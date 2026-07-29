package eu.kanade.tachiyomi.network.interceptor

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import android.webkit.WebViewClient
import eu.kanade.tachiyomi.network.AndroidCookieJar
import okhttp3.Cookie
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class CloudflareInterceptor(
    context: Context,
    private val cookieManager: AndroidCookieJar,
    defaultUserAgentProvider: () -> String,
) : WebViewInterceptor(context, defaultUserAgentProvider) {

    private val handler = Handler(Looper.getMainLooper())

    override fun shouldIntercept(response: Response): Boolean {
        return response.code in ERROR_CODES && response.header("Server") in SERVER_CHECK
    }

    override fun intercept(
        chain: Interceptor.Chain,
        request: Request,
        response: Response,
    ): Response {
        try {
            response.close()
            cookieManager.remove(request.url, COOKIE_NAMES, 0)
            val oldCookie = cookieManager.get(request.url)
                .firstOrNull { it.name == "cf_clearance" }
            resolveWithWebView(request, oldCookie)
            return chain.proceed(request)
        } catch (e: CloudflareBypassException) {
            throw IOException("Cloudflare bypass failed", e)
        } catch (e: Exception) {
            throw IOException(e)
        }
    }

    private fun resolveWithWebView(originalRequest: Request, oldCookie: Cookie?) {
        val latch = CountDownLatch(1)
        var webview: WebView? = null
        var cloudflareBypassed = false
        val origRequestUrl = originalRequest.url.toString()
        val headers = parseHeaders(originalRequest.headers)
        val activity = com.anymex.runtimehost.RuntimeBridge.resolveAppCompatActivity(context)

        handler.post {
            val webViewContext = activity ?: context
            val wv = WebView(webViewContext).apply {
                setLayerType(View.LAYER_TYPE_SOFTWARE, null)
                with(settings) {
                    javaScriptEnabled = true
                    domStorageEnabled = true
                    databaseEnabled = true
                    useWideViewPort = true
                    loadWithOverviewMode = true
                    cacheMode = android.webkit.WebSettings.LOAD_DEFAULT
                    setSupportMultipleWindows(true)
                    setSupportZoom(true)
                    builtInZoomControls = true
                    displayZoomControls = false
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        safeBrowsingEnabled = false
                    }
                }
                try {
                    android.webkit.CookieManager.getInstance().acceptThirdPartyCookies(this)
                } catch (_: Throwable) {}
                settings.userAgentString = defaultUserAgentProvider()
            }
            webview = wv

            if (activity != null) {
                (activity.window.decorView as ViewGroup).addView(wv, ViewGroup.LayoutParams(1, 1))
            }

            wv.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) {
                    val newClearance = cookieManager.get(origRequestUrl.toHttpUrl())
                        .firstOrNull { it.name == "cf_clearance" }
                    if (newClearance != null && newClearance != oldCookie) {
                        cloudflareBypassed = true
                        latch.countDown()
                    }
                }

                override fun onReceivedError(
                    view: WebView,
                    request: android.webkit.WebResourceRequest,
                    error: android.webkit.WebResourceError,
                ) {
                    if (request.isForMainFrame) {
                        latch.countDown()
                    }
                }
            }

            wv.loadUrl(origRequestUrl, headers)
        }

        latch.await(30, TimeUnit.SECONDS)

        handler.post {
            webview?.let { wv ->
                wv.stopLoading()
                if (activity != null) {
                    try {
                        (activity.window.decorView as ViewGroup).removeView(wv)
                    } catch (_: Throwable) {}
                }
                wv.destroy()
            }
        }

        if (!cloudflareBypassed) {
            throw CloudflareBypassException()
        }
    }

    companion object {
        private val ERROR_CODES = listOf(403, 503)
        private val SERVER_CHECK = arrayOf("cloudflare-nginx", "cloudflare")
        private val COOKIE_NAMES = listOf("cf_clearance")
    }

    private class CloudflareBypassException : Exception()
}
