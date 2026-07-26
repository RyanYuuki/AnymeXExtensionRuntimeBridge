package eu.kanade.tachiyomi.network.interceptor

import android.content.Context
import okhttp3.Interceptor
import okhttp3.Response

abstract class WebViewInterceptor @JvmOverloads constructor(
    protected val context: Context? = null
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        return chain.proceed(chain.request())
    }
}
