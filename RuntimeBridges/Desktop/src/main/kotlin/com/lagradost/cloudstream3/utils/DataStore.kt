package com.lagradost.cloudstream3.utils

import android.content.Context
import android.content.SharedPreferences
import com.fasterxml.jackson.databind.json.JsonMapper
import com.lagradost.cloudstream3.mapper
import com.lagradost.cloudstream3.mvvm.logError
import java.util.Calendar
import java.util.Date
import java.util.GregorianCalendar
import kotlin.reflect.KClass
import kotlin.reflect.KProperty

// Mock implementation of DataStore to run on Desktop JVM without Android dependencies.
// We use a simple in-memory map here.
object DataStore {
    @PublishedApi internal val memoryPrefs = mutableMapOf<String, String>()

    @PublishedApi internal var appContext: Context? = null
    val mapper: JsonMapper = com.lagradost.cloudstream3.mapper

    fun init(context: Context) {
        appContext = context
    }

    @PublishedApi internal fun getFolderName(folder: String, path: String): String = "$folder/$path"

    fun Context.getKeys(folder: String): List<String> {
        val fixedFolder = folder.trimEnd('/') + "/"
        return memoryPrefs.keys.filter { it.startsWith(fixedFolder) }
    }

    fun Context.removeKey(folder: String, path: String) = removeKey(getFolderName(folder, path))

    fun Context.containsKey(path: String): Boolean = memoryPrefs.containsKey(path)

    fun Context.removeKey(path: String) {
        memoryPrefs.remove(path)
    }

    fun Context.removeKeys(folder: String): Int {
        val keys = getKeys("$folder/")
        keys.forEach { memoryPrefs.remove(it) }
        return keys.size
    }

    fun <T> Context.setKey(path: String, value: T) {
        try {
            memoryPrefs[path] = mapper.writeValueAsString(value)
        } catch (e: Exception) {
            logError(e)
        }
    }

    fun <T> Context.getKey(path: String, valueType: Class<T>): T? {
        return try {
            val json = memoryPrefs[path] ?: return null
            mapper.readValue(json, valueType)
        } catch (e: Exception) {
            null
        }
    }

    fun <T> Context.setKey(folder: String, path: String, value: T) = setKey(getFolderName(folder, path), value)

    inline fun <reified T : Any> String.toKotlinObject(): T = mapper.readValue(this, T::class.java)

    fun <T> String.toKotlinObject(valueType: Class<T>): T = mapper.readValue(this, valueType)

    inline fun <reified T : Any> Context.getKey(path: String, defVal: T?): T? {
        return try {
            val json = memoryPrefs[path] ?: return defVal
            json.toKotlinObject()
        } catch (e: Exception) {
            null
        }
    }

    inline fun <reified T : Any> Context.getKey(path: String): T? = getKey(path, null)

    inline fun <reified T : Any> Context.getKey(folder: String, path: String): T? =
        getKey(getFolderName(folder, path), null)

    inline fun <reified T : Any> Context.getKey(folder: String, path: String, defVal: T?): T? =
        getKey(getFolderName(folder, path), defVal) ?: defVal


    fun <T> setKey(path: String, value: T) {
        appContext?.setKey(path, value)
    }

    fun <T> setKey(folder: String, path: String, value: T) {
        appContext?.setKey(folder, path, value)
    }

    inline fun <reified T : Any> getKey(path: String, defVal: T?): T? =
        appContext?.getKey(path, defVal)

    inline fun <reified T : Any> getKey(path: String): T? = appContext?.getKey(path)

    inline fun <reified T : Any> getKey(folder: String, path: String): T? =
        appContext?.getKey(folder, path)

    inline fun <reified T : Any> getKey(folder: String, path: String, defVal: T?): T? =
        appContext?.getKey(folder, path, defVal)

    fun getKeys(folder: String): List<String>? = appContext?.getKeys(folder)

    fun removeKey(folder: String, path: String) { appContext?.removeKey(folder, path) }

    fun removeKey(path: String) { appContext?.removeKey(path) }

    fun <T : Any> getKeyClass(path: String, valueType: Class<T>): T? =
        appContext?.getKey(path, valueType)

    fun <T : Any> setKeyClass(path: String, value: T) { appContext?.setKey(path, value) }

    fun removeKeys(folder: String): Int? = appContext?.removeKeys(folder)

    fun Int.toYear(): Date = GregorianCalendar.getInstance().also { it.set(Calendar.YEAR, this) }.time
}

class PreferenceDelegate<T : Any>(
    val key: String, val default: T
) {
    private val klass: KClass<out T> = default::class
    private var cache: T? = null

    operator fun getValue(self: Any?, property: KProperty<*>): T {
        if (cache != null) return cache!!
        val json = DataStore.getKeyClass(key, String::class.java)
        if (json == null) return default
        val parsed = mapper.readValue(json, klass.java)
        cache = parsed ?: default
        return cache!!
    }

    operator fun setValue(self: Any?, property: KProperty<*>, t: T?) {
        cache = t
        if (t == null) {
            DataStore.removeKey(key)
        } else {
            DataStore.setKey(key, mapper.writeValueAsString(t))
        }
    }
}
