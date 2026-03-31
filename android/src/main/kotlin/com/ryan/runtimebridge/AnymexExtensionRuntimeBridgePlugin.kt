package com.ryan.runtimebridge

import android.app.Activity
import android.content.Context
import android.util.Log
import dalvik.system.DexClassLoader
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink as MethodEventSink
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result as MethodResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.isActive
import kotlinx.coroutines.cancel
import android.net.Uri
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.lang.reflect.InvocationHandler

class AnymexExtensionRuntimeBridgePlugin : FlutterPlugin, ActivityAware {

    private val TAG = "AnymeXBridge"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private lateinit var anymeXChannel: MethodChannel
    private lateinit var aniyomiChannel: MethodChannel
    private lateinit var cloudStreamChannel: MethodChannel
    private lateinit var videoStreamEventChannel: EventChannel
    private lateinit var loggingChannel: MethodChannel


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
            override fun onListen(arguments: Any?, events: MethodEventSink?) {
                val args = arguments as? Map<*, *> ?: return
                val apiName = args["apiName"] as? String ?: return
                val url = args["url"] as? String ?: return
                val params = (args["parameters"] as? Map<String, Any?>)?.toMutableMap() ?: mutableMapOf()
                if (args.containsKey("token")) {
                    params["token"] = args["token"]
                }
                handleVideoStream(apiName, url, params, events)
            }
            override fun onCancel(arguments: Any?) {
                videoStreamJob?.cancel()
                videoStreamJob = null
            }
        })

        loggingChannel = MethodChannel(binding.binaryMessenger, "anymexLogger")
        loggingChannel.setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                flutterReady = true
                logQueue.forEach { logMap ->
                    try {
                        loggingChannel.invokeMethod("log", logMap)
                    } catch (e: Exception) {}
                }
                logQueue.clear()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        anymeXChannel.setMethodCallHandler(null)
        aniyomiChannel.setMethodCallHandler(null)
        cloudStreamChannel.setMethodCallHandler(null)
        videoStreamEventChannel.setStreamHandler(null)
        videoStreamJob?.cancel()
        scope.cancel()
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

    private fun loadAnymeXRuntimeHost(apkPath: String, settingsMap: Map<String, Any?>? = null): Boolean {
        Log.i(TAG, "loadAnymeXRuntimeHost called with: $apkPath")
        val ctx = context ?: run {
            Log.e(TAG, "loadAnymeXRuntimeHost: context is null")
            return false
        }

        runtimeBridge?.let { oldBridge ->
            try {
                Log.i(TAG, "Shutting down existing runtime host...")
                bridgeClass?.getMethod("shutdown")?.invoke(oldBridge)
            } catch (e: Exception) {
                Log.e(TAG, "Error shutting down old runtime host: ${e.message}")
            }
        }

        return try {
            runtimeBridge = null
            bridgeClass = null

            val originalApk = File(apkPath)
            if (!originalApk.exists()) {
                Log.e(TAG, "APK does not exist at path: $apkPath")
                return false
            }
            Log.i(TAG, "Loading APK: $apkPath Size: ${originalApk.length()} LastModified: ${originalApk.lastModified()}")

            val cacheApkName = "anymex_runtime_${originalApk.length()}_${originalApk.lastModified()}.apk"
            val cacheApk = File(ctx.filesDir, cacheApkName)

            if (!cacheApk.exists()) {
                Log.i(TAG, "Creating new cached APK: $cacheApkName")
                ctx.filesDir.listFiles()?.forEach { file ->
                    if (file.name.startsWith("anymex_runtime_") && file.name.endsWith(".apk") && file.name != cacheApkName) {
                        Log.d(TAG, "Deleting old cached APK: ${file.name}")
                        file.delete()
                    }
                }

                originalApk.inputStream().use { input ->
                    FileOutputStream(cacheApk).use { output ->
                        input.copyTo(output)
                    }
                }
                cacheApk.setReadOnly()
            } else {
                Log.i(TAG, "Using existing cached APK: $cacheApkName")
            }

            ctx.cacheDir.listFiles()?.forEach { file ->
                if (file.isDirectory && file.name.startsWith("anymex_dex_")) {
                    file.deleteRecursively()
                }
            }

            val optimizedDir = File(ctx.cacheDir, "anymex_dex_${System.currentTimeMillis()}")
            optimizedDir.mkdirs()

            Log.d(TAG, "Using optimized dex dir: ${optimizedDir.absolutePath}")

            val loader = ChildFirstClassLoader(
                cacheApk.absolutePath,
                optimizedDir.absolutePath,
                cacheApk.absolutePath,
                ctx.classLoader!!
            )

            bridgeClass = loader.loadClass("com.anymex.runtimehost.RuntimeBridge")
            Log.d(TAG, "bridgeClass loaded: $bridgeClass")
            runtimeBridge = bridgeClass!!.getField("INSTANCE").get(null)
            call("initialize", ctx, settingsMap)

            Log.i(TAG, "Runtime Host loaded successfully")
            true
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to load Runtime Host APK: ${e.message}")
            false
        }
    }

    private fun handleAnymeX(call: MethodCall, result: MethodResult) {
        when (call.method) {
            "loadAnymeXRuntimeHost" -> {
                val path = call.argument<String>("path")
                val settingsMap = call.argument<Map<String, Any?>>("settings")
                if (path.isNullOrBlank()) {
                    result.error("INVALID_ARG", "path is required", null)
                    return
                }
                scope.launch {
                    try {
                        val ok = loadAnymeXRuntimeHost(path, settingsMap)
                        withContext(Dispatchers.Main) {
                            if (ok) result.success(true)
                            else result.error("LOAD_FAILED", "Failed to load runtime host APK", null)
                        }
                    } catch (e: Throwable) {
                        sendError(result, "loadAnymeXRuntimeHost", e)
                    }
                }
            }
            "isLoaded" -> {
                Log.d(TAG, "isLoaded check: runtimeBridge=$runtimeBridge, bridgeClass=$bridgeClass")
                result.success(runtimeBridge != null)
            }
            "cancelRequest" -> {
                val token = call.argument<String>("token")
                if (token != null) {
                    val ok = call("cancelRequest", token) as? Boolean ?: false
                    result.success(ok)
                } else {
                    result.error("INVALID_ARG", "token is required", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun handleAniyomi(call: MethodCall, result: MethodResult) {
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
                            args["page"] as Int,
                            args["parameters"] as? Map<String, Any?>)
                    }
                    "getLatestUpdates" -> {
                        val args = call.arguments as Map<*, *>
                        call("aniyomiGetLatestUpdates", ctx,
                            args["sourceId"] as String,
                            args["isAnime"] as Boolean,
                            args["page"] as Int,
                            args["parameters"] as? Map<String, Any?>)
                    }
                    "search" -> {
                        val args = call.arguments as Map<*, *>
                        call("aniyomiSearch", ctx,
                            args["sourceId"] as String,
                            args["isAnime"] as Boolean,
                            args["query"] as String,
                            args["page"] as Int,
                            args["parameters"] as? Map<String, Any?>)
                    }
                    "getDetail" -> {
                        val args = call.arguments as Map<*, *>
                        call("aniyomiGetDetail", ctx,
                            args["sourceId"] as String,
                            args["isAnime"] as Boolean,
                            args["media"] as Map<String, Any?>,
                            args["parameters"] as? Map<String, Any?>)
                    }
                    "getVideoList" -> {
                        val args = call.arguments as Map<*, *>
                        call("aniyomiGetVideoList", ctx,
                            args["sourceId"] as String,
                            args["isAnime"] as Boolean,
                            args["episode"] as Map<String, Any?>,
                            args["parameters"] as? Map<String, Any?>)
                    }
                    "getPageList" -> {
                        val args = call.arguments as Map<*, *>
                        call("aniyomiGetPageList", ctx,
                            args["sourceId"] as String,
                            args["isAnime"] as Boolean,
                            args["episode"] as Map<String, Any?>,
                            args["parameters"] as? Map<String, Any?>)
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
            } catch (e: Throwable) {
                sendError(result, "Aniyomi.${call.method}", e)
            }
        }
    }

    private fun handleCloudStream(call: MethodCall, result: MethodResult) {
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
                    "loadPlugin" -> {
                        val path = call.argument<String>("path")
                            ?: return@launch withContext(Dispatchers.Main) {
                                result.error("INVALID_ARG", "path required", null)
                            }
                        call("csLoadPlugin", ctx, path)
                    }
                    "search" -> {
                        call("csSearch", ctx,
                            call.argument<String>("query") ?: "",
                            call.argument<String>("apiName"),
                            call.argument<Int>("page") ?: 1,
                            call.argument<Map<String, Any?>>("parameters"))
                    }
                    "getDetail" -> {
                        call("csGetDetail", ctx,
                            call.argument<String>("apiName") ?: "",
                            call.argument<String>("url") ?: "",
                            call.argument<Map<String, Any?>>("parameters"))
                    }
                    "getVideoList" -> {
                        call("csGetVideoList", ctx,
                            call.argument<String>("apiName") ?: "",
                            call.argument<String>("url") ?: "",
                            call.argument<Map<String, Any?>>("parameters"))
                    }
                    "deletePlugin" -> {
                        val internalName = call.argument<String>("internalName")
                            ?: return@launch withContext(Dispatchers.Main) {
                                result.error("INVALID_ARG", "internalName required", null)
                            }
                        call("csUnloadPlugin", internalName)
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
            } catch (e: Throwable) {
                sendError(result, "CloudStream.${call.method}", e)
            }
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun handleVideoStream(apiName: String, url: String, parameters: Map<String, Any?>?, events: MethodEventSink?) {
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

                call("csGetVideoListStream", ctx, apiName, url, proxyCallback, parameters)
                withContext(Dispatchers.Main) { events?.endOfStream() }
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: Throwable) {
                sendError(result = object : MethodResult {
                    override fun success(res: Any?) {}
                    override fun error(code: String, msg: String?, details: Any?) {
                        events?.error(code, msg, details)
                    }
                    override fun notImplemented() {
                        events?.endOfStream()
                    }
                }, methodName = "videoStream", e = e)
                withContext(Dispatchers.Main) { events?.endOfStream() }
            }
        }
    }

    private fun sendError(result: MethodResult, methodName: String, e: Throwable) {
        val stackTrace = Log.getStackTraceString(e)
        val errorMessage = e.message ?: "Unknown error"
        val detailedError = "Method: $methodName\nError: $errorMessage\n$stackTrace"

        Log.e(TAG, detailedError)
        logToFlutter("ERROR", "BRIDGE", detailedError)

        scope.launch(Dispatchers.Main) {
            result.error("BRIDGE_ERROR", errorMessage, detailedError)
        }
    }

    private fun call(methodName: String, vararg args: Any?): Any? {
        val bridge = runtimeBridge ?: throw IllegalStateException("Runtime Host not loaded")
        val cls = bridgeClass ?: throw IllegalStateException("Runtime Host class not loaded")

        val method = cls.methods.filter { it.name == methodName }
            .firstOrNull { it.parameterTypes.size == args.size }
            ?: cls.methods.firstOrNull { it.name == methodName }
            ?: throw NoSuchMethodException("No method '$methodName' in RuntimeBridge")

        val effectiveArgs = if (method.parameterTypes.size != args.size) {
            logToFlutter("WARNING", "BRIDGE", "Argument count mismatch for $methodName. Expected ${method.parameterTypes.size}, got ${args.size}. Adjusting.")
            if (args.size > method.parameterTypes.size) {
                args.take(method.parameterTypes.size).toTypedArray()
            } else {
                val padded = args.toMutableList()
                while (padded.size < method.parameterTypes.size) padded.add(null)
                padded.toTypedArray()
            }
        } else {
            args
        }

        logToFlutter("INFO", "BRIDGE", "Calling Method: RuntimeBridge.$methodName")
        val result = method.invoke(bridge, *effectiveArgs)
        logToFlutter("INFO", "BRIDGE", "Method '$methodName' completed successfully")

        return result
    }

    private fun ensureLoaded(result: MethodResult): Boolean {
        if (runtimeBridge == null) {
            result.error("NOT_LOADED", "Runtime Host APK not loaded. Call loadAnymeXRuntimeHost first.", null)
            return false
        }
        return true
    }

    private fun effectiveContext(): Context? = activity ?: context

    private val logQueue = mutableListOf<Map<String, String>>()
    private var flutterReady = false

    private fun logToFlutter(level: String, tag: String, message: String) {
        scope.launch(Dispatchers.Main) {
            val logMap = mapOf("level" to level, "tag" to tag, "message" to message)
            if (flutterReady) {
                try {
                    loggingChannel.invokeMethod("log", logMap)
                } catch (e: Exception) {}
            } else {
                logQueue.add(logMap)
                if (logQueue.size > 2000) logQueue.removeAt(0)
            }
        }
    }

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