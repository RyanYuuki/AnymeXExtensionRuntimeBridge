package eu.kanade.tachiyomi.network.interceptor

import android.content.Context
import okhttp3.Interceptor
import okhttp3.Response

open class CloudflareInterceptor @JvmOverloads constructor(
    context: Context? = null
) : WebViewInterceptor(context) {

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val response = chain.proceed(request)
        return response
    }
}
