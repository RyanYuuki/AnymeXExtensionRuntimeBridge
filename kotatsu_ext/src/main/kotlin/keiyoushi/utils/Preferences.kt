package keiyoushi.utils

import android.app.Application
import android.content.SharedPreferences
import eu.kanade.tachiyomi.source.online.HttpSource
import uy.kohesive.injekt.Injekt

public inline fun HttpSource.getPreferences(
    migration: SharedPreferences.() -> Unit = { },
): SharedPreferences = getPreferences(id).also(migration)

public inline fun HttpSource.getPreferencesLazy(
    crossinline migration: SharedPreferences.() -> Unit = { },
): Lazy<SharedPreferences> = lazy { getPreferences(migration) }

@Suppress("NOTHING_TO_INLINE")
public inline fun getPreferences(sourceId: Long): SharedPreferences {
    return try {
        Injekt.get(Application::class.java).getSharedPreferences("source_$sourceId", 0x0000)
    } catch (e: Exception) {
        android.util.Log.e("AnymeXPreferences", "Failed to get SharedPreferences for source $sourceId: ${e.message}", e)
        keiyoushi.utils.InMemorySharedPreferences()
    }
}
