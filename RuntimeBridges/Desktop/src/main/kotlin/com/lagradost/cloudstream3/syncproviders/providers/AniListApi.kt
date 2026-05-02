package com.lagradost.cloudstream3.syncproviders.providers

import com.fasterxml.jackson.annotation.JsonProperty
import com.lagradost.cloudstream3.*
import com.lagradost.cloudstream3.CloudStreamApp.Companion.getKey
import com.lagradost.cloudstream3.CloudStreamApp.Companion.setKey
import com.lagradost.cloudstream3.mvvm.logError
import com.lagradost.cloudstream3.syncproviders.*
import com.lagradost.cloudstream3.ui.SyncWatchType
import com.lagradost.cloudstream3.utils.AppUtils.parseJson
import com.lagradost.cloudstream3.utils.AppUtils.toJson
import com.lagradost.cloudstream3.utils.AppUtils.tryParseJson
import com.lagradost.cloudstream3.utils.DataStore.toKotlinObject
import java.net.URLEncoder
import java.util.*

class AniListApi : SyncAPI() {
    override var name = "AniList"
    override val idPrefix = "anilist"

    val key = "6871"
    override val redirectUrlIdentifier = "anilistlogin"
    override var requireLibraryRefresh = true
    override val hasOAuth2 = true
    override var mainUrl = "https://anilist.co"
    override val icon = 0
    override val createAccountUrl = "$mainUrl/signup"
    override val syncIdName = SyncIdName.Anilist

    override fun loginRequest(): AuthLoginPage? =
        AuthLoginPage("https://anilist.co/api/v2/oauth/authorize?client_id=$key&response_type=token")

    override suspend fun login(redirectUrl: String, payload: String?): AuthToken? {
        val sanitizer = splitRedirectUrl(redirectUrl)
        val token = AuthToken(
            accessToken = sanitizer["access_token"] ?: throw Exception("No access token"),
            accessTokenLifetime = unixTime + (sanitizer["expires_in"]?.toLong() ?: 0L),
        )
        return token
    }

    override suspend fun user(token: AuthToken?): AuthUser? {
        val user = getUser(token ?: return null)
            ?: throw Exception("Unable to fetch user data")

        return AuthUser(
            id = user.id,
            name = user.name,
            profilePicture = user.picture,
        )
    }

    override fun urlToId(url: String): String? =
        url.removePrefix("$mainUrl/anime/").removeSuffix("/")

    private fun getUrlFromId(id: Int): String {
        return "$mainUrl/anime/$id"
    }

    override suspend fun search(auth : AuthData?, query: String): List<SyncSearchResult>? {
        val data = searchShows(query) ?: return null
        return data.data?.page?.media?.map {
            SyncSearchResultImpl(
                it.title.romaji ?: "No Title",
                this.name,
                it.id.toString(),
                getUrlFromId(it.id),
                it.bannerImage
            )
        }
    }

    override suspend fun load(auth : AuthData?, id: String): SyncResult? {
        val internalId = (Regex("anilist\\.co/anime/(\\d*)").find(id)?.groupValues?.getOrNull(1)
            ?: id).toIntOrNull() ?: throw Exception("Invalid internalId")
        val season = getSeason(internalId).data.media

        return SyncResult(
            season.id.toString(),
            nextAiring = season.nextAiringEpisode?.let {
                NextAiring(
                    it.episode ?: return@let null,
                    (it.timeUntilAiring ?: return@let null).toLong() + unixTime
                )
            },
            title = season.title?.userPreferred,
            synonyms = season.synonyms,
            isAdult = season.isAdult,
            totalEpisodes = season.episodes,
            synopsis = season.description,
            actors = season.characters?.edges?.mapNotNull { edge ->
                val node = edge.node ?: return@mapNotNull null
                ActorData(
                    actor = Actor(
                        name = node.name?.userPreferred ?: node.name?.full ?: node.name?.native
                        ?: return@mapNotNull null,
                        image = node.image?.large ?: node.image?.medium
                    ),
                    role = when (edge.role) {
                        "MAIN" -> ActorRole.Main
                        "SUPPORTING" -> ActorRole.Supporting
                        "BACKGROUND" -> ActorRole.Background
                        else -> null
                    },
                    voiceActor = edge.voiceActors?.firstNotNullOfOrNull { staff ->
                        Actor(
                            name = staff.name?.userPreferred ?: staff.name?.full
                            ?: staff.name?.native
                            ?: return@mapNotNull null,
                            image = staff.image?.large ?: staff.image?.medium
                        )
                    }
                )
            },
            publicScore = Score.from100(season.averageScore),
            recommendations = season.recommendations?.edges?.mapNotNull { rec ->
                val recMedia = rec.node.mediaRecommendation
                SyncSearchResultImpl(
                    name = recMedia?.title?.userPreferred ?: return@mapNotNull null,
                    this.name,
                    recMedia.id?.toString() ?: return@mapNotNull null,
                    getUrlFromId(recMedia.id),
                    recMedia.coverImage?.extraLarge ?: recMedia.coverImage?.large
                    ?: recMedia.coverImage?.medium
                )
            },
            trailers = when (season.trailer?.site?.lowercase()?.trim()) {
                "youtube" -> listOf("https://www.youtube.com/watch?v=${season.trailer.id}")
                else -> null
            }
        )
    }

    override suspend fun status(auth : AuthData?, id: String): AbstractSyncStatus? {
        val internalId = id.toIntOrNull() ?: return null
        val data = getDataAboutId(auth ?: return null, internalId) ?: return null

        return SyncStatus(
            score = Score.from100(data.score),
            watchedEpisodes = data.progress,
            status = SyncWatchType.fromInternalId(data.type?.value ?: return null),
            isFavorite = data.isFavourite,
            maxEpisodes = data.episodes,
        )
    }

    override suspend fun updateStatus(
        auth: AuthData?,
        id: String,
        newStatus: AbstractSyncStatus
    ): Boolean {
        return postDataAboutId(
            auth ?: return false,
            id.toIntOrNull() ?: return false,
            fromIntToAnimeStatus(newStatus.status.internalId),
            newStatus.score,
            newStatus.watchedEpisodes
        )
    }

    companion object {
        const val MAX_STALE = 60 * 10
        private val aniListStatusString =
            arrayOf("CURRENT", "COMPLETED", "PAUSED", "DROPPED", "PLANNING", "REPEATING")

        const val ANILIST_CACHED_LIST: String = "anilist_cached_list"

        private suspend fun searchShows(name: String): GetSearchRoot? {
            try {
                val query = """
                query (${"$"}id: Int, ${"$"}page: Int, ${"$"}search: String, ${"$"}type: MediaType) {
                    Page (page: ${"$"}page, perPage: 10) {
                        media (id: ${"$"}id, search: ${"$"}search, type: ${"$"}type) {
                            id
                            idMal
                            seasonYear
                            startDate { year month day }
                            title {
                                romaji
                            }
                            averageScore
                            meanScore
                            nextAiringEpisode {
                                timeUntilAiring
                                episode
                            }
                            trailer { id site thumbnail }
                            bannerImage
                            recommendations {
                                nodes {
                                    id
                                    mediaRecommendation {
                                        id
                                        title {
                                            english
                                            romaji
                                        }
                                        idMal
                                        coverImage { medium large extraLarge }
                                        averageScore
                                    }
                                }
                            }
                            relations {
                                edges {
                                    id
                                    relationType(version: 2)
                                    node {
                                        format
                                        id
                                        idMal
                                        coverImage { medium large extraLarge }
                                        averageScore
                                        title {
                                            english
                                            romaji
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                """
                val data = mapOf(
                        "query" to query,
                        "variables" to mapOf(
                                     "search" to name,
                                     "page" to 1,
                                     "type" to "ANIME"
                                 ).toJson()
                    )

                val res = app.post(
                    "https://graphql.anilist.co/",
                    data = data,
                    timeout = 5000
                ).text.replace("\\", "")
                return res.toKotlinObject<GetSearchRoot>()
            } catch (e: Exception) {
                logError(e)
            }
            return null
        }

        enum class AniListStatusType(var value: Int) {
            Watching(0),
            Completed(1),
            Paused(2),
            Dropped(3),
            Planning(4),
            ReWatching(5),
            None(-1)
        }

        fun fromIntToAnimeStatus(inp: Int): AniListStatusType {
            return when (inp) {
                -1 -> AniListStatusType.None
                0 -> AniListStatusType.Watching
                1 -> AniListStatusType.Completed
                2 -> AniListStatusType.Paused
                3 -> AniListStatusType.Dropped
                4 -> AniListStatusType.Planning
                5 -> AniListStatusType.ReWatching
                else -> AniListStatusType.None
            }
        }

        private suspend fun getSeason(id: Int): SeasonResponse {
            val q = """
               query (${"$"}id: Int = $id) {
                   Media (id: ${"$"}id, type: ANIME) {
                       id
                       idMal
                       coverImage {
                           extraLarge
                           large
                           medium
                           color
                       }
                       title {
                           romaji
                           english
                           native
                           userPreferred
                       }
                       duration
                       episodes
                       genres
                       synonyms
                       averageScore
                       isAdult
                       description(asHtml: false)
                       characters(sort: ROLE page: 1 perPage: 20) {
                           edges {
                               role
                               voiceActors {
                                   name {
                                       userPreferred
                                       full
                                       native
                                   }
                                   age
                                   image {
                                       large
                                       medium
                                   }
                               }
                               node {
                                   name {
                                       userPreferred
                                       full
                                       native
                                   }
                                   age
                                   image {
                                       large
                                       medium
                                   }
                               }
                           }
                       }
                       trailer {
                           id
                           site
                           thumbnail
                       }
                       relations {
                           edges {
                                 id
                                 relationType(version: 2)
                                 node {
                                      id
                                      coverImage {
                                          extraLarge
                                          large
                                          medium
                                          color
                                      }
                                 }
                           }
                       }
                       recommendations {
                           edges {
                               node {
                                   mediaRecommendation {
                                       id
                                       coverImage {
                                           extraLarge
                                           large
                                           medium
                                           color
                                       }
                                       title {
                                           romaji
                                           english
                                           native
                                           userPreferred
                                       }
                                   }
                               }
                           }
                       }
                       nextAiringEpisode {
                           timeUntilAiring
                           episode
                       }
                       format
                   }
               }
         """
            val data = app.post(
                "https://graphql.anilist.co",
                data = mapOf("query" to q),
            ).text

            return tryParseJson(data) ?: throw Exception("Error parsing $data")
        }
    }

    private suspend fun getDataAboutId(auth : AuthData, id: Int): AniListTitleHolder? {
        val q =
            """query (${"$"}id: Int = $id) {
                Media (id: ${"$"}id, type: ANIME) {
                    id
                    episodes
                    isFavourite
                    mediaListEntry {
                        progress
                        status
                        score (format: POINT_100)
                    }
                    title {
                        english
                        romaji
                    }
                }
            }"""

        val data = postApi(auth.token, q, true)
        val d = parseJson<GetDataRoot>(data ?: return null)

        val main = d.data?.media
        if (main?.mediaListEntry != null) {
            return AniListTitleHolder(
                title = main.title,
                id = id,
                isFavourite = main.isFavourite,
                progress = main.mediaListEntry.progress,
                episodes = main.episodes,
                score = main.mediaListEntry.score,
                type = fromIntToAnimeStatus(aniListStatusString.indexOf(main.mediaListEntry.status)),
            )
        } else {
            return AniListTitleHolder(
                title = main?.title,
                id = id,
                isFavourite = main?.isFavourite,
                progress = 0,
                episodes = main?.episodes,
                score = 0,
                type = AniListStatusType.None,
            )
        }
    }

    private suspend fun postApi(token : AuthToken, q: String, cache: Boolean = false): String? {
        return app.post(
            "https://graphql.anilist.co/",
            headers = mapOf(
                "Authorization" to "Bearer ${token.accessToken ?: return null}",
                if (cache) "Cache-Control" to "max-stale=$MAX_STALE" else "Cache-Control" to "no-cache"
            ),
            data = mapOf(
                "query" to URLEncoder.encode(q, "UTF-8")
            ),
            timeout = 5000
        ).text.replace("\\/", "/")
    }

    private suspend fun postDataAboutId(
        auth : AuthData,
        id: Int,
        type: AniListStatusType,
        score: Score?,
        progress: Int?
    ): Boolean {
        val q = if (type == AniListStatusType.None) {
                // Delete logic omitted or simplified for desktop
                return false
            } else {
                """mutation (${"$"}id: Int = $id, ${"$"}status: MediaListStatus = ${
                    aniListStatusString[maxOf(0, type.value)]
                }, ${if (score != null) "${"$"}scoreRaw: Int = ${score.toInt(100)}" else ""} , ${if (progress != null) "${"$"}progress: Int = $progress" else ""}) {
                    SaveMediaListEntry (mediaId: ${"$"}id, status: ${"$"}status, scoreRaw: ${"$"}scoreRaw, progress: ${"$"}progress) {
                        id
                    }
                }"""
            }

        val data = postApi(auth.token, q)
        return !data.isNullOrBlank()
    }

    private suspend fun getUser(token : AuthToken): AniListUser? {
        val q = """
                {
                    Viewer {
                        id
                        name
                        avatar {
                            large
                        }
                    }
                }"""
        val data = postApi(token, q)
        if (data.isNullOrBlank()) return null
        val userData = parseJson<AniListRoot>(data)
        val u = userData.data?.viewer ?: return null
        return AniListUser(u.id, u.name, u.avatar?.large)
    }

    // Interior DTOs for JSON mapping
    data class GetDataRoot(val data: GetDataData?)
    data class GetDataData(val media: GetDataMedia?)
    data class GetDataMedia(val mediaListEntry: GetDataEntry?, val id: Int, val episodes: Int?, val isFavourite: Boolean?, val title: Title?)
    data class GetDataEntry(val progress: Int, val status: String, val score: Int)
    
    data class AniListRoot(val data: AniListData?)
    data class AniListData(val viewer: AniListViewer?)
    data class AniListViewer(val id: Int, val name: String, val avatar: AniListAvatar?)
    data class AniListAvatar(val large: String?)
    data class AniListUser(val id: Int, val name: String, val picture: String?)

    data class AniListTitleHolder(
        val title: Title?,
        val id: Int,
        val isFavourite: Boolean?,
        val progress: Int,
        val episodes: Int?,
        val score: Int,
        val type: AniListStatusType
    )

    data class GetSearchRoot(val data: GetSearchData?)
    data class GetSearchData(val page: GetSearchPage?)
    data class GetSearchPage(val media: List<GetSearchMedia>?)
    data class GetSearchMedia(val id: Int, val bannerImage: String?, val title: Title)

    data class SeasonResponse(val data: SeasonData)
    data class SeasonData(@JsonProperty("Media") val media: SeasonMedia)
    data class SeasonMedia(
        val id: Int,
        val title: Title?,
        val episodes: Int?,
        val description: String?,
        val averageScore: Int?,
        val isAdult: Boolean?,
        val synonyms: List<String>?,
        val bannerImage: String?,
        val characters: CharacterConnection?,
        val nextAiringEpisode: SeasonNextAiringEpisode?,
        val recommendations: RecommendationConnection?,
        val trailer: MediaTrailer?,
        val coverImage: CoverImage?
    )
    data class Title(val romaji: String?, val english: String?, val userPreferred: String?)
    data class CharacterConnection(val edges: List<CharacterEdge>?)
    data class CharacterEdge(val role: String?, val node: Character?, val voiceActors: List<Staff>?)
    data class Character(val name: Name?, val image: Image?)
    data class Staff(val name: Name?, val image: Image?)
    data class Name(val full: String?, val native: String?, val userPreferred: String?)
    data class Image(val medium: String?, val large: String?)
    data class SeasonNextAiringEpisode(val episode: Int?, val timeUntilAiring: Int?)
    data class RecommendationConnection(val edges: List<RecommendationEdge>?)
    data class RecommendationEdge(val node: Recommendation)
    data class Recommendation(val mediaRecommendation: SeasonMedia?)
    data class MediaTrailer(val id: String?, val site: String?)
    data class CoverImage(val extraLarge: String?, val large: String?, val medium: String?)
}
