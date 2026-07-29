package com.lagradost.cloudstream3

import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import com.lagradost.cloudstream3.utils.Event
import com.lagradost.nicehttp.Requests
import com.lagradost.nicehttp.ResponseParser
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import java.util.concurrent.TimeUnit
import kotlin.reflect.KClass
import okhttp3.HttpUrl.Companion.toHttpUrl

/**
 * Compatibility file for CloudStream plugins.
 * Some plugins depend on package-level properties in MainActivityKt (generated from MainActivity.kt).
 */

val app: Requests by lazy {
    val logging = HttpLoggingInterceptor().apply {
        level = HttpLoggingInterceptor.Level.BASIC
    }
    
    val client = OkHttpClient.Builder()
        .addInterceptor(logging)
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .cookieJar(object : okhttp3.CookieJar {
            private val cookieStore = java.util.concurrent.ConcurrentHashMap<String, List<okhttp3.Cookie>>()
            override fun saveFromResponse(url: okhttp3.HttpUrl, cookies: List<okhttp3.Cookie>) {
                cookieStore[url.host] = cookies
            }
            override fun loadForRequest(url: okhttp3.HttpUrl): List<okhttp3.Cookie> {
                val list = mutableListOf<okhttp3.Cookie>()
                val memoryCookies = cookieStore[url.host]
                if (memoryCookies != null) {
                    list.addAll(memoryCookies)
                }
                try {
                    val cookieManager = android.webkit.CookieManager.getInstance()
                    val cookieString = cookieManager.getCookie(url.toString())
                    if (!cookieString.isNullOrEmpty()) {
                        cookieString.split(";").forEach { pair ->
                            val cleanPair = pair.trim()
                            if (cleanPair.isNotEmpty()) {
                                val cookie = okhttp3.Cookie.parse(url, cleanPair)
                                if (cookie != null) {
                                    if (list.none { it.name == cookie.name }) {
                                        list.add(cookie)
                                    }
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    System.err.println("[Cloudstream-Android] Failed to load cookies from CookieManager: ${e.message}")
                }
                return list
            }
        })
        .addInterceptor { chain ->
            val request = chain.request()
            val host = request.url.host
            var customUa = System.getProperty("anymex.ua.$host")
            if (customUa.isNullOrEmpty()) {
                val parts = host.split(".")
                if (parts.size >= 2) {
                    val parentDomain = parts.takeLast(2).joinToString(".")
                    customUa = System.getProperty("anymex.ua.$parentDomain")
                }
            }
            if (!customUa.isNullOrEmpty()) {
                val newRequest = request.newBuilder()
                    .header("User-Agent", customUa)
                    .build()
                chain.proceed(newRequest)
            } else {
                chain.proceed(request)
            }
        }
        .build()

    Requests(
        baseClient = client,
        responseParser = object : ResponseParser {
            val mapper: ObjectMapper = jacksonObjectMapper().configure(
                DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES,
                false
            )

            override fun <T : Any> parse(text: String, kClass: KClass<T>): T {
                return mapper.readValue(text, kClass.java)
            }

            override fun <T : Any> parseSafe(text: String, kClass: KClass<T>): T? {
                return try {
                    mapper.readValue(text, kClass.java)
                } catch (e: Exception) {
                    null
                }
            }

            override fun writeValueAsString(obj: Any): String {
                return mapper.writeValueAsString(obj)
            }
        }
    ).apply {
        defaultHeaders = mapOf("user-agent" to USER_AGENT)
    }
}

val api: Requests get() = app

open class CommonActivity : android.app.Activity()
class MainActivity : CommonActivity() {
    companion object {
        var context: android.content.Context? = null
        var activity: android.app.Activity? = null
        val afterPluginsLoadedEvent = Event<Boolean>()
        val bookmarksUpdatedEvent = Event<Boolean>()
        val libraryUpdatedEvent   = Event<Boolean>()
        val onBackPressedEvent = Event<Boolean>()
        val reloadHomeEvent  = Event<Boolean>()
        val reloadPageEvent  = Event<Boolean>()
        val reinitFirebase = Event<Boolean>()
        val restartApp     = Event<Boolean>()
    }
}
