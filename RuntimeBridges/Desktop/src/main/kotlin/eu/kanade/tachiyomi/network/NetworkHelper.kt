package eu.kanade.tachiyomi.network

import android.content.Context
import eu.kanade.tachiyomi.network.interceptor.CloudflareInterceptor
import eu.kanade.tachiyomi.network.interceptor.IgnoreGzipInterceptor
import eu.kanade.tachiyomi.network.interceptor.UncaughtExceptionInterceptor
import eu.kanade.tachiyomi.network.interceptor.UserAgentInterceptor
import okhttp3.Cache
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.ConnectionSpec
import okhttp3.Response
import okhttp3.brotli.BrotliInterceptor
import java.io.File
import java.util.concurrent.TimeUnit

class NetworkHelper(
    context: android.content.Context
) {
    companion object {
        val sharedCookieManager = java.net.CookieManager().apply {
            setCookiePolicy(java.net.CookiePolicy.ACCEPT_ALL)
        }

        fun defaultUserAgentProvider() =
            System.getProperty("anymex.ua.default")?.takeIf { it.isNotBlank() }
                ?: "Mozilla/5.0 (Linux; Android 13; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36"
    }

    fun defaultUserAgentProvider() = Companion.defaultUserAgentProvider()

    val cookieJar = object : CookieJar {
        override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
            val uri = try { url.toUri() } catch (e: Exception) { java.net.URI(url.toString()) }
            val headers = mapOf("Set-Cookie" to cookies.map { it.toString() })
            try {
                sharedCookieManager.put(uri, headers)
            } catch (e: Exception) {
                System.err.println("[WARN] Failed to save cookies for ${url.host}: ${e.message}")
            }
        }

        override fun loadForRequest(url: HttpUrl): List<Cookie> {
            val uri = try { url.toUri() } catch (e: Exception) { java.net.URI(url.toString()) }
            try {
                val headers = sharedCookieManager.get(uri, emptyMap())
                val cookieHeaders = headers["Cookie"] ?: headers["cookie"] ?: return emptyList()
                return cookieHeaders.flatMap { header ->
                    header.split(";").mapNotNull { Cookie.parse(url, it.trim()) }
                }
            } catch (e: Exception) {
                System.err.println("[WARN] Failed to load cookies for ${url.host}: ${e.message}")
                return emptyList()
            }
        }
    }

    var client: OkHttpClient = run {
        val builder = OkHttpClient.Builder()
            .cookieJar(cookieJar)
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .callTimeout(2, TimeUnit.MINUTES)
            .retryOnConnectionFailure(true)
            .connectionSpecs(listOf(ConnectionSpec.MODERN_TLS, ConnectionSpec.COMPATIBLE_TLS))
            .cache(
                Cache(
                    directory = File(context.cacheDir, "network_cache"),
                    maxSize = 5L * 1024 * 1024, // 5 MiB
                ),
            )
            .addInterceptor(UncaughtExceptionInterceptor())
            .addInterceptor(CloudflareInterceptor(context))
            .addInterceptor(object : Interceptor {
                override fun intercept(chain: Interceptor.Chain): Response {
                    return try {
                        BrotliInterceptor.intercept(chain)
                    } catch (_: Throwable) {
                        chain.proceed(chain.request())
                    }
                }
            })
            .addInterceptor(IgnoreGzipInterceptor())
            .addInterceptor(UserAgentInterceptor(::defaultUserAgentProvider))
            .addInterceptor(object : Interceptor {
                override fun intercept(chain: Interceptor.Chain): Response {
                    val id = RequestTag.get()
                    val request = if (id != null) {
                        chain.request().newBuilder()
                            .tag(String::class.java, id)
                            .build()
                    } else {
                        chain.request()
                    }
                    return chain.proceed(request)
                }
            })
            .addInterceptor(object : Interceptor {
                override fun intercept(chain: Interceptor.Chain): Response {
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
                    return if (!customUa.isNullOrEmpty()) {
                        val newRequest = request.newBuilder()
                            .header("User-Agent", customUa)
                            .build()
                        chain.proceed(newRequest)
                    } else {
                        chain.proceed(request)
                    }
                }
            })
        builder.build()
    }

    /**
     * @deprecated Since extension-lib 1.5
     */
    @Deprecated("The regular client handles Cloudflare by default")
    @Suppress("UNUSED")
    val cloudflareClient: OkHttpClient = client
}