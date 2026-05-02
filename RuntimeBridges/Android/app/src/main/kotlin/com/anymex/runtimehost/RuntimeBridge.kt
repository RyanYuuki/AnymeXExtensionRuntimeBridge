package com.anymex.runtimehost

import android.content.Context
import android.util.Log
import com.anymex.runtimehost.aniyomi.AnimeSourceMethods
import com.anymex.runtimehost.aniyomi.AniyomiExtensionManager
import com.anymex.runtimehost.aniyomi.AniyomiSourceMethods
import com.anymex.runtimehost.aniyomi.MangaSourceMethods
import com.lagradost.cloudstream3.AcraApplication
import com.lagradost.cloudstream3.APIHolder
import com.lagradost.cloudstream3.CloudStreamApp
import com.lagradost.cloudstream3.plugins.PluginManager
import com.lagradost.cloudstream3.plugins.RepositoryManager
import com.lagradost.cloudstream3.utils.DataStore
import eu.kanade.tachiyomi.animesource.model.Video
import eu.kanade.tachiyomi.animesource.model.Track
import eu.kanade.tachiyomi.animesource.model.TimeStamp
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.online.AnimeHttpSource
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.online.HttpSource
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.Json
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingletonFactory
import uy.kohesive.injekt.api.get
import java.io.File


@Suppress("unused")
object RuntimeBridge {

    private const val TAG = "RuntimeBridge"
    private var extensionManager: AniyomiExtensionManager? = null
    private var initialized = false

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val csPathRegistry = mutableMapOf<String, String>() 
    private val csMetadataRegistry = mutableMapOf<String, ProviderMetadata>() 
    private val aniyomiPathRegistry = mutableMapOf<String, String>() 
    private val aniyomiIsAnimeRegistry = mutableMapOf<String, Boolean>() 
    private val activeRequests = mutableMapOf<String, Job>() 

    data class ProviderMetadata(
        val id: String,
        val name: String,
        val mainUrl: String,
        val lang: String,
        val sourcePlugin: String?,
        val iconUrl: String?,
        val internalName: String?
    )

    @JvmOverloads
    fun initialize(context: Context, settingsMap: Map<String, Any?>? = null) {
        if (initialized) return

        Log.i(TAG, "Initializing Runtime Host - Version: 1.0.6")
        
        try {
            okhttp3.OkHttp.initialize(context.applicationContext)
        } catch (e: Throwable) {
            Log.e(TAG, "Failed or skipped OkHttp startup: ${e.message}")
        }

        try {
            Injekt.addSingletonFactory<android.app.Application> {
                context.applicationContext as android.app.Application
            }
            Injekt.addSingletonFactory { NetworkHelper(context.applicationContext) }
            Injekt.addSingletonFactory { Injekt.get<NetworkHelper>().client }
            Injekt.addSingletonFactory {
                Json {
                    ignoreUnknownKeys = true
                    explicitNulls = false
                }
            }

            DataStore.init(context.applicationContext)
            AcraApplication.context = context.applicationContext
            CloudStreamApp.context = context.applicationContext

            extensionManager = AniyomiExtensionManager(context.applicationContext)
            Injekt.addSingletonFactory<AniyomiExtensionManager> { extensionManager!! }

            val aniyomiExtensionsPath = settingsMap?.get("aniyomiExtensionsPath") as? String
            if (aniyomiExtensionsPath != null) {
                Log.i(TAG, "Proactive Loading: Starting Aniyomi extension scan at $aniyomiExtensionsPath")
                scope.launch {
                    getInstalledAnimeExtensions(context.applicationContext, aniyomiExtensionsPath)
                    getInstalledMangaExtensions(context.applicationContext)
                    Log.i(TAG, "Proactive Loading: Aniyomi background scan completed")
                }
            }
        } catch (e: Throwable) {
            Log.e(TAG, "Init Step 2 Failed (Skipping Critical Setup): ${e.message}")
        }

        Log.i(TAG, "Runtime Host Initialized successfully")
        initialized = true
    }

    fun cancelRequest(token: String): Boolean {
        val job = activeRequests[token] ?: return false
        Log.i(TAG, "Cancelling network request for token: $token")
        job.cancel()
        activeRequests.remove(token)
        return true
    }

    fun shutdown() {
        Log.i(TAG, "Shutting down Runtime Host...")
        try {
            initialized = false
            activeRequests.values.forEach { it.cancel() }
            activeRequests.clear()

            csPathRegistry.clear()
            csMetadataRegistry.clear()
            aniyomiPathRegistry.clear()
            aniyomiIsAnimeRegistry.clear()
            Log.i(TAG, "Runtime Host shutdown complete")
        } catch (e: Exception) {
            Log.e(TAG, "Error during shutdown: ${e.message}")
        }
    }

    fun getInstalledAnimeExtensions(context: Context, path: String?): List<Map<String, Any?>> {
        val extensions = extensionManager(context).fetchInstalledAnimeExtensions(path)
        
        extensions.forEach { ext ->
            ext.sources.forEach { source ->
                aniyomiPathRegistry[source.id.toString()] = path ?: ""
                aniyomiIsAnimeRegistry[source.id.toString()] = true
            }
        }

        return extensions.flatMap { ext ->
            ext.sources.map { source ->
                val baseUrl = (source as? AnimeHttpSource)?.baseUrl.orEmpty()
                mapOf(
                    "id" to source.id.toString(),
                    "name" to ext.name,
                    "baseUrl" to baseUrl,
                    "lang" to source.lang,
                    "isNsfw" to ext.isNsfw,
                    "iconUrl" to ext.iconUrl,
                    "version" to ext.versionName,
                    "pkgName" to ext.pkgName,
                    "itemType" to 1,
                    "hasUpdate" to ext.hasUpdate,
                    "isObsolete" to ext.isObsolete,
                    "isShared" to ext.isShared,
                )
            }
        }
    }

    fun getInstalledMangaExtensions(context: Context): List<Map<String, Any?>> {
        val extensions = extensionManager(context).fetchInstalledMangaExtensions()
        
        extensions.forEach { ext ->
            ext.sources.forEach { source ->
                aniyomiPathRegistry[source.id.toString()] = "" 
                aniyomiIsAnimeRegistry[source.id.toString()] = false
            }
        }

        return extensions.flatMap { ext ->
            ext.sources.map { source ->
                val baseUrl = (source as? HttpSource)?.baseUrl.orEmpty()
                mapOf(
                    "id" to source.id.toString(),
                    "name" to ext.name,
                    "baseUrl" to baseUrl,
                    "lang" to source.lang,
                    "isNsfw" to ext.isNsfw,
                    "iconUrl" to ext.iconUrl,
                    "version" to ext.versionName,
                    "pkgName" to ext.pkgName,
                    "itemType" to 0,
                    "hasUpdate" to ext.hasUpdate,
                    "isObsolete" to ext.isObsolete,
                )
            }
        }
    }

    @JvmStatic
    @JvmOverloads
    fun aniyomiGetPopular(
        context: Context,
        sourceId: String,
        isAnime: Boolean,
        page: Int,
        parameters: Map<String, Any?>? = null,
    ): Map<String, Any?> {
        val token = parameters?.get("token") as? String
        val job = scope.async {
            val m = media(context, sourceId, isAnime)
            m.parameters = parameters
            val res = m.getPopular(page)
            mapOf("list" to res.animes.map { it.toMap() }, "hasNextPage" to res.hasNextPage)
        }
        if (token != null) activeRequests[token] = job
        return try {
            runBlocking { job.await() }
        } finally {
            if (token != null) activeRequests.remove(token)
        }
    }

    @JvmStatic
    @JvmOverloads
    fun aniyomiGetLatestUpdates(
        context: Context,
        sourceId: String,
        isAnime: Boolean,
        page: Int,
        parameters: Map<String, Any?>? = null,
    ): Map<String, Any?> {
        val token = parameters?.get("token") as? String
        val job = scope.async {
            val m = media(context, sourceId, isAnime)
            m.parameters = parameters
            val res = m.getLatestUpdates(page)
            mapOf("list" to res.animes.map { it.toMap() }, "hasNextPage" to res.hasNextPage)
        }
        if (token != null) activeRequests[token] = job
        return try {
            runBlocking { job.await() }
        } finally {
            if (token != null) activeRequests.remove(token)
        }
    }

    @JvmStatic
    @JvmOverloads
    fun aniyomiSearch(
        context: Context,
        sourceId: String,
        isAnime: Boolean,
        query: String,
        page: Int,
        parameters: Map<String, Any?>? = null,
    ): Map<String, Any?> {
        val token = parameters?.get("token") as? String
        val job = scope.async {
            val m = media(context, sourceId, isAnime)
            m.parameters = parameters
            val res = m.getSearchResults(query, page)
            mapOf("list" to res.animes.map { it.toMap() }, "hasNextPage" to res.hasNextPage)
        }
        if (token != null) activeRequests[token] = job
        return try {
            runBlocking { job.await() }
        } finally {
            if (token != null) activeRequests.remove(token)
        }
    }

    @JvmStatic
    @JvmOverloads
    fun aniyomiGetDetail(
        context: Context,
        sourceId: String,
        isAnime: Boolean,
        mediaMap: Map<String, Any?>,
        parameters: Map<String, Any?>? = null,
    ): Map<String, Any?> {
        val token = parameters?.get("token") as? String
        val job = scope.async {
            val anime = SAnime.create().apply {
                title = mediaMap["title"] as? String ?: ""
                url = mediaMap["url"] as? String ?: ""
                thumbnail_url = mediaMap["thumbnail_url"] as? String
                description = mediaMap["description"] as? String
                artist = mediaMap["artist"] as? String
                author = mediaMap["author"] as? String
                genre = mediaMap["genre"] as? String
            }
            val m = media(context, sourceId, isAnime)
            m.parameters = parameters
            
            val details = m.getDetails(anime)
            val eps = if (isAnime) m.getEpisodeList(anime) else m.getChapterList(anime)

            mapOf(
                "title" to anime.title,
                "url" to anime.url,
                "cover" to anime.thumbnail_url,
                "artist" to details.artist,
                "author" to details.author,
                "description" to details.description,
                "genre" to details.getGenres(),
                "status" to details.status,
                "episodes" to eps.map {
                    mapOf(
                        "name" to it.name,
                        "url" to it.url,
                        "date_upload" to it.date_upload,
                        "episode_number" to it.episode_number,
                        "scanlator" to it.scanlator
                    )
                }
            )
        }
        if (token != null) activeRequests[token] = job
        return try {
            runBlocking { job.await() }
        } finally {
            if (token != null) activeRequests.remove(token)
        }
    }

    @JvmStatic
    @JvmOverloads
    fun aniyomiGetVideoList(
        context: Context,
        sourceId: String,
        isAnime: Boolean,
        episodeMap: Map<String, Any?>,
        parameters: Map<String, Any?>? = null,
    ): List<Map<String, Any?>> {
        val token = parameters?.get("token") as? String
        val job = scope.async {
            val ep = SEpisode.create().apply {
                name = episodeMap["name"] as? String ?: ""
                url = episodeMap["url"] as? String ?: ""
                episode_number = (episodeMap["episode_number"] as? Number)?.toFloat() ?: 0f
                scanlator = episodeMap["scanlator"] as? String
            }
            val m = media(context, sourceId, isAnime)
            m.parameters = parameters
            m.getVideoList(ep).map { videoToMap(it) }
        }
        if (token != null) activeRequests[token] = job
        return try {
            runBlocking { job.await() }
        } finally {
            if (token != null) activeRequests.remove(token)
        }
    }


    @JvmStatic
    @JvmOverloads
    fun aniyomiGetPageList(
        context: Context,
        sourceId: String,
        isAnime: Boolean,
        chapterMap: Map<String, Any?>,
        parameters: Map<String, Any?>? = null,
    ): List<Map<String, Any?>> {
        val token = parameters?.get("token") as? String
        val job = scope.async {
            val chapter = SChapter.create().apply {
                name = chapterMap["name"] as? String ?: ""
                url = chapterMap["url"] as? String ?: ""
            }
            val m = media(context, sourceId, isAnime)
            m.parameters = parameters
            
            m.getPageList(chapter).map { page ->
                val imageUrl = page.imageUrl ?: ""
                mapOf("url" to imageUrl, "headers" to emptyMap<String, String>())
            }
        }
        if (token != null) activeRequests[token] = job
        return try {
            runBlocking { job.await() }
        } finally {
            if (token != null) activeRequests.remove(token)
        }
    }

    private data class PrefHandlers(
        val pref: androidx.preference.Preference,
        val click: androidx.preference.Preference.OnPreferenceClickListener?,
        val change: androidx.preference.Preference.OnPreferenceChangeListener?
    )

    private val sourcePreferences = mutableMapOf<String, MutableMap<String, PrefHandlers>>()

    @android.annotation.SuppressLint("RestrictedApi")
    fun aniyomiGetPreference(
        context: Context,
        sourceId: String,
        isAnime: Boolean,
    ): List<Map<String, Any?>> = runBlocking {
        sourcePreferences.remove(sourceId)
        
        val prefManager = androidx.preference.PreferenceManager(context)
        prefManager.sharedPreferencesName = "source_$sourceId"
        
        val screen = prefManager.createPreferenceScreen(context)
        
        try {
            media(context, sourceId, isAnime).setupPreferenceScreen(screen)
        } catch (e: com.anymex.runtimehost.aniyomi.NoPreferenceScreenException) {
            return@runBlocking emptyList<Map<String, Any?>>()
        }

        val list = mutableListOf<Map<String, Any?>>()
        val store = sourcePreferences.getOrPut(sourceId) { mutableMapOf() }

        fun walk(group: androidx.preference.PreferenceGroup) {
            for (i in 0 until group.preferenceCount) {
                val p = group.getPreference(i)
                store[p.key] = PrefHandlers(p, p.onPreferenceClickListener, p.onPreferenceChangeListener)

                val map = mutableMapOf(
                    "key" to p.key,
                    "title" to p.title?.toString(),
                    "summary" to p.summary?.toString(),
                    "enabled" to p.isEnabled,
                    "type" to when (p) {
                        is androidx.preference.ListPreference -> "list"
                        is androidx.preference.MultiSelectListPreference -> "multi_select"
                        is androidx.preference.SwitchPreferenceCompat -> "switch"
                        is androidx.preference.EditTextPreference -> "text"
                        is androidx.preference.CheckBoxPreference -> "checkbox"
                        else -> "other"
                    },
                    "value" to when (p) {
                        is androidx.preference.ListPreference -> p.value
                        is androidx.preference.MultiSelectListPreference -> p.values.toList()
                        is androidx.preference.SwitchPreferenceCompat -> p.isChecked
                        is androidx.preference.EditTextPreference -> p.text
                        is androidx.preference.CheckBoxPreference -> p.isChecked
                        else -> null
                    }
                )

                if (p is androidx.preference.ListPreference) {
                    map["entries"] = p.entries?.map { it.toString() }
                    map["entryValues"] = p.entryValues?.map { it.toString() }
                } else if (p is androidx.preference.MultiSelectListPreference) {
                    map["entries"] = p.entries?.map { it.toString() }
                    map["entryValues"] = p.entryValues?.map { it.toString() }
                }

                list += map
                if (p is androidx.preference.PreferenceCategory) walk(p)
            }
        }

        walk(screen)
        list
    }

    fun aniyomiSavePreference(
        context: Context,
        sourceId: String,
        key: String,
        action: String?,
        value: Any?,
    ): Boolean = runBlocking {
        val isAnime = aniyomiIsAnimeRegistry[sourceId] ?: true
        val handler = sourcePreferences[sourceId]?.get(key) ?: return@runBlocking false
        val pref = handler.pref
        
        val actualAction = action ?: "change"

        val actualValue = if (pref is androidx.preference.MultiSelectListPreference && value is List<*>) {
            value.filterIsInstance<String>().toSet()
        } else {
            value
        }

        if (actualAction == "click") {
            handler.click?.onPreferenceClick(pref)
        } else {
            handler.change?.onPreferenceChange(pref, actualValue)
        }

        val prefs = context.getSharedPreferences("source_$sourceId", Context.MODE_PRIVATE)
        val editor = prefs.edit()

        when (pref) {
            is androidx.preference.SwitchPreferenceCompat -> {
                val b = value as Boolean
                pref.isChecked = b
                editor.putBoolean(key, b)
            }
            is androidx.preference.ListPreference -> {
                val s = value as String
                pref.value = s
                editor.putString(key, s)
            }
            is androidx.preference.EditTextPreference -> {
                val s = value as String
                pref.text = s
                editor.putString(key, s)
            }
            is androidx.preference.MultiSelectListPreference -> {
                val newSet = when (value) {
                    is List<*> -> value.filterIsInstance<String>().toSet()
                    is Set<*> -> value.filterIsInstance<String>().toSet()
                    else -> emptySet()
                }
                pref.values = newSet.toMutableSet()
                editor.putStringSet(key, newSet)
            }
            is androidx.preference.CheckBoxPreference -> {
                val b = value as Boolean
                pref.isChecked = b
                editor.putBoolean(key, b)
            }
        }
        editor.apply()

        true
    }

    fun csLoadPlugin(context: Context, path: String): Boolean {
        val file = File(path)
        if (!file.exists()) {
            Log.e(TAG, "Plugin file not found: $path")
            return false
        }
        
        return runBlocking {
            val success = PluginManager.loadPlugin(context, file)
            if (success) {
                val pluginData = PluginManager.getPluginsOnline()
                APIHolder.apis.forEach { provider ->
                    if (provider.sourcePlugin == path || provider.sourcePlugin?.contains(file.name) == true) {
                        val data = pluginData.firstOrNull { it.filePath == provider.sourcePlugin }
                        csPathRegistry[provider.name] = path
                        csMetadataRegistry[provider.name] = ProviderMetadata(
                            id = provider.name,
                            name = provider.name,
                            mainUrl = provider.mainUrl,
                            lang = provider.lang,
                            sourcePlugin = provider.sourcePlugin,
                            iconUrl = data?.iconUrl,
                            internalName = data?.internalName
                        )
                        Log.d(TAG, "Registered CloudStream Provider: ${provider.name}")
                    }
                }
            }
            success
        }
    }

    fun csUnloadPlugin(apiName: String): Boolean {
        if (apiName.isBlank()) return false
        
        val provider = APIHolder.apis.find { it.name.equals(apiName, ignoreCase = true) }
        val internalName = provider?.sourcePlugin ?: csMetadataRegistry[apiName]?.mainUrl ?: apiName
        
        Log.i(TAG, "Attempting to unload plugin: $apiName (Internal Path/ID: $internalName)")

        val removedCount = APIHolder.apis.count { 
            it.name.equals(apiName, ignoreCase = true) || 
            (it.sourcePlugin != null && it.sourcePlugin!!.endsWith(internalName, ignoreCase = true)) 
        }

        APIHolder.apis.removeIf { 
            it.name.equals(apiName, ignoreCase = true) || 
            (it.sourcePlugin != null && it.sourcePlugin!!.endsWith(internalName, ignoreCase = true)) 
        }

        csMetadataRegistry.remove(apiName)
        
        val fileName = internalName.substringAfterLast("/")
        if (fileName.length > 3) {
            val extraRemoved = APIHolder.apis.count { it.sourcePlugin?.endsWith(fileName, ignoreCase = true) == true }
            APIHolder.apis.removeIf { it.sourcePlugin?.endsWith(fileName, ignoreCase = true) == true }
            Log.d(TAG, "Extra removal check for '$fileName' hit $extraRemoved providers")
        }

        PluginManager.unloadPlugin(internalName)
        Log.i(TAG, "Unloaded $removedCount providers for plugin: $apiName")
        return true
    }

    fun csGetRegisteredProviders(): List<Map<String, Any?>> {
        return csMetadataRegistry.values.map { provider ->
            mapOf(
                "id" to provider.name,
                "name" to provider.name,
                "url" to provider.mainUrl,
                "language" to provider.lang,
                "plugin" to (provider.sourcePlugin ?: ""),
                "iconUrl" to (provider.iconUrl ?: ""),
                "internalName" to (provider.internalName ?: provider.name),
                "itemType" to 1,
            )
        }
    }

    @JvmStatic
    @JvmOverloads
    fun csSearch(
        context: Context,
        query: String,
        apiName: String?,
        page: Int,
        parameters: Map<String, Any?>? = null,
    ): Map<String, Any?> {
        val token = parameters?.get("token") as? String
        val job = scope.async {
            if (apiName != null) {
                val provider = APIHolder.apis.find { it.name.equals(apiName, ignoreCase = true) }
                    ?: return@async mapOf("list" to emptyList<Any>(), "hasNextPage" to false)
                com.anymex.runtimehost.cloudstream.CloudStreamSourceMethods(provider).search(query, page)
            } else {
                val allItems = APIHolder.apis.flatMap { provider ->
                    @Suppress("UNCHECKED_CAST")
                    com.anymex.runtimehost.cloudstream.CloudStreamSourceMethods(provider)
                        .search(query, page)["list"] as? List<Map<String, Any?>> ?: emptyList()
                }
                mapOf("list" to allItems, "hasNextPage" to false)
            }
        }
        if (token != null) activeRequests[token] = job
        return try {
            runBlocking { job.await() }
        } finally {
            if (token != null) activeRequests.remove(token)
        }
    }

    @JvmStatic
    @JvmOverloads
    fun csGetDetail(
        context: Context,
        apiName: String,
        url: String,
        parameters: Map<String, Any?>? = null,
    ): Map<String, Any?> {
        val token = parameters?.get("token") as? String
        val job = scope.async {
            try {
                val provider = APIHolder.apis.find { it.name.equals(apiName, ignoreCase = true) }
                    ?: return@async mapOf("title" to null, "url" to url, "error" to "Provider not found")
                com.anymex.runtimehost.cloudstream.CloudStreamSourceMethods(provider).getDetails(url) ?: emptyMap()
            } catch (e: Exception) {
                Log.e(TAG, "csGetDetail failed: ${e.message}")
                mapOf("title" to null, "url" to url, "error" to e.message)
            }
        }
        if (token != null) activeRequests[token] = job
        return try {
            runBlocking { job.await() }
        } finally {
            if (token != null) activeRequests.remove(token)
        }
    }

    @JvmStatic
    @JvmOverloads
    fun csGetVideoList(
        context: Context,
        apiName: String,
        url: String,
        parameters: Map<String, Any?>? = null,
    ): List<Map<String, Any?>> {
        val token = parameters?.get("token") as? String
        val job = scope.async {
            val provider = APIHolder.apis.find { it.name.equals(apiName, ignoreCase = true) }
                ?: throw IllegalArgumentException("Provider '$apiName' not found")
            com.anymex.runtimehost.cloudstream.CloudStreamSourceMethods(provider).loadLinks(url)
        }
        if (token != null) activeRequests[token] = job
        return try {
            runBlocking { job.await() }
        } finally {
            if (token != null) activeRequests.remove(token)
        }
    }

    @JvmStatic
    @JvmOverloads
    fun csGetVideoListStream(
        context: Context,
        apiName: String,
        url: String,
        onLinkFound: (Map<String, Any?>) -> Unit,
        parameters: Map<String, Any?>? = null,
    ) {
        val token = parameters?.get("token") as? String
        val extractionJob = kotlinx.coroutines.Job()
        if (token != null) activeRequests[token] = extractionJob

        try {
            runBlocking(extractionJob + kotlinx.coroutines.Dispatchers.IO) {
                val provider = APIHolder.apis.find { it.name.equals(apiName, ignoreCase = true) }
                    ?: throw IllegalArgumentException("Provider '$apiName' not found")
                
                com.anymex.runtimehost.cloudstream.CloudStreamSourceMethods(provider)
                    .loadLinksStream(url, onLinkFound)

                while (coroutineContext[kotlinx.coroutines.Job]?.isActive == true) {
                    kotlinx.coroutines.delay(10000)
                }
            }
        } catch (e: Exception) {
            if (e !is kotlinx.coroutines.CancellationException) {
                Log.e("RuntimeBridge", "Extraction error: ${e.message}")
            }
        } finally {
            if (token != null) activeRequests.remove(token)
        }
        
        System.gc()
    }

    private fun extensionManager(context: Context): AniyomiExtensionManager {
        if (extensionManager == null) initialize(context)
        return extensionManager!!
    }

    private fun media(context: Context, sourceId: String, isAnime: Boolean): AniyomiSourceMethods =
        if (isAnime) AnimeSourceMethods(sourceId) else MangaSourceMethods(sourceId)

    private fun okhttp3.Headers?.toMap(): Map<String, String> = this?.names()?.associateWith { name -> get(name).orEmpty() }.orEmpty()

    private fun SAnime.toMap(): Map<String, Any?> = mapOf(
        "url" to url,
        "title" to title,
        "artist" to artist,
        "author" to author,
        "description" to description,
        "genre" to getGenres(),
        "status" to status,
        "thumbnail_url" to thumbnail_url,
        "background_url" to background_url,
        "update_strategy" to update_strategy.name,
        "fetch_type" to fetch_type.name,
        "season_number" to season_number,
        "initialized" to initialized
    )

    private fun videoToMap(it: Video): Map<String, Any?> = mapOf(
        "title" to it.videoTitle,
        "url" to it.videoUrl,
        "quality" to it.resolution,
        "bitrate" to it.bitrate,
        "headers" to it.headers?.toMap(),
        "preferred" to it.preferred,
        "subtitles" to it.subtitleTracks.map { t -> mapOf("file" to t.url, "label" to t.lang) },
        "audios" to it.audioTracks.map { t -> mapOf("file" to t.url, "label" to t.lang) },
        "timestamps" to it.timestamps.map { ts ->
            mapOf(
                "start" to ts.start,
                "end" to ts.end,
                "name" to ts.name,
                "type" to ts.type.name
            )
        },
        "mpvArgs" to it.mpvArgs.toMap(),
        "ffmpegStreamArgs" to it.ffmpegStreamArgs.toMap(),
        "ffmpegVideoArgs" to it.ffmpegVideoArgs.toMap(),
        "internalData" to it.internalData,
        "initialized" to it.initialized
    )
}
