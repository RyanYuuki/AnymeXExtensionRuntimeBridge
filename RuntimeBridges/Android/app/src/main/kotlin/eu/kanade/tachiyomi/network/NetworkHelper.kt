package eu.kanade.tachiyomi.network

import android.content.Context
import android.util.Log
import eu.kanade.tachiyomi.network.interceptor.CloudflareInterceptor
import eu.kanade.tachiyomi.network.interceptor.IgnoreGzipInterceptor
import eu.kanade.tachiyomi.network.interceptor.UncaughtExceptionInterceptor
import eu.kanade.tachiyomi.network.interceptor.UserAgentInterceptor
import okhttp3.Cache
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.brotli.BrotliInterceptor
import java.io.File
import java.util.concurrent.TimeUnit

class NetworkHelper(
    context: Context,
) {
    companion object {
        @Volatile
        private var resolvedUa: String? = null

        fun defaultUserAgentProvider(): String {
            return System.getProperty("anymex.ua.default")?.takeIf { it.isNotBlank() }
                ?: resolvedUa
                ?: "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"
        }

        internal fun initUserAgent(context: Context) {
            if (resolvedUa != null) return
            try {
                val raw = android.webkit.WebSettings.getDefaultUserAgent(context)
                resolvedUa = raw
                    .replace("; wv)", ")")
                    .replace(" Version/[\\d.]+ ".toRegex(), " ")
            } catch (_: Throwable) {}
        }
    }

    fun defaultUserAgentProvider() = Companion.defaultUserAgentProvider()

    val cookieJar = AndroidCookieJar()

    var client: OkHttpClient = run {
        val builder = OkHttpClient.Builder()
            .cookieJar(cookieJar)
            .connectTimeout(60, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .writeTimeout(60, TimeUnit.SECONDS)
            .callTimeout(2, TimeUnit.MINUTES)
            .cache(
                Cache(
                    directory = File(context.externalCacheDir ?: context.cacheDir, "network_cache"),
                    maxSize = 5L * 1024 * 1024, // 5 MiB
                ),
            )
            .addInterceptor(UncaughtExceptionInterceptor())
            .addInterceptor(object : Interceptor {
                override fun intercept(chain: Interceptor.Chain): Response {
                    val request = chain.request()
                    try {
                        return chain.proceed(request)
                    } catch (e: Exception) {
                        Log.e("AnymeXNetwork", "[ERROR] Request failed for ${request.url}: ${e.message}", e)
                        throw e
                    }
                }
            })
            .addInterceptor(CloudflareInterceptor(context, cookieJar, ::defaultUserAgentProvider))
            .addInterceptor(BrotliInterceptor)
            .addInterceptor(IgnoreGzipInterceptor())
            .addInterceptor(UserAgentInterceptor(::defaultUserAgentProvider))
            // Per-host User-Agent override — explicit class to avoid SAM cast across classloaders
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