package com.anymex.desktop

import android.app.Application
import android.content.Context
import androidx.preference.*
import com.google.gson.Gson
import eu.kanade.tachiyomi.PreferenceScreen as EuPreferenceScreen
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.ConfigurableAnimeSource
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.ConfigurableSource
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import uy.kohesive.injekt.api.addSingletonFactory
import eu.kanade.tachiyomi.network.NetworkHelper
import kotlinx.serialization.json.Json
object AniyomiSourceMethods {
    private val gson = Gson()
    
    private data class PrefHandlers(
        val pref: Preference,
        val click: Preference.OnPreferenceClickListener?,
        val change: Preference.OnPreferenceChangeListener?
    )
    private val sourcePreferences = mutableMapOf<String, MutableMap<String, PrefHandlers>>()

    private inline fun <T> safe(block: () -> T?, default: T): T = try { block() ?: default } catch (e: Exception) { default }

    private fun SAnime.toDetailsMap() = mapOf<String, Any>(
        "title" to safe({ title }, ""),
        "url" to safe({ url }, ""),
        "cover" to safe({ thumbnail_url }, ""),
        "description" to safe({ description }, ""),
        "author" to safe({ author }, ""),
        "artist" to safe({ artist }, ""),
        "genre" to safe({ getGenres() }, emptyList<String>()),
        "status" to safe({ status }, 0),
        "background_url" to safe({ background_url }, ""),
        "update_strategy" to safe({ update_strategy.name }, "UNKNOWN"),
        "fetch_type" to safe({ fetch_type.name }, "UNKNOWN"),
        "season_number" to safe({ season_number }, -1.0),
        "initialized" to safe({ initialized }, false)
    )

    private fun SManga.toDetailsMap() = mapOf<String, Any>(
        "title" to safe({ title }, ""),
        "url" to safe({ url }, ""),
        "cover" to safe({ thumbnail_url }, ""),
        "description" to safe({ description }, ""),
        "author" to safe({ author }, ""),
        "artist" to safe({ artist }, ""),
        "genre" to safe({ getGenres() }, emptyList<String>()),
        "status" to safe({ status }, 0),
        "update_strategy" to safe({ update_strategy.name }, "UNKNOWN"),
        "initialized" to safe({ initialized }, false)
    )

    private fun parseNumberFromName(name: String): Float {
        val prefixRegex = Regex("""(?i)(?:chapter|ch\.|ep\.|episode)\s*(\d+(\.\d+)?)""")
        val prefixMatch = prefixRegex.find(name)
        if (prefixMatch != null) return prefixMatch.groupValues[1].toFloatOrNull() ?: -1f
        
        val fallbackRegex = Regex("""(\d+(\.\d+)?)""")
        return fallbackRegex.find(name)?.groupValues?.get(1)?.toFloatOrNull() ?: -1f
    }

    private fun SEpisode.toDetailsMap(): Map<String, Any> {
        val currentName = safe({ name }, "")
        var epNum = safe({ episode_number }, -1f)
        if (epNum == -1f || epNum < 0f) epNum = parseNumberFromName(currentName)
        
        return mapOf<String, Any>(
            "name" to currentName,
            "url" to safe({ url }, ""),
            "date_upload" to safe({ date_upload }, 0L),
            "episode_number" to epNum,
            "scanlator" to safe({ scanlator }, ""),
            "fillermark" to safe({ fillermark }, false),
            "summary" to safe({ summary }, ""),
            "preview_url" to safe({ preview_url }, "")
        )
    }

    private fun SChapter.toDetailsMap(): Map<String, Any> {
        val currentName = safe({ name }, "")
        var chNum = safe({ chapter_number }, -1f)
        if (chNum == -1f || chNum < 0f) chNum = parseNumberFromName(currentName)

        return mapOf<String, Any>(
            "name" to currentName,
            "url" to safe({ url }, ""),
            "date_upload" to safe({ date_upload }, 0L),
            "chapter_number" to chNum,
            "episode_number" to chNum, 
            "scanlator" to safe({ scanlator }, "")
        )
    }

    suspend fun fetchPopular(className: String, page: Int, isAnimeObj: Any?): String {
        val anime = when (isAnimeObj) {
            is Boolean -> isAnimeObj
            is String -> isAnimeObj.toBoolean()
            else -> isAnimeObj.toString().toBoolean()
        }
        System.err.println("Fetching popular for $className (isAnime: $anime)")
        return try {
            if (anime) {
                val source = DesktopExtensionLoader.loadedAnimeSources[className] as? AnimeCatalogueSource
                    ?: return "{\"list\": [], \"hasNextPage\": false}"
                val result = source.getPopularAnime(page)
                val map = mapOf("list" to result.animes.map { it.toDetailsMap() }, "hasNextPage" to result.hasNextPage)
                gson.toJson(map)
            } else {
                val source = DesktopExtensionLoader.loadedMangaSources[className] as? CatalogueSource
                    ?: return "{\"list\": [], \"hasNextPage\": false}"
                val result = source.getPopularManga(page)
                val map = mapOf("list" to result.mangas.map { it.toDetailsMap() }, "hasNextPage" to result.hasNextPage)
                gson.toJson(map)
            }
        } catch (e: Exception) {
            "{\"list\": [], \"hasNextPage\": false, \"error\": \"${e.message}\"}"
        }
    }

    suspend fun fetchLatestUpdates(className: String, page: Int, isAnimeObj: Any?): String {
        val anime = when (isAnimeObj) {
            is Boolean -> isAnimeObj
            is String -> isAnimeObj.toBoolean()
            else -> isAnimeObj.toString().toBoolean()
        }
        return try {
            if (anime) {
                val source = DesktopExtensionLoader.loadedAnimeSources[className] as? AnimeCatalogueSource
                    ?: return "{\"list\": [], \"hasNextPage\": false}"
                val result = source.getLatestUpdates(page)
                gson.toJson(mapOf("list" to result.animes.map { it.toDetailsMap() }, "hasNextPage" to result.hasNextPage))
            } else {
                val source = DesktopExtensionLoader.loadedMangaSources[className] as? CatalogueSource
                    ?: return "{\"list\": [], \"hasNextPage\": false}"
                val result = source.getLatestUpdates(page)
                gson.toJson(mapOf("list" to result.mangas.map { it.toDetailsMap() }, "hasNextPage" to result.hasNextPage))
            }
        } catch (e: Exception) {
            "{\"list\": [], \"hasNextPage\": false, \"error\": \"${e.message}\"}"
        }
    }

    suspend fun search(className: String, query: String, page: Int, isAnimeObj: Any?): String {
        val anime = when (isAnimeObj) {
            is Boolean -> isAnimeObj
            is String -> isAnimeObj.toBoolean()
            else -> isAnimeObj.toString().toBoolean()
        }
        return try {
            if (anime) {
                val source = DesktopExtensionLoader.loadedAnimeSources[className] as? AnimeCatalogueSource
                    ?: return "{\"list\": [], \"hasNextPage\": false}"
                val result = source.getSearchAnime(page, query, source.getFilterList())
                gson.toJson(mapOf("list" to result.animes.map { it.toDetailsMap() }, "hasNextPage" to result.hasNextPage))
            } else {
                val source = DesktopExtensionLoader.loadedMangaSources[className] as? CatalogueSource
                    ?: return "{\"list\": [], \"hasNextPage\": false}"
                val result = source.getSearchManga(page, query, source.getFilterList())
                gson.toJson(mapOf("list" to result.mangas.map { it.toDetailsMap() }, "hasNextPage" to result.hasNextPage))
            }
        } catch (e: Exception) {
            "{\"list\": [], \"hasNextPage\": false, \"error\": \"${e.message}\"}"
        }
    }

    suspend fun fetchDetails(className: String, url: String, title: String, cover: String, isAnimeObj: Any?): String {
        val anime = when (isAnimeObj) {
            is Boolean -> isAnimeObj
            is String -> isAnimeObj.toBoolean()
            else -> isAnimeObj.toString().toBoolean()
        }
        return try {
            val map = mutableMapOf<String, Any?>()
            if (anime) {
                val source = DesktopExtensionLoader.loadedAnimeSources[className] ?: return "{}"
                val animeObj = SAnime.create().apply {
                    this.url = url
                    this.title = title
                    this.thumbnail_url = cover
                }
                val details = source.getAnimeDetails(animeObj)
                val episodes = source.getEpisodeList(animeObj)
                map.putAll(details.toDetailsMap())
                map["episodes"] = episodes.map { it.toDetailsMap() }
            } else {
                val source = DesktopExtensionLoader.loadedMangaSources[className] ?: return "{}"
                val manga = SManga.create().apply {
                    this.url = url
                    this.title = title
                    this.thumbnail_url = cover
                }
                val details = source.getMangaDetails(manga)
                val chapters = source.getChapterList(manga)
                map.putAll(details.toDetailsMap())
                map["episodes"] = chapters.map { it.toDetailsMap() }
            }
            gson.toJson(map)
        } catch (e: Exception) {
            "{\"error\": \"${e.message}\"}"
        }
    }

    suspend fun fetchVideoList(className: String, url: String, name: String): String {
        return try {
            val source = DesktopExtensionLoader.loadedAnimeSources[className] ?: return "[]"
            val episode = SEpisode.create().apply {
                this.url = url
                this.name = name
            }
            val videos = source.getVideoList(episode)
            gson.toJson(videos.map { video ->
                mapOf(
                    "title" to (try { video.videoTitle } catch (e: Exception) { "" }),
                    "url" to (try { video.videoUrl } catch (e: Exception) { "" }),
                    "quality" to (try { video.resolution } catch (e: Exception) { null }),
                    "bitrate" to (try { video.bitrate } catch (e: Exception) { null }),
                    "headers" to (try { video.headers?.names()?.associateWith { video.headers!![it] ?: "" } } catch (e: Exception) { emptyMap<String, String>() }),
                    "preferred" to (try { video.preferred } catch (e: Exception) { false }),
                    "subtitles" to (try { 
                        val tracks = video.subtitleTracks
                        tracks.map { mapOf("file" to it.url, "label" to it.lang) } 
                    } catch (e: Throwable) { 
                        System.err.println("[ERROR] Failed to map subtitles for $url")
                        e.printStackTrace()
                        emptyList<Map<String, String>>() 
                    }),
                    "audios" to (try { video.audioTracks.map { mapOf("file" to it.url, "label" to it.lang) } } catch (e: Exception) { emptyList<Map<String, String>>() }),
                    "timestamps" to (try { video.timestamps.map { mapOf("start" to it.start, "end" to it.end, "name" to it.name, "type" to it.type.name) } } catch (e: Exception) { emptyList<Map<String, Any>>() }),
                    "mpvArgs" to (try { video.mpvArgs.toMap() } catch (e: Exception) { emptyMap<String, String>() }),
                    "ffmpegStreamArgs" to (try { video.ffmpegStreamArgs.toMap() } catch (e: Exception) { emptyMap<String, String>() }),
                    "ffmpegVideoArgs" to (try { video.ffmpegVideoArgs.toMap() } catch (e: Exception) { emptyMap<String, String>() }),
                    "internalData" to (try { video.internalData } catch (e: Exception) { "" }),
                    "initialized" to (try { video.initialized } catch (e: Exception) { false })
                )
            })
        } catch (e: Throwable) {
            System.err.println("[ERROR] fetchVideoList failed for $url")
            e.printStackTrace()
            "[]"
        }
    }

    suspend fun fetchPageList(className: String, url: String, name: String): String {
        return try {
            val source = DesktopExtensionLoader.loadedMangaSources[className] ?: return "[]"
            val chapter = SChapter.create().apply {
                this.url = url
                this.name = name
            }
            val pages = source.getPageList(chapter)
            gson.toJson(pages.map { page ->
                mapOf("url" to page.imageUrl, "headers" to emptyMap<String, String>())
            })
        } catch (e: Exception) { "[]" }
    }

    fun getPreferences(sourceId: String, isAnime: Any?): String {
        val isAnimeBool = when (isAnime) {
            is Boolean -> isAnime
            is String -> isAnime.toBoolean()
            else -> false
        }
        sourcePreferences.remove(sourceId)
        val context = Injekt.get<Application>()
        val screen = EuPreferenceScreen(context)
        
        try {
            val sources = if (isAnimeBool) DesktopExtensionLoader.loadedAnimeSources else DesktopExtensionLoader.loadedMangaSources
            val source = sources[sourceId] ?: return "[]"
            var called = false
            if (isAnimeBool && source is ConfigurableAnimeSource) {
                source.setupPreferenceScreen(screen)
                called = true
            } else if (!isAnimeBool && source is ConfigurableSource) {
                source.setupPreferenceScreen(screen)
                called = true
            }
            if (!called) {
                try {
                    val method = source.javaClass.methods.find { it.name == "setupPreferenceScreen" }
                    if (method != null) {
                        method.invoke(source, screen)
                        called = true
                    }
                } catch (_: Exception) {}
            }
        } catch (e: Exception) {
            return "[]"
        }

        val list = mutableListOf<Map<String, Any?>>()
        val store = sourcePreferences.getOrPut(sourceId) { mutableMapOf() }
        val prefs = context.getSharedPreferences("source_$sourceId", Context.MODE_PRIVATE)

        fun walk(group: PreferenceGroup) {
            for (i in 0 until group.getPreferenceCount()) {
                val p = group.getPreference(i)
                if (p.key != null) {
                    store[p.key] = PrefHandlers(p, p.getOnPreferenceClickListener(), p.getOnPreferenceChangeListener())
                    when (p) {
                        is ListPreference -> p.value = prefs.getString(p.key, p.value)
                        is MultiSelectListPreference -> {
                            val saved = prefs.getStringSet(p.key, p.values)
                            if (saved != null) p.values = saved.toMutableSet()
                        }
                        is SwitchPreferenceCompat -> p.isChecked = prefs.getBoolean(p.key, p.isChecked)
                        is EditTextPreference -> p.text = prefs.getString(p.key, p.text)
                        is CheckBoxPreference -> p.isChecked = prefs.getBoolean(p.key, p.isChecked)
                    }
                }

                var summary = p.summary?.toString()
                if (summary != null && summary.contains("%s")) {
                    summary = when (p) {
                        is ListPreference -> {
                            val index = p.entryValues?.indexOf(p.value) ?: -1
                            if (index >= 0 && p.entries != null && index < p.entries!!.size) {
                                summary.replace("%s", p.entries!![index].toString())
                            } else {
                                summary.replace("%s", p.value ?: "")
                            }
                        }
                        is EditTextPreference -> summary.replace("%s", p.text ?: "")
                        else -> summary
                    }
                }

                val map = mutableMapOf(
                    "key" to p.key,
                    "title" to p.title?.toString(),
                    "summary" to summary,
                    "enabled" to p.isEnabled,
                    "type" to when (p) {
                        is ListPreference -> "list"
                        is MultiSelectListPreference -> "multi_select"
                        is SwitchPreferenceCompat -> "switch"
                        is EditTextPreference -> "text"
                        is CheckBoxPreference -> "checkBox"
                        else -> "other"
                    },
                    "value" to when (p) {
                        is ListPreference -> p.value
                        is MultiSelectListPreference -> p.values?.toList()
                        is SwitchPreferenceCompat -> p.isChecked
                        is EditTextPreference -> p.text
                        is CheckBoxPreference -> p.isChecked
                        else -> null
                    }
                )

                if (p is ListPreference) {
                    map["entries"] = p.entries?.map { it.toString() }
                    map["entryValues"] = p.entryValues?.map { it.toString() }
                } else if (p is MultiSelectListPreference) {
                    map["entries"] = p.entries?.map { it.toString() }
                    map["entryValues"] = p.entryValues?.map { it.toString() }
                } else if (p is EditTextPreference) {
                    map["dialogTitle"] = p.dialogTitle?.toString()
                    map["dialogMessage"] = p.dialogMessage?.toString()
                }

                list += map
                if (p is PreferenceCategory) walk(p)
            }
        }
        walk(screen)
        return gson.toJson(list)
    }

    fun savePreference(sourceId: String, key: String, value: Any?, isAnime: Any?): String {
        val context = Injekt.get<Application>()
        val prefs = context.getSharedPreferences("source_$sourceId", Context.MODE_PRIVATE)
        val editor = prefs.edit()
        
        try {
            val hMap = sourcePreferences[sourceId]
            val handler = hMap?.get(key)
            
            if (handler != null) {
                val pref = handler.pref
                val newValue = when (pref) {
                    is MultiSelectListPreference -> {
                        when (value) {
                            is Iterable<*> -> value.map { it.toString() }.toSet()
                            else -> emptySet<String>()
                        }
                    }
                    is ListPreference -> value?.toString() ?: ""
                    is EditTextPreference -> value?.toString() ?: ""
                    is SwitchPreferenceCompat -> {
                        when (value) {
                            is Boolean -> value
                            is String -> value.toBoolean()
                            else -> value as? Boolean ?: false
                        }
                    }
                    is CheckBoxPreference -> {
                        when (value) {
                            is Boolean -> value
                            is String -> value.toBoolean()
                            else -> value as? Boolean ?: false
                        }
                    }
                    else -> value
                }

                val shouldSave = try {
                    handler.change?.onPreferenceChange(pref, newValue) ?: true
                } catch (e: Exception) { true }
                
                if (!shouldSave) return "success"

                when (pref) {
                    is SwitchPreferenceCompat -> {
                        val b = (newValue as? Boolean) ?: false
                        pref.isChecked = b
                        editor.putBoolean(key, b)
                    }
                    is CheckBoxPreference -> {
                        val b = (newValue as? Boolean) ?: false
                        pref.isChecked = b
                        editor.putBoolean(key, b)
                    }
                    is ListPreference -> {
                        val s = newValue?.toString() ?: ""
                        pref.value = s
                        editor.putString(key, s)
                    }
                    is EditTextPreference -> {
                        val s = newValue?.toString() ?: ""
                        pref.text = s
                        editor.putString(key, s)
                    }
                    is MultiSelectListPreference -> {
                        val set = (newValue as? Set<*>)?.map { it.toString() }?.toSet() ?: emptySet()
                        pref.values = set.toMutableSet()
                        editor.putStringSet(key, set)
                    }
                }
            } else {
                when (value) {
                    is Boolean -> editor.putBoolean(key, value)
                    is String -> editor.putString(key, value)
                    is Iterable<*> -> editor.putStringSet(key, value.map { it.toString() }.toSet())
                    else -> editor.putString(key, value?.toString())
                }
            }
            
            editor.apply()
            return "success"
        } catch (e: Exception) { return "failure" }
    }

    val classLoaders = mutableMapOf<String, java.net.URLClassLoader>()

    private fun isAssignableByClassName(clazz: Class<*>, targetNames: List<String>): Boolean {
        var current: Class<*>? = clazz
        while (current != null) {
            if (targetNames.contains(current.name)) return true
            for (iface in current.interfaces) {
                if (isInterfaceAssignable(iface, targetNames)) return true
            }
            current = current.superclass
        }
        return false
    }

    private fun isInterfaceAssignable(iface: Class<*>, targetNames: List<String>): Boolean {
        if (targetNames.contains(iface.name)) return true
        for (parent in iface.interfaces) {
            if (isInterfaceAssignable(parent, targetNames)) return true
        }
        return false
    }

    private fun instantiateSource(clazz: Class<*>): Any? {
        try {
            return clazz.getDeclaredConstructor().newInstance()
        } catch (e: Exception) {
            try {
                return clazz.getDeclaredField("INSTANCE").get(null)
            } catch (e2: Exception) {
                val cause = e.cause ?: e
                System.err.println("    [INSTANTIATE ERROR] ${clazz.simpleName} constructor failed: ${cause.javaClass.simpleName}: ${cause.message}")
                return null
            }
        }
    }

    private var initialized = false

    @JvmStatic
    fun initialize() {
        if (initialized) return
        
        val context = Application()
        
        Injekt.addSingletonFactory<Application> { context }
        Injekt.addSingletonFactory<Context> { context }
        Injekt.addSingletonFactory { NetworkHelper(context) }
        Injekt.addSingletonFactory { Injekt.get<NetworkHelper>().client }
        Injekt.addSingletonFactory {
            Json {
                ignoreUnknownKeys = true
                explicitNulls = false
            }
        }

        initialized = true
        System.err.println("Desktop Runtime initialized!")
    }

    fun loadExtensions(folderPath: String): String {
        initialize()
        val folder = java.io.File(folderPath)
        System.err.println("Scanning for JARs in: " + folder.absolutePath)
        
        if (!folder.exists() || !folder.isDirectory) {
            System.err.println("Folder does not exist or is not a directory!")
            return "[]"
        }

        val jsonArray = com.google.gson.JsonArray()
        val animeTargetNames = listOf(
            "eu.kanade.tachiyomi.animesource.AnimeSource",
            "eu.kanade.tachiyomi.animesource.AnimeCatalogueSource",
            "eu.kanade.tachiyomi.animesource.online.AnimeHttpSource"
        )
        val mangaTargetNames = listOf(
            "eu.kanade.tachiyomi.source.MangaSource",
            "eu.kanade.tachiyomi.source.CatalogueSource",
            "eu.kanade.tachiyomi.source.online.HttpSource"
        )

        folder.listFiles { file -> file.extension == "jar" }?.forEach { jar ->
            System.err.println("Processing JAR: ${jar.name}")
            try {
                val tempJar = java.io.File.createTempFile("ext_${jar.nameWithoutExtension}_", ".jar")
                tempJar.deleteOnExit()
                jar.copyTo(tempJar, overwrite = true)

                val classLoader = java.net.URLClassLoader(arrayOf(tempJar.toURI().toURL()), DesktopExtensionLoader::class.java.classLoader)
                var extractedVersion = "1.0.0"
                var extractedPkgName = ""

                val zipFile1 = java.util.zip.ZipFile(jar)
                for (entry in zipFile1.entries()) {
                    if (entry.name.endsWith("BuildConfig.class")) {
                        val className = entry.name.replace("/", ".").removeSuffix(".class")
                        try {
                            val clazz = Class.forName(className, false, classLoader)
                            try { extractedVersion = clazz.getField("VERSION_NAME").get(null) as String } catch(_: Exception) {}
                            try { extractedPkgName = clazz.getField("APPLICATION_ID").get(null) as String } catch(_: Exception) {}
                            if (extractedPkgName.isEmpty()) extractedPkgName = clazz.getPackage()?.name ?: ""
                        } catch (e: Exception) {
                            System.err.println("Could not parse BuildConfig: ${e.message}")
                        }
                        break
                    }
                }
                zipFile1.close()

                val zipFile = java.util.zip.ZipFile(jar)
                val entries = zipFile.entries()
                
                while (entries.hasMoreElements()) {
                    val entry = entries.nextElement()
                    if (entry.name.endsWith(".class") && !entry.name.contains("$")) {
                        val className = entry.name.replace("/", ".").removeSuffix(".class")
                        
                        if (className.contains(".dto.")) continue

                        try {
                            val clazz = Class.forName(className, false, classLoader)
                            if (clazz.isInterface || java.lang.reflect.Modifier.isAbstract(clazz.modifiers)) continue

                            if (isAssignableByClassName(clazz, animeTargetNames)) {
                                val instance = instantiateSource(clazz) as? eu.kanade.tachiyomi.animesource.AnimeSource
                                if (instance != null) {
                                    val extObj = com.google.gson.JsonObject().apply {
                                        addProperty("id", instance.id.toString())
                                        addProperty("name", instance.name)
                                        addProperty("lang", instance.lang)
                                        addProperty("type", "anime")
                                        val baseUrl = (instance as? eu.kanade.tachiyomi.animesource.online.AnimeHttpSource)?.baseUrl ?: ""
                                        addProperty("baseUrl", baseUrl)
                                        addProperty("isNsfw", false)
                                        addProperty("version", extractedVersion)
                                        addProperty("pkgName", extractedPkgName)
                                        addProperty("className", className)
                                        addProperty("itemType", 1)
                                        addProperty("hasUpdate", false)
                                        addProperty("isObsolete", false)
                                        addProperty("isShared", false)
                                    }
                                    jsonArray.add(extObj)
                                    DesktopExtensionLoader.loadedAnimeSources[instance.id.toString()] = instance
                                    classLoaders[instance.id.toString()] = classLoader
                                }
                            } else if (isAssignableByClassName(clazz, listOf("eu.kanade.tachiyomi.animesource.AnimeSourceFactory"))) {
                                val factory = instantiateSource(clazz) as? eu.kanade.tachiyomi.animesource.AnimeSourceFactory
                                if (factory != null) {
                                    factory.createSources().forEach { src ->
                                        val extObj = com.google.gson.JsonObject().apply {
                                            addProperty("id", src.id.toString())
                                            addProperty("name", src.name)
                                            addProperty("lang", src.lang)
                                            addProperty("type", "anime")
                                            val baseUrl = (src as? eu.kanade.tachiyomi.animesource.online.AnimeHttpSource)?.baseUrl ?: ""
                                            addProperty("baseUrl", baseUrl)
                                            addProperty("isNsfw", false)
                                            addProperty("version", extractedVersion)
                                            addProperty("pkgName", extractedPkgName)
                                            addProperty("className", src.javaClass.name)
                                            addProperty("itemType", 1)
                                            addProperty("hasUpdate", false)
                                            addProperty("isObsolete", false)
                                            addProperty("isShared", false)
                                        }
                                        jsonArray.add(extObj)
                                        DesktopExtensionLoader.loadedAnimeSources[src.id.toString()] = src
                                        classLoaders[src.id.toString()] = classLoader
                                    }
                                }
                            } else if (isAssignableByClassName(clazz, mangaTargetNames)) {
                                val instance = instantiateSource(clazz) as? eu.kanade.tachiyomi.source.MangaSource
                                if (instance != null) {
                                    val extObj = com.google.gson.JsonObject().apply {
                                        addProperty("id", instance.id.toString())
                                        addProperty("name", instance.name)
                                        addProperty("lang", instance.lang)
                                        addProperty("type", "manga")
                                        val baseUrl = (instance as? eu.kanade.tachiyomi.source.online.HttpSource)?.baseUrl ?: ""
                                        addProperty("baseUrl", baseUrl)
                                        addProperty("isNsfw", false)
                                        addProperty("version", extractedVersion)
                                        addProperty("pkgName", extractedPkgName)
                                        addProperty("className", className)
                                        addProperty("itemType", 0)
                                        addProperty("hasUpdate", false)
                                        addProperty("isObsolete", false)
                                    }
                                    jsonArray.add(extObj)
                                    DesktopExtensionLoader.loadedMangaSources[instance.id.toString()] = instance
                                    classLoaders[instance.id.toString()] = classLoader
                                }
                            } else if (isAssignableByClassName(clazz, listOf("eu.kanade.tachiyomi.source.SourceFactory"))) {
                                val factory = instantiateSource(clazz) as? eu.kanade.tachiyomi.source.SourceFactory
                                if (factory != null) {
                                    factory.createSources().filterIsInstance<eu.kanade.tachiyomi.source.MangaSource>().forEach { src ->
                                        val extObj = com.google.gson.JsonObject().apply {
                                            addProperty("id", src.id.toString())
                                            addProperty("name", src.name)
                                            addProperty("lang", src.lang)
                                            addProperty("type", "manga")
                                            val baseUrl = (src as? eu.kanade.tachiyomi.source.online.HttpSource)?.baseUrl ?: ""
                                            addProperty("baseUrl", baseUrl)
                                            addProperty("isNsfw", false)
                                            addProperty("version", extractedVersion)
                                            addProperty("pkgName", extractedPkgName)
                                            addProperty("className", src.javaClass.name)
                                            addProperty("itemType", 0)
                                            addProperty("hasUpdate", false)
                                            addProperty("isObsolete", false)
                                        }
                                        jsonArray.add(extObj)
                                        DesktopExtensionLoader.loadedMangaSources[src.id.toString()] = src
                                        classLoaders[src.id.toString()] = classLoader
                                    }
                                }
                            }
                        } catch (e: Exception) {}
                    }
                }
                zipFile.close()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        
        return gson.toJson(jsonArray)
    }

    fun unloadExtension(sourceId: String) {
        DesktopExtensionLoader.loadedAnimeSources.remove(sourceId)
        DesktopExtensionLoader.loadedMangaSources.remove(sourceId)
        sourcePreferences.remove(sourceId)
        try {
            classLoaders.remove(sourceId)?.close()
            System.err.println("Successfully closed ClassLoader and unloaded extension: $sourceId")
        } catch (e: Exception) {
            System.err.println("Error closing classloader for $sourceId: ${e.message}")
        }
    }
}
