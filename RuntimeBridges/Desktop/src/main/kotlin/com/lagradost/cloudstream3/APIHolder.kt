package com.lagradost.cloudstream3

import com.lagradost.cloudstream3.plugins.BasePlugin
import com.lagradost.cloudstream3.utils.ExtractorApi
import java.util.Collections.synchronizedList
import com.fasterxml.jackson.databind.json.JsonMapper
import com.fasterxml.jackson.module.kotlin.kotlinModule
import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.module.kotlin.readValue
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import android.content.Context

object APIHolder {
    val allProviders: MutableList<MainAPI> = synchronizedList(mutableListOf())
    val apis: MutableList<MainAPI> = synchronizedList(mutableListOf())
    
    val mapper: JsonMapper = JsonMapper.builder().addModule(kotlinModule())
        .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false).build()

    fun addPluginMapping(provider: MainAPI) {
        if (!apis.contains(provider)) {
            apis.add(provider)
        }
    }
    
    fun removePluginMapping(provider: MainAPI) {
        apis.remove(provider)
    }

    suspend fun getCaptchaToken(url: String, key: String, referer: String? = null): String? = null
    
    val unixTime: Long
        get() = System.currentTimeMillis() / 1000L
    val unixTimeMS: Long
        get() = System.currentTimeMillis()

    fun capitalize(str: String): String {
        return str.replaceFirstChar { if (it.isLowerCase()) it.titlecase(java.util.Locale.getDefault()) else it.toString() }
    }
}

// Mapped in MainAPI.kt for binary compatibility

abstract class UiText {
    abstract fun asString(context: Context?): String
    fun asStringNull(context: Context?): String? = asString(context)
    class StringValue(val value: String): UiText() {
        override fun asString(context: Context?) = value
    }
}

fun txt(s: String?): UiText = UiText.StringValue(s ?: "")

enum class VideoWatchState {
    None,
    Watched
}

data class ResultEpisode(
    val headerName: String,
    val name: String?,
    val poster: String?,
    val episode: Int,
    val seasonIndex: Int?,
    val season: Int?,
    val data: String,
    val apiName: String,
    val id: Int,
    val index: Int,
    val position: Long = 0,
    val duration: Long = 0,
    val score: Score? = null,
    val description: String? = null,
    val isFiller: Boolean? = null,
    val tvType: TvType = TvType.Anime,
    val parentId: Int = 0,
    val videoWatchState: VideoWatchState = VideoWatchState.None,
    val totalEpisodeIndex: Int? = null,
    val airDate: Long? = null,
    val runTime: Int? = null,
)

data class SubtitleData(val name: String, val url: String, val origin: String? = null, val headers: Map<String, String> = mapOf())

data class LinkLoadingResult(
    val links: List<com.lagradost.cloudstream3.utils.ExtractorLink>,
    val subs: List<SubtitleData>,
    val syncData: HashMap<String, String>
)

// Mocks removed as they are now replaced by real implementations in MainActivity.kt and ParCollections.kt

object MvvmMock {
    fun logError(e: Throwable) {
        e.printStackTrace()
    }
}
fun logError(e: Throwable) = MvvmMock.logError(e)

inline fun <T> safe(f: () -> T): T? {
    return try {
        f()
    } catch (e: Exception) {
        logError(e)
        null
    }
}

object Log {
    fun d(tag: String, msg: String, tr: Throwable? = null): Int { System.err.println("D/$tag: $msg"); tr?.printStackTrace(System.err); return 0 }
    fun i(tag: String, msg: String, tr: Throwable? = null): Int { System.err.println("I/$tag: $msg"); tr?.printStackTrace(System.err); return 0 }
    fun e(tag: String, msg: String, tr: Throwable? = null): Int { System.err.println("E/$tag: $msg"); tr?.printStackTrace(System.err); return 0 }
    fun w(tag: String, msg: String, tr: Throwable? = null): Int { System.err.println("W/$tag: $msg"); tr?.printStackTrace(System.err); return 0 }
}

enum class RequestBodyTypes(val value: String) {
    JSON("application/json"),
    FORM("application/x-www-form-urlencoded");
    
    fun toMediaTypeOrNull() = value.toMediaTypeOrNull()
}

class WebViewResolver(
    val interceptUrl: Any? = null,
    val additionalUrls: List<Any>? = null,
    val useOkhttp: Boolean = false,
    val timeout: Long = 0L
)

fun getCaptchaToken(url: String, key: String, referer: String? = null): String? = null
