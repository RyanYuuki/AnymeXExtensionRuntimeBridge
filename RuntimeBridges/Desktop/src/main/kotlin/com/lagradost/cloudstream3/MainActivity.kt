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


val app: Requests by lazy {
    val logging = HttpLoggingInterceptor().apply {
        level = HttpLoggingInterceptor.Level.BASIC
    }
    
    try {
        java.util.logging.Logger.getLogger("okhttp3.OkHttpClient").apply {
            level = java.util.logging.Level.FINE
            addHandler(java.util.logging.ConsoleHandler().apply {
                level = java.util.logging.Level.FINE
            })
        }
    } catch (e: Exception) {
        System.err.println("Failed to enable OkHttp leak detection logging: ${e.message}")
    }
    
    val client = OkHttpClient.Builder()
        .addInterceptor(logging)
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
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
    }
}
