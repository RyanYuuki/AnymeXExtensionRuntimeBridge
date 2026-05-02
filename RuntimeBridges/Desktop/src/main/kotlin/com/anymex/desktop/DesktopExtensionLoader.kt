package com.anymex.desktop

import android.app.Application
import android.content.Context
import eu.kanade.tachiyomi.animesource.AnimeSource
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.AnimeSourceFactory
import eu.kanade.tachiyomi.animesource.ConfigurableAnimeSource
import eu.kanade.tachiyomi.animesource.model.*
import eu.kanade.tachiyomi.source.MangaSource
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.SourceFactory
import eu.kanade.tachiyomi.source.ConfigurableSource
import eu.kanade.tachiyomi.source.model.*
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.util.lang.awaitSingle
import eu.kanade.tachiyomi.PreferenceScreen as EuPreferenceScreen
import androidx.preference.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingletonFactory
import uy.kohesive.injekt.api.get
import java.io.File
import java.net.URLClassLoader
import java.util.zip.ZipFile
import com.google.gson.Gson
import com.google.gson.JsonArray
import com.google.gson.JsonElement
import com.google.gson.JsonObject
import kotlinx.coroutines.*
import java.util.concurrent.ConcurrentHashMap
import tachiyomi.core.util.lang.awaitSingle
import okhttp3.Protocol
import kotlinx.coroutines.asContextElement

object DesktopExtensionLoader {
    private val gson = Gson()
    val loadedAnimeSources = mutableMapOf<String, AnimeSource>()
    val loadedMangaSources = mutableMapOf<String, MangaSource>()
    private val classLoaders = mutableMapOf<String, URLClassLoader>()
    private var initialized = false

    private data class PrefHandlers(
        val pref: Preference,
        val click: Preference.OnPreferenceClickListener?,
        val change: Preference.OnPreferenceChangeListener?
    )
    private val sourcePreferences = mutableMapOf<String, MutableMap<String, PrefHandlers>>()
}

fun main(args: Array<String>) = runBlocking {
    val reader = System.`in`.bufferedReader(Charsets.UTF_8)
    val originalOut = System.`out`
    val cleanOut = java.io.PrintStream(originalOut, true, "UTF-8")
    
    System.setOut(java.io.PrintStream(System.err, true, "UTF-8"))

    val gson = Gson()
    
    val activeJobs = ConcurrentHashMap<String, Job>()
    val outLock = Any()

    System.err.println("AnymeX Sidecar Process Started")
    System.err.println("All stdout has been redirected to stderr for IPC safety.")

    while (true) {
        val line = try { reader.readLine() } catch (e: Exception) { null } ?: break
        if (line.isBlank()) continue

        launch(Dispatchers.IO) {
            try {
                val request = gson.fromJson(line, JsonObject::class.java)
                val method = request.get("method")?.let { if (it.isJsonPrimitive) it.asString else null } ?: return@launch
                val requestId = request.get("id")?.let { if (it.isJsonPrimitive) it.asString else null } ?: request.get("id")?.toString()?.replace("\"", "")
                val methodArgs = request.getAsJsonObject("args") ?: JsonObject()

                fun getSafeString(key: String): String =
                    methodArgs.get(key)?.let { if (it.isJsonPrimitive) it.asString else "" } ?: ""

                fun getSafeInt(key: String, default: Int): Int =
                    methodArgs.get(key)?.let { if (it.isJsonPrimitive && it.asJsonPrimitive.isNumber) it.asInt else default } ?: default

                fun getSafeBoolean(key: String, default: Boolean): Boolean =
                    methodArgs.get(key)?.let { if (it.isJsonPrimitive && it.asJsonPrimitive.isBoolean) it.asBoolean else default } ?: default

                if (method == "cancel") {
                    val targetId = getSafeString("id")
                    if (targetId.isNotEmpty()) {
                        activeJobs.remove(targetId)?.cancel()
                        
                        try {
                           val client = Injekt.get<okhttp3.OkHttpClient>()
                           val calls = client.dispatcher.queuedCalls() + client.dispatcher.runningCalls()
                           calls.forEach { call ->
                               if (call.request().tag(String::class.java) == targetId) {
                                   call.cancel()
                                   System.err.println("[RPC] Forcibly cancelled OkHttp call for: $targetId")
                               }
                           }
                        } catch (e: Exception) {
                            System.err.println("[RPC] Error cancelling OkHttp calls: ${e.message}")
                        }
                        
                        System.err.println("[RPC] Cancelled request: $targetId")
                    }
                    return@launch
                }

                if (requestId != null) {
                    activeJobs[requestId] = coroutineContext[Job]!!
                }

                fun sendResponse(data: Any?, status: String? = null) {
                    if (requestId == null) return
                    val responseObj = JsonObject()
                    responseObj.addProperty("id", requestId)
                    if (status != null) responseObj.addProperty("status", status)
                    
                    try {
                        val decoded = if (data is String) {
                             try { gson.fromJson(data, JsonElement::class.java) } catch (e: Exception) { com.google.gson.JsonPrimitive(data) }
                        } else {
                             gson.toJsonTree(data)
                        }
                        responseObj.add("data", decoded)
                    } catch (e: Exception) {
                        responseObj.addProperty("data", data.toString())
                    }
                    
                    synchronized(outLock) {
                        cleanOut.println(gson.toJson(responseObj))
                    }
                }

                val ioContext = if (requestId != null) {
                    Dispatchers.IO + eu.kanade.tachiyomi.network.RequestTag.threadLocalId.asContextElement(requestId)
                } else {
                    Dispatchers.IO
                }

                val resultData = withContext(ioContext) {
                    when (method) {
                        "loadExtensions" -> {
                            val path = getSafeString("folderPath")
                            AniyomiSourceMethods.loadExtensions(path)
                        }
                        "getPopular" -> {
                            val sourceId = getSafeString("sourceId")
                            val page = getSafeInt("page", 1)
                            val isAnime = getSafeBoolean("isAnime", true)
                            AniyomiSourceMethods.fetchPopular(sourceId, page, isAnime)
                        }
                        "getLatestUpdates" -> {
                            val sourceId = getSafeString("sourceId")
                            val page = getSafeInt("page", 1)
                            val isAnime = getSafeBoolean("isAnime", true)
                            AniyomiSourceMethods.fetchLatestUpdates(sourceId, page, isAnime)
                        }
                        "search" -> {
                            val sourceId = getSafeString("sourceId")
                            val query = getSafeString("query")
                            val page = getSafeInt("page", 1)
                            val isAnime = getSafeBoolean("isAnime", true)
                            AniyomiSourceMethods.search(sourceId, query, page, isAnime)
                        }
                        "getDetail" -> {
                            val sourceId = getSafeString("sourceId")
                            val media = methodArgs.getAsJsonObject("media") ?: JsonObject()
                            val url = media.get("url")?.let { if (it.isJsonPrimitive) it.asString else "" } ?: ""
                            val title = media.get("title")?.let { if (it.isJsonPrimitive) it.asString else "" } ?: ""
                            val cover = media.get("thumbnail_url")?.let { if (it.isJsonPrimitive) it.asString else "" } ?: ""
                            val isAnime = getSafeBoolean("isAnime", true)
                            AniyomiSourceMethods.fetchDetails(sourceId, url, title, cover, isAnime)
                        }
                        "getVideoList" -> {
                            val sourceId = getSafeString("sourceId")
                            val episode = methodArgs.getAsJsonObject("episode") ?: JsonObject()
                            val url = episode.get("url")?.let { if (it.isJsonPrimitive) it.asString else "" } ?: ""
                            val name = episode.get("name")?.let { if (it.isJsonPrimitive) it.asString else "" } ?: ""
                            AniyomiSourceMethods.fetchVideoList(sourceId, url, name)
                        }
                        "getPageList" -> {
                            val sourceId = getSafeString("sourceId")
                            val episode = methodArgs.getAsJsonObject("episode") ?: JsonObject()
                            val url = episode.get("url")?.let { if (it.isJsonPrimitive) it.asString else "" } ?: ""
                            val name = episode.get("name")?.let { if (it.isJsonPrimitive) it.asString else "" } ?: ""
                            AniyomiSourceMethods.fetchPageList(sourceId, url, name)
                        }
                        "unloadExtension" -> {
                            val sourceId = getSafeString("sourceId")
                            AniyomiSourceMethods.unloadExtension(sourceId)
                            "null"
                        }
                        "aniyomiGetPreferences" -> {
                            val sourceId = getSafeString("sourceId")
                            val isAnime = getSafeBoolean("isAnime", true)
                            AniyomiSourceMethods.getPreferences(sourceId, isAnime)
                        }
                        "aniyomiSavePreference" -> {
                            val sourceId = getSafeString("sourceId")
                            val key = getSafeString("key")
                            val value = methodArgs.get("value")
                            val isAnime = getSafeBoolean("isAnime", true)
                            
                            val actualValue: Any? = if (value == null || value.isJsonNull) {
                                null
                            } else if (value.isJsonPrimitive) {
                                val p = value.asJsonPrimitive
                                when {
                                    p.isBoolean -> p.asBoolean
                                    p.isNumber -> {
                                        val n = p.asNumber
                                        if (n.toDouble() == n.toInt().toDouble()) n.toInt() else n.toDouble()
                                    }
                                    else -> p.asString
                                }
                            } else if (value.isJsonArray) {
                                value.asJsonArray.map { it.asString }.toSet()
                            } else {
                                value.toString()
                            }
                            
                            val result = AniyomiSourceMethods.savePreference(sourceId, key, actualValue, isAnime)
                            if (result == "success") "true" else "false"
                        }
                        "csLoadExtensions" -> {
                            val path = getSafeString("folderPath")
                            com.anymex.desktop.cloudstream.CloudStreamExtensionLoader.loadExtensions(path)
                        }
                        "csSearch" -> {
                            val sourceId = getSafeString("sourceId")
                            val query = getSafeString("query")
                            val page = getSafeInt("page", 1)
                            com.anymex.desktop.cloudstream.CloudStreamExtensionLoader.search(sourceId, query, page)
                        }
                        "csGetDetail" -> {
                            val sourceId = getSafeString("sourceId")
                            val url = methodArgs.get("url")?.let { if (it.isJsonPrimitive) it.asString else "" } ?: ""
                            com.anymex.desktop.cloudstream.CloudStreamExtensionLoader.fetchDetails(sourceId, url)
                        }
                        "csGetVideoList" -> {
                            val sourceId = getSafeString("sourceId")
                            val url = methodArgs.get("url")?.let { if (it.isJsonPrimitive) it.asString else "" } ?: ""
                            com.anymex.desktop.cloudstream.CloudStreamExtensionLoader.fetchVideoList(sourceId, url)
                        }
                        "csGetVideoListStream" -> {
                            val sourceId = getSafeString("sourceId")
                            val url = methodArgs.get("url")?.let { if (it.isJsonPrimitive) it.asString else "" } ?: ""
                            com.anymex.desktop.cloudstream.CloudStreamExtensionLoader.fetchVideoListStream(sourceId, url) { linkJson ->
                                 sendResponse(linkJson, "partial")
                            }
                            "completed"
                        }
                        "ping" -> "pong"
                        "exit" -> {
                            System.exit(0)
                            ""
                        }
                        else -> "{\"error\": \"Unknown method: $method\"}"
                    }
                }

                if (requestId != null) {
                    if (resultData == "completed") {
                        sendResponse(null, "completed")
                    } else {
                        sendResponse(resultData)
                    }
                    activeJobs.remove(requestId)
                } else {
                    synchronized(outLock) {
                        cleanOut.println(resultData)
                    }
                }
            } catch (e: CancellationException) {

            } catch (e: Exception) {
                System.err.println("[RPC] Error processing line: $line")
                e.printStackTrace()
                
                val errorResponse = JsonObject()
                errorResponse.addProperty("error", e.message ?: "Unknown error")
                
                synchronized(outLock) {
                    cleanOut.println(gson.toJson(errorResponse))
                }
            }
        }
    }
}
