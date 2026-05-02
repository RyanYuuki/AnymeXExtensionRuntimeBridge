package com.lagradost.cloudstream3.syncproviders.providers

import com.fasterxml.jackson.annotation.JsonInclude
import com.fasterxml.jackson.annotation.JsonProperty
import com.lagradost.cloudstream3.*
import com.lagradost.cloudstream3.CloudStreamApp.Companion.getKey
import com.lagradost.cloudstream3.CloudStreamApp.Companion.removeKey
import com.lagradost.cloudstream3.CloudStreamApp.Companion.setKey
import com.lagradost.cloudstream3.mvvm.logError
import com.lagradost.cloudstream3.syncproviders.*
import com.lagradost.cloudstream3.ui.SyncWatchType
import com.lagradost.cloudstream3.utils.AppUtils.toJson
import com.lagradost.cloudstream3.utils.DataStore.toYear
import java.math.BigInteger
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.*
import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.toDuration

private const val CLIENT_ID = ""
private const val CLIENT_SECRET = ""

class SimklApi : SyncAPI() {
    override var name = "Simkl"
    override val idPrefix = "simkl"

    override val redirectUrlIdentifier = "simkl"
    override val hasOAuth2 = true
    override val hasPin = true
    override var requireLibraryRefresh = true
    override var mainUrl = "https://simkl.com"
    override val icon = 0
    override val createAccountUrl = "$mainUrl/signup"
    override val syncIdName = SyncIdName.Simkl

    private var lastScoreTime = -1L

    private object SimklCache {
        private const val SIMKL_CACHE_KEY = "SIMKL_API_CACHE"

        enum class CacheTimes(val value: String) {
            OneMonth("30d"),
            ThirtyMinutes("30m")
        }

        private class SimklCacheWrapper<T>(
            @JsonProperty("obj") val obj: T?,
            @JsonProperty("validUntil") val validUntil: Long,
        ) {
            fun isFresh(): Boolean {
                return validUntil > unixTime
            }

            fun remainingTime(): Duration {
                val unixTime = unixTime
                return if (validUntil > unixTime) {
                    (validUntil - unixTime).toDuration(DurationUnit.SECONDS)
                } else {
                    Duration.ZERO
                }
            }
        }

        fun <T> setKey(path: String, value: T, cacheTime: Duration) {
            setKey(
                SIMKL_CACHE_KEY,
                path,
                SimklCacheWrapper(value, unixTime + cacheTime.inWholeSeconds).toJson()
            )
        }

        inline fun <reified T : Any> getKey(path: String): T? {
            val type = mapper.typeFactory.constructParametricType(
                SimklCacheWrapper::class.java,
                T::class.java
            )
            val cache = getKey<String>(SIMKL_CACHE_KEY, path)?.let {
                mapper.readValue<SimklCacheWrapper<T>>(it, type)
            }

            return if (cache?.isFresh() == true) {
                cache.obj
            } else {
                removeKey(SIMKL_CACHE_KEY, path)
                null
            }
        }
    }

    companion object {
        const val SIMKL_CACHED_LIST: String = "simkl_cached_list"
        private const val SIMKL_DATE_FORMAT = "yyyy-MM-dd'T'HH:mm:ss'Z'"

        fun getUnixTime(string: String?): Long? {
            return try {
                SimpleDateFormat(SIMKL_DATE_FORMAT, Locale.getDefault()).apply {
                    this.timeZone = TimeZone.getTimeZone("UTC")
                }.parse(
                    string ?: return null
                )?.toInstant()?.epochSecond
            } catch (e: Exception) {
                logError(e)
                return null
            }
        }

        fun getDateTime(unixTime: Long?): String? {
            return try {
                SimpleDateFormat(SIMKL_DATE_FORMAT, Locale.getDefault()).apply {
                    this.timeZone = TimeZone.getTimeZone("UTC")
                }.format(
                    Date.from(
                        Instant.ofEpochSecond(
                            unixTime ?: return null
                        )
                    )
                )
            } catch (e: Exception) {
                null
            }
        }

        fun getPosterUrl(poster: String): String {
            return "https://simkl.net/posters/${poster}_m.jpg"
        }

        private fun getUrlFromId(id: Int): String {
            return "https://simkl.com/anime/$id"
        }

        enum class SimklListStatusType(
            var value: Int,
            val originalName: String?
        ) {
            Watching(0, "watching"),
            Completed(1, "completed"),
            Paused(2, "hold"),
            Dropped(3, "dropped"),
            Planning(4, "plantowatch"),
            ReWatching(5, "watching"),
            None(-1, null);

            companion object {
                fun fromString(string: String): SimklListStatusType? {
                    return entries.firstOrNull {
                        it.originalName == string
                    }
                }
            }
        }

        @JsonInclude(JsonInclude.Include.NON_EMPTY)
        data class MediaObject(
            @JsonProperty("title") val title: String?,
            @JsonProperty("year") val year: Int?,
            @JsonProperty("ids") val ids: Ids?,
            @JsonProperty("total_episodes") val totalEpisodes: Int? = null,
            @JsonProperty("status") val status: String? = null,
            @JsonProperty("poster") val poster: String? = null,
            @JsonProperty("type") val type: String? = null,
        ) {
            data class Ids(
                @JsonProperty("simkl") val simkl: Int?,
                @JsonProperty("imdb") val imdb: String? = null,
                @JsonProperty("tmdb") val tmdb: String? = null,
                @JsonProperty("mal") val mal: String? = null,
                @JsonProperty("anilist") val anilist: String? = null,
            )
            
            fun toSyncSearchResult(): SyncAPI.SyncSearchResult? {
                return SyncAPI.SyncSearchResultImpl(
                    this.title ?: return null,
                    "Simkl",
                    this.ids?.simkl?.toString() ?: return null,
                    getUrlFromId(this.ids.simkl ?: return null),
                    this.poster?.let { getPosterUrl(it) },
                    if (this.type == "movie") TvType.Movie else TvType.TvSeries
                )
            }
        }

        fun getHeaders(token: AuthToken): Map<String, String> =
            mapOf("Authorization" to "Bearer ${token.accessToken}", "simkl-api-key" to CLIENT_ID)
    }

    override suspend fun status(auth: AuthData?, id: String): AbstractSyncStatus? {
        return null // Simplified for desktop stability trial
    }

    override suspend fun updateStatus(
        auth: AuthData?,
        id: String,
        newStatus: AbstractSyncStatus
    ): Boolean {
        return false // Simplified
    }

    override suspend fun search(auth: AuthData?, query: String): List<SyncSearchResult>? {
        return app.get(
            "$mainUrl/search/", params = mapOf("client_id" to CLIENT_ID, "q" to query)
        ).parsedSafe<Array<MediaObject>>()?.mapNotNull { it.toSyncSearchResult() }
    }
    
    override suspend fun load(auth: AuthData?, id: String): SyncResult? {
        return null
    }

    override suspend fun library(auth: AuthData?): LibraryMetadata? {
        return null
    }
}
