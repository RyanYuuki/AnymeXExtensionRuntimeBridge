package com.ryan.runtimebridge

import android.app.Activity
import android.content.Context
import android.util.Log
import dalvik.system.DexClassLoader
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.runBlocking
import android.net.Uri
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.lang.reflect.InvocationHandler

class AnymeXBridgePlugin : FlutterPlugin, ActivityAware {

    private val TAG = "AnymeXBridge"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private lateinit var anymeXChannel: MethodChannel
    private lateinit var aniyomiChannel: MethodChannel
    private lateinit var cloudStreamChannel: MethodChannel
    private lateinit var videoStreamEventChannel: EventChannel

    private var context: Context? = null
    private var activity: Activity? = null

    private var runtimeBridge: Any? = null
    private var bridgeClass: Class<*>? = null
    private var videoStreamJob: kotlinx.coroutines.Job? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        anymeXChannel = MethodChannel(binding.binaryMessenger, "anymeXBridge")
        anymeXChannel.setMethodCallHandler { call, result -> handleAnymeX(call, result) }

        aniyomiChannel = MethodChannel(binding.binaryMessenger, "aniyomiExtensionBridge")
        aniyomiChannel.setMethodCallHandler { call, result -> handleAniyomi(call, result) }

        cloudStreamChannel = MethodChannel(binding.binaryMessenger, "cloudstreamExtensionBridge")
        cloudStreamChannel.setMethodCallHandler { call, result -> handleCloudStream(call, result) }

        videoStreamEventChannel = EventChannel(binding.binaryMessenger, "cloudstreamExtensionBridge/videoStream")
        videoStreamEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                val args = arguments as? Map<*, *> ?: return
                val apiName = args["apiName"] as? String ?: return
                val url = args["url"] as? String ?: return
                handleVideoStream(apiName, url, events)
            }
            override fun onCancel(arguments: Any?) {
                videoStreamJob?.cancel()
                videoStreamJob = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        anymeXChannel.setMethodCallHandler(null)
        aniyomiChannel.setMethodCallHandler(null)
        cloudStreamChannel.setMethodCallHandler(null)
        videoStreamEventChannel.setStreamHandler(null)
        videoStreamJob?.cancel()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    private fun loadAnymeXRuntimeHost(apkPath: String): Boolean {
        Log.i(TAG, "loadAnymeXRuntimeHost called with: $apkPath")
        val ctx = context ?: run {
            Log.e(TAG, "loadAnymeXRuntimeHost: context is null")
            return false
        }

        return try {
            runtimeBridge = null
            bridgeClass = null

            val cacheApk = File(ctx.filesDir, "anymex_runtime_host.apk")
            val optimizedDir = File(ctx.cacheDir, "anymex_dex")
            
            if (cacheApk.exists()) cacheApk.delete()
            if (optimizedDir.exists()) optimizedDir.deleteRecursively()
            optimizedDir.mkdirs()

            Log.d(TAG, "Copying APK to internal storage...")
            val inputStream: InputStream? = if (apkPath.startsWith("content://")) {
                Log.d(TAG, "Detected content URI, using ContentResolver")
                ctx.contentResolver.openInputStream(Uri.parse(apkPath))
            } else {
                Log.d(TAG, "Detected file path, using FileInputStream")
                File(apkPath).inputStream()
            }

            if (inputStream == null) {
                Log.e(TAG, "Failed to open input stream for $apkPath")
                return false
            }

            inputStream.use { input ->
                FileOutputStream(cacheApk).use { output ->
                    input.copyTo(output)
                }
            }
            
            val totalBytes = cacheApk.length()
            Log.i(TAG, "APK copied successfully ($totalBytes bytes) to ${cacheApk.absolutePath}")
            cacheApk.setReadOnly()

            val loader = ChildFirstClassLoader(
                cacheApk.absolutePath,
                optimizedDir.absolutePath,
                null,
                ctx.classLoader!!
            )

            bridgeClass = loader.loadClass("com.anymex.runtimehost.RuntimeBridge")
            Log.d(TAG, "bridgeClass loaded: $bridgeClass")
            runtimeBridge = bridgeClass!!.getField("INSTANCE").get(null)
            Log.d(TAG, "runtimeBridge assigned: $runtimeBridge")

            call("initialize", ctx)

            Log.i(TAG, "Runtime Host loaded successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load Runtime Host APK: ${e.message}", e)
            false
        }
    }

    private fun handleAnymeX(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadAnymeXRuntimeHost" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("INVALID_ARG", "path is required", null)
                    return
                }
                scope.launch {
                    val ok = loadAnymeXRuntimeHost(path)
                    withContext(Dispatchers.Main) {
                        if (ok) result.success(true)
                        else result.error("LOAD_FAILED", "Failed to load runtime host APK", null)
                    }
                }
            }
            "isLoaded" -> {
                Log.d(TAG, "isLoaded check: runtimeBridge=$runtimeBridge, bridgeClass=$bridgeClass")
                result.success(runtimeBridge != null)
            }
            else -> result.notImplemented()
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun handleAniyomi(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureLoaded(result)) return
        val ctx = effectiveContext() ?: return result.error("NO_CTX", "No context", null)

        scope.launch {
            try {
                val res: Any? = when (call.method) {
                    "getInstalledAnimeExtensions" -> {
                        val path = call.arguments as? String?
                        call("getInstalledAnimeExtensions", ctx, path)
                    }
                    "getInstalledMangaExtensions" -> {
                        call("getInstalledMangaExtensions", ctx)
                    }
                    "getPopular" -> {
                        val args = call.arguments as Map<*, *>
                        call("aniyomiGetPopular", ctx,
                            args["sourceId"] as String,
                            args["isAnime"] as Boolean,
                            args["page"] as Int)
                    }
                    "getLatestUpdates" -> {
                        val args = call.arguments as Map<*, *>
                        call("aniyomiGetLatestUpdates", ctx,
                            args["sourceId"] as String,
                            args["isAnime"] as Boolean,
                            args["page"] as Int)
                    }
                    "search" -> {
                        val args = call.arguments as Map<*, *>
                        call("aniyomiSearch", ctx,
                            args["sourceId"] as String,
                            args["isAnime"] as Boolean,
                            args["query"] as String,
                            args["page"] as Int)
                    }
                    "getDetail" -> {
                        val args = call.arguments as Map<*, *>
                        call("aniyomiGetDetail", ctx,
                            args["sourceId"] as String,
                            args["isAnime"] as Boolean,
                            args["media"] as Map<String, Any?>)
                    }
                    "getVideoList" -> {
                        val args = call.arguments as Map<*, *>
                        call("aniyomiGetVideoList", ctx,
                            args["sourceId"] as String,
                            args["isAnime"] as Boolean,
                            args["episode"] as Map<String, Any?>)
                    }
                    "getPageList" -> {
                        val args = call.arguments as Map<*, *>
                        call("aniyomiGetPageList", ctx,
                            args["sourceId"] as String,
                            args["isAnime"] as Boolean,
                            args["episode"] as Map<String, Any?>)
                    }
                    "getPreference" -> {
                        val args = call.arguments as Map<*, *>
                        call("aniyomiGetPreference", ctx,
                            args["sourceId"] as String,
                            args["isAnime"] as Boolean)
                    }
                    "saveSourcePreference" -> {
                        val args = call.arguments as Map<*, *>
                        call("aniyomiSavePreference", ctx,
                            args["sourceId"] as String,
                            args["key"] as String,
                            args["action"] as? String,
                            args["value"])
                    }
                    else -> { withContext(Dispatchers.Main) { result.notImplemented() }; return@launch }
                }
                withContext(Dispatchers.Main) { result.success(res) }
            } catch (e: Exception) {
                Log.e(TAG, "Aniyomi call failed [${call.method}]: ${e.message}", e)
                withContext(Dispatchers.Main) { result.error("ERROR", e.message, null) }
            }
        }
    }

    private fun handleCloudStream(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureLoaded(result)) return
        val ctx = effectiveContext() ?: return result.error("NO_CTX", "No context", null)

        when (call.method) {
            "initialize" -> {
                call("initialize", ctx)
                result.success(null)
                return
            }
            "getRegisteredProviders" -> {
                result.success(call("csGetRegisteredProviders"))
                return
            }
        }

        scope.launch {
            try {
                val res: Any? = when (call.method) {
                    "loadLocalPlugins" -> call("csLoadLocalPlugins", ctx)
                    "loadPlugin" -> {
                        val path = call.argument<String>("path")
                            ?: return@launch withContext(Dispatchers.Main) {
                                result.error("INVALID_ARG", "path required", null)
                            }
                        call("csLoadPlugin", ctx, path)
                    }
                    "downloadPlugin" -> {
                        call("csDownloadPlugin", ctx,
                            call.argument<String>("pluginUrl") ?: "",
                            call.argument<String>("internalName") ?: "",
                            call.argument<String>("repositoryUrl") ?: "")
                    }
                    "deletePlugin" -> {
                        call("csDeletePlugin", ctx,
                            call.argument<String>("internalName") ?: "",
                            call.argument<String>("repositoryUrl") ?: "")
                    }
                    "search" -> {
                        call("csSearch", ctx,
                            call.argument<String>("query") ?: "",
                            call.argument<String>("apiName"),
                            call.argument<Int>("page") ?: 1)
                    }
                    "getDetail" -> {
                        call("csGetDetail", ctx,
                            call.argument<String>("apiName") ?: "",
                            call.argument<String>("url") ?: "")
                    }
                    "getVideoList" -> {
                        call("csGetVideoList", ctx,
                            call.argument<String>("apiName") ?: "",
                            call.argument<String>("url") ?: "")
                    }
                    "getExtensionSettings" -> {
                        call("csGetExtensionSettings", ctx,
                            call.argument<String>("pluginName") ?: "")
                    }
                    "setExtensionSettings" -> {
                        call("csSetExtensionSettings", ctx,
                            call.argument<String>("pluginName") ?: "",
                            call.argument<String>("key") ?: "",
                            call.argument<Any>("value"))
                    }
                    else -> { withContext(Dispatchers.Main) { result.notImplemented() }; return@launch }
                }
                withContext(Dispatchers.Main) { result.success(res) }
            } catch (e: Exception) {
                Log.e(TAG, "CloudStream call failed [${call.method}]: ${e.message}", e)
                withContext(Dispatchers.Main) { result.error("ERROR", e.message, null) }
            }
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun handleVideoStream(apiName: String, url: String, events: EventChannel.EventSink?) {
        val ctx = effectiveContext() ?: run {
            events?.error("NO_CTX", "No context available", null)
            events?.endOfStream()
            return
        }

        videoStreamJob?.cancel()
        videoStreamJob = scope.launch {
            try {
                val cls = bridgeClass ?: throw IllegalStateException("Runtime Host not loaded")
                val loader = cls.classLoader ?: throw IllegalStateException("No Host ClassLoader")
                val function1Class = loader.loadClass("kotlin.jvm.functions.Function1")
                val unitClass = loader.loadClass("kotlin.Unit")
                val unitInstance = unitClass.getField("INSTANCE").get(null)

                val proxyCallback = Proxy.newProxyInstance(
                    loader,
                    arrayOf(function1Class),
                    object : InvocationHandler {
                        override fun invoke(proxy: Any?, method: Method?, args: Array<out Any?>?): Any? {
                            if (method?.name == "invoke") {
                                val video = args?.get(0)
                                runBlocking(Dispatchers.Main) { 
                                    events?.success(video)
                                }
                                return unitInstance
                            }
                            return null
                        }
                    }
                )

                call("csGetVideoListStream", ctx, apiName, url, proxyCallback)
                withContext(Dispatchers.Main) { events?.endOfStream() }
            } catch (e: Exception) {
                Log.e(TAG, "videoStream failed: ${e.message}", e)
                withContext(Dispatchers.Main) {
                    events?.error("VIDEO_STREAM_FAILED", e.message, null)
                    events?.endOfStream()
                }
            }
        }
    }

    private fun call(methodName: String, vararg args: Any?): Any? {
        val bridge = runtimeBridge ?: throw IllegalStateException("Runtime Host not loaded")
        val cls = bridgeClass ?: throw IllegalStateException("Runtime Host class not loaded")

        val method = cls.methods.firstOrNull { it.name == methodName }
            ?: throw NoSuchMethodException("No method '$methodName' in RuntimeBridge")

        return method.invoke(bridge, *args)
    }

    private fun ensureLoaded(result: MethodChannel.Result): Boolean {
        if (runtimeBridge == null) {
            result.error("NOT_LOADED", "Runtime Host APK not loaded. Call loadAnymeXRuntimeHost first.", null)
            return false
        }
        return true
    }

    private fun effectiveContext(): Context? = activity ?: context

    private class ChildFirstClassLoader(
        dexPath: String,
        optimizedDirectory: String?,
        librarySearchPath: String?,
        parent: ClassLoader
    ) : DexClassLoader(dexPath, optimizedDirectory, librarySearchPath, parent) {

        private val systemClassLoader: ClassLoader? = getSystemClassLoader()

        override fun loadClass(name: String?, resolve: Boolean): Class<*> {
            var c = findLoadedClass(name)

            if (c == null && systemClassLoader != null) {
                try {
                    c = systemClassLoader.loadClass(name)
                } catch (_: ClassNotFoundException) {}
            }

            if (c == null) {
                try {
                    c = findClass(name)
                } catch (_: ClassNotFoundException) {
                    c = super.loadClass(name, resolve)
                }
            }

            if (resolve) {
                resolveClass(c)
            }

            return c
        }
    }
}