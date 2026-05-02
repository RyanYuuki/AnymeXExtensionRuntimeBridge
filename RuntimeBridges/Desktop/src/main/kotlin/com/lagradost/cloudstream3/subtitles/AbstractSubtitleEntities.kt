package com.lagradost.cloudstream3.subtitles

import com.lagradost.cloudstream3.TvType

class AbstractSubtitleEntities {
    data class SubtitleEntity(
        var idPrefix : String,
        var name: String = "",
        var lang: String = "en",
        var data: String = "",
        var type: TvType = TvType.Movie,
        var source: String,
        var epNumber: Int? = null,
        var seasonNumber: Int? = null,
        var year: Int? = null,
        var isHearingImpaired: Boolean = false,
        var headers: Map<String, String> = emptyMap()
    )

    data class SubtitleSearch(
        var query: String = "",
        var lang: String? = null,
        var imdbId: String? = null,
        var tmdbId: Int? = null,
        var malId: Int? = null,
        var aniListId: Int? = null,
        var epNumber: Int? = null,
        var seasonNumber: Int? = null,
        var year: Int? = null
    )
}
