package eu.kanade.tachiyomi.network

import okhttp3.CacheControl
import okhttp3.FormBody
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import okhttp3.RequestBody
import java.util.concurrent.TimeUnit.MINUTES

private val DEFAULT_CACHE_CONTROL = CacheControl.Builder().maxAge(10, MINUTES).build()
private val DEFAULT_HEADERS = Headers.Builder().build()
private val DEFAULT_BODY: RequestBody = FormBody.Builder().build()

/** Matches a URI scheme prefix, for example `http:`, `https:` or `intent:`. */
private val SCHEME_PREFIX = Regex("^[a-zA-Z][a-zA-Z0-9+.\\-]*:")

/**
 * Prefix a scheme onto a bare host or a protocol-relative URL.
 *
 * Only strings with NO scheme at all are prefixed. A string that already carries one is passed
 * through untouched so OkHttp can apply the WHATWG normalisation a browser would — sources
 * routinely scrape URLs that are scheme-ful but not spelled `http://` or `https://` exactly:
 * JSON-escaped (`https:\/\/host\/path`), upper-cased (`HTTPS://host`), or single-slashed
 * (`https:/host`). Prefixing those produced `https://https:\/\/host…`, whose authority parses as
 * `https`, so the request died with `UnknownHostException: https` instead of loading.
 */
fun String.normalizeUrl(): String {
    if (isBlank()) return this
    if (SCHEME_PREFIX.containsMatchIn(this)) return this
    if (startsWith("//")) return "https:$this"
    return "https://$this"
}

fun GET(
    url: String,
    headers: Headers = DEFAULT_HEADERS,
    cache: CacheControl = DEFAULT_CACHE_CONTROL,
): Request {
    val nUrl = url.normalizeUrl().toHttpUrl()
    return GET(nUrl, headers, cache)
}

/**
 * @since extensions-lib 1.4
 */
fun GET(
    url: HttpUrl,
    headers: Headers = DEFAULT_HEADERS,
    cache: CacheControl = DEFAULT_CACHE_CONTROL,
): Request {
    return Request.Builder()
        .url(url)
        .headers(headers)
        .cacheControl(cache)
        .build()
}

fun POST(
    url: String,
    headers: Headers = DEFAULT_HEADERS,
    body: RequestBody = DEFAULT_BODY,
    cache: CacheControl = DEFAULT_CACHE_CONTROL,
): Request {
    return Request.Builder()
        .url(url.normalizeUrl())
        .post(body)
        .headers(headers)
        .cacheControl(cache)
        .build()
}

fun PUT(
    url: String,
    headers: Headers = DEFAULT_HEADERS,
    body: RequestBody = DEFAULT_BODY,
    cache: CacheControl = DEFAULT_CACHE_CONTROL,
): Request {
    return Request.Builder()
        .url(url.normalizeUrl())
        .put(body)
        .headers(headers)
        .cacheControl(cache)
        .build()
}

fun DELETE(
    url: String,
    headers: Headers = DEFAULT_HEADERS,
    body: RequestBody = DEFAULT_BODY,
    cache: CacheControl = DEFAULT_CACHE_CONTROL,
): Request {
    return Request.Builder()
        .url(url.normalizeUrl())
        .delete(body)
        .headers(headers)
        .cacheControl(cache)
        .build()
}
