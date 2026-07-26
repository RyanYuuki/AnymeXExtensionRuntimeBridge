package com.anymex.desktop.cloudstream

import com.google.gson.Gson
import com.google.gson.JsonObject
import com.lagradost.cloudstream3.Log
import com.lagradost.cloudstream3.*
import java.io.File
import java.net.URLClassLoader
import java.util.zip.ZipFile

import android.app.Application
import android.content.Context
import eu.kanade.tachiyomi.network.NetworkHelper
import kotlinx.serialization.json.Json
import uy.kohesive.injekt.Injekt
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import uy.kohesive.injekt.api.addSingletonFactory
import uy.kohesive.injekt.api.get

import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withTimeout

object CloudStreamExtensionLoader {
    val loadedMap = ConcurrentHashMap<String, MainAPI>()
    private val classLoaders = ConcurrentHashMap<String, URLClassLoader>()
    private val scanMutex = Mutex()
    private val gson = Gson()
    private var initialized = false

    fun initialize() {
        if (initialized) return
        
        val context = Application()
        
        Injekt.addSingletonFactory<Application> { context }
        Injekt.addSingletonFactory<Context> { context }
        Injekt.addSingletonFactory { NetworkHelper(context) }
        Injekt.addSingletonFactory<okhttp3.OkHttpClient> { Injekt.get<NetworkHelper>().client }
        Injekt.addSingletonFactory<Json> {
            Json {
                ignoreUnknownKeys = true
                explicitNulls = false
            }
        }
        initialized = true
        System.err.println("CloudStream Runtime initialized!")
    }

    suspend fun loadExtensions(folderPath: String): String = scanMutex.withLock {
        initialize()
        val folder = File(folderPath)
        if (!folder.exists() || !folder.isDirectory) return "[]"

        val jsonArray = com.google.gson.JsonArray()

        folder.listFiles { file -> file.extension == "jar" }?.forEach { jar ->
            System.err.println("[CS] Scanning: ${jar.name}")
            
            val jarProcessThread = Thread {
                try {
                    val zipFile = ZipFile(jar)
                    val manifestEntry = zipFile.getEntry("manifest.json") ?: zipFile.getEntry("plugins.manifest")
                    if (manifestEntry == null) {
                        System.err.println("  [CS] Skipped ${jar.name}: no manifest.json or plugins.manifest found")
                        zipFile.close()
                        return@Thread
                    }

                    val manifestContent = zipFile.getInputStream(manifestEntry).bufferedReader().use { it.readText() }
                    val manifest = gson.fromJson(manifestContent, JsonObject::class.java)
                    val pluginClassName = manifest.get("pluginClassName")?.asString ?: ""
                    val version = manifest.get("version")?.asString ?: "1.0.0"
                    System.err.println("  [CS] Manifest: pluginClassName='$pluginClassName' version='$version'")
                    zipFile.close()

                    val tempJar = File.createTempFile("cs_ext_", ".jar").apply { deleteOnExit() }
                    jar.copyTo(tempJar, overwrite = true)
                    val classLoader = com.anymex.desktop.ChildFirstURLClassLoader(arrayOf(tempJar.toURI().toURL()), CloudStreamExtensionLoader::class.java.classLoader)
                    
                    val pluginClass = if (pluginClassName.isNotEmpty()) {
                        try { Class.forName(pluginClassName, false, classLoader) } catch (e: Throwable) {
                            System.err.println("  [CS] Could not load pluginClass '$pluginClassName': ${e.javaClass.simpleName}: ${e.message}")
                            null
                        }
                    } else null

                    if (pluginClass != null) {
                        try {
                            populatePlugin(pluginClass, version, pluginClassName, jsonArray)
                        } catch (e: Throwable) {
                            System.err.println("  [CS] Error initializing $pluginClassName: ${e.message}")
                        }
                    }

                    val beforeCount = jsonArray.size()
                    findMainApisInJar(jar, classLoader, version, jsonArray)
                    val afterCount = jsonArray.size()
                    if (afterCount == beforeCount && pluginClass == null) {
                        System.err.println("  [CS] No APIs found in ${jar.name}")
                    }
                    classLoaders[jar.absolutePath] = classLoader
                } catch (e: Throwable) {
                    System.err.println("  [CS] Error processing ${jar.name}: ${e.javaClass.simpleName}: ${e.message}")
                }
            }
            
            jarProcessThread.isDaemon = true
            jarProcessThread.start()
            jarProcessThread.join(20000L)

            if (jarProcessThread.isAlive) {
                System.err.println("  [CS] Warning: JAR ${jar.name} HUNG during processing and was bypassed.")
            }
        }

        val finalJson = gson.toJson(jsonArray)
        System.err.println("[CS] Scan complete. Found ${jsonArray.size()} providers.")
        return finalJson
    }

    private fun populatePlugin(pluginClass: Class<*>, version: String, className: String, jsonArray: com.google.gson.JsonArray): Any? {
        val instance = instantiateApi(pluginClass) ?: return null
        
        if (instance is com.lagradost.cloudstream3.plugins.Plugin) {
            val preApis = com.lagradost.cloudstream3.APIHolder.apis.toList()
            val context = android.app.Application()
            val loadThread = Thread {
                try {
                    val contextClass = android.content.Context::class.java
                    val loadWithContext = try {
                        pluginClass.getMethod("load", contextClass)
                    } catch (e: NoSuchMethodException) { null }

                    if (loadWithContext != null) {
                        System.err.println("  [CS] Calling load(Context) on $className")
                        loadWithContext.invoke(instance, context)
                    } else {
                        System.err.println("  [CS] Calling load() on $className (no Context overload)")
                        instance.load(null)
                    }
                } catch (e: Throwable) {
                    val cause = e.cause ?: e
                    System.err.println("  [CS] load() failed for $className: ${cause.javaClass.simpleName}: ${cause.message}")
                }
            }
            loadThread.isDaemon = true
            loadThread.start()
            loadThread.join(10000L)
            
            val postApis = com.lagradost.cloudstream3.APIHolder.apis.toList()
            val newApis = postApis.filter { it !in preApis }
            if (newApis.isNotEmpty()) {
                System.err.println("  [CS] Plugin $className registered ${newApis.size} API(s)")
                newApis.forEach { addApiToJson(it, version, it.javaClass.name, jsonArray) }
                return instance
            } else {
                System.err.println("  [CS] Plugin $className registered 0 APIs after load()")
            }
        }
        
        if (isMainApiClass(pluginClass)) {
            val api = instance as? MainAPI
            if (api != null) {
                addApiToJson(api, version, className, jsonArray)
                return instance
            }
        }
        return null
    }

    private fun addApiToJson(apiInstance: MainAPI, version: String, className: String, jsonArray: com.google.gson.JsonArray) {
        val idStr = "cs_" + apiInstance.name.replace(Regex("[^a-zA-Z0-9]"), "").lowercase()
        
        synchronized(jsonArray) {
            if (jsonArray.any { it.asJsonObject.get("id").asString == idStr }) return

            System.err.println("  [CS] Found API: ${apiInstance.name}")
            
            val extObj = JsonObject().apply {
                addProperty("id", idStr)
                addProperty("name", apiInstance.name)
                addProperty("lang", apiInstance.lang)
                addProperty("type", "anime")
                addProperty("baseUrl", apiInstance.mainUrl)
                addProperty("isNsfw", false)
                addProperty("version", version)
                addProperty("pkgName", "cloudstream.plugin")
                addProperty("className", className)
                addProperty("itemType", 1)
                addProperty("hasUpdate", false)
                addProperty("isObsolete", false)
                addProperty("isShared", false)
            }
            jsonArray.add(extObj)
            loadedMap[idStr] = apiInstance
        }
    }

    private fun isMainApiClass(clazz: Class<*>): Boolean {
        if (clazz.isInterface || java.lang.reflect.Modifier.isAbstract(clazz.modifiers)) return false
        if (MainAPI::class.java.isAssignableFrom(clazz)) return true
        
        var curr: Class<*>? = clazz
        while (curr != null) {
            val name = curr.name
            if (name.contains("MainAPI") || name.contains("Provider")) return true
            if (curr.interfaces.any { it.name.contains("MainAPI") || it.name.contains("Provider") }) return true
            curr = curr.superclass
        }
        return false
    }

    private fun findMainApisInJar(jar: File, classLoader: URLClassLoader, version: String, jsonArray: com.google.gson.JsonArray) {
        val zipFile = ZipFile(jar)
        val candidates = zipFile.entries()
            .toList()
            .filter { it.name.endsWith(".class") && !it.name.contains("$") }
        System.err.println("  [CS] Inspecting ${candidates.size} top-level classes in ${jar.name}")
        for (entry in candidates) {
            val className = entry.name.replace('/', '.').replace('\\', '.').removeSuffix(".class")
            try {
                val clazz = Class.forName(className, false, classLoader)
                if (isMainApiClass(clazz)) {
                    System.err.println("  [CS] Candidate API class: $className")
                    val apiInstance = instantiateApi(clazz) as? MainAPI
                    if (apiInstance != null) {
                        addApiToJson(apiInstance, version, className, jsonArray)
                    } else {
                        System.err.println("    [CS] Could not instantiate $className (not a MainAPI or instantiation failed)")
                    }
                }
            } catch (e: Throwable) {
                System.err.println("    [CS] Skipped $className: ${e.javaClass.simpleName}: ${e.message}")
            }
        }
        zipFile.close()
    }

    private fun instantiateApi(clazz: Class<*>): Any? {
        return try {
            clazz.getDeclaredConstructor().newInstance()
        } catch (e: Throwable) {
            try {
                clazz.getDeclaredField("INSTANCE").get(null)
            } catch (e2: Throwable) {
                null
            }
        }
    }

    suspend fun search(sourceId: String, query: String, page: Int): String = withContext(Dispatchers.IO) {
        val api = loadedMap[sourceId] ?: return@withContext "{\"list\": [], \"hasNextPage\": false}"
        try {
            withTimeout(60000L) {
                val methods = CloudStreamSourceMethods(api)
                val result = methods.search(query, page)
                gson.toJson(result)
            }
        } catch (e: Throwable) {
            System.err.println("[CS-Loader] ERROR: Outer search wrapper failed for $sourceId: ${e.message}")
            e.printStackTrace()
            "{\"list\": [], \"hasNextPage\": false}"
        }
    }

    suspend fun fetchDetails(sourceId: String, url: String): String = withContext(Dispatchers.IO) {
        val api = loadedMap[sourceId] ?: return@withContext "{}"
        try {
            withTimeout(60000L) {
                val methods = CloudStreamSourceMethods(api)
                val result = methods.getDetails(url)
                gson.toJson(result)
            }
        } catch (e: Throwable) {
            "{}"
        }
    }

    suspend fun fetchVideoList(sourceId: String, url: String): String = withContext(Dispatchers.IO) {
        val api = loadedMap[sourceId] ?: return@withContext "[]"
        try {
            withTimeout(60000L) {
                val methods = CloudStreamSourceMethods(api)
                val links = methods.loadLinks(url)
                gson.toJson(links)
            }
        } catch (e: Throwable) {
            "[]"
        }
    }

    suspend fun fetchVideoListStream(sourceId: String, url: String, onLinkFound: (String) -> Unit) = withContext(Dispatchers.IO) {
        val api = loadedMap[sourceId] ?: return@withContext
        try {
            withTimeout(120000L) {
                val methods = CloudStreamSourceMethods(api)
                methods.loadLinksStream(url) { link ->
                    onLinkFound(gson.toJson(link))
                }
            }
        } catch (e: Throwable) {
        }
    }
}
