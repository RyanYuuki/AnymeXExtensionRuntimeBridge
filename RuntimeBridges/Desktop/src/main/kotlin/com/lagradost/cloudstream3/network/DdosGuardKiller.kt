package com.lagradost.cloudstream3.network

import okhttp3.Interceptor
import okhttp3.Response

class DdosGuardKiller(private val alwaysBypass: Boolean) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        // Just proceed with the original request as a stub.
        return chain.proceed(chain.request())
    }
}
