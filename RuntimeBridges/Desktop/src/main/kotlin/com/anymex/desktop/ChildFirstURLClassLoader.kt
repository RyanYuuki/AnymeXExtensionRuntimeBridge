package com.anymex.desktop

import java.net.URL
import java.net.URLClassLoader

class ChildFirstURLClassLoader(
    urls: Array<URL>,
    parent: ClassLoader
) : URLClassLoader(urls, parent) {

    private val systemClassLoader: ClassLoader? =
        ChildFirstURLClassLoader::class.java.classLoader ?: getSystemClassLoader()

    private fun shouldDelegateToParent(name: String?): Boolean {
        if (name == null) return false
        if (name.startsWith("eu.kanade.tachiyomi.extension.") ||
            name.startsWith("eu.kanade.tachiyomi.animeextension.") ||
            name.startsWith("eu.kanade.tachiyomi.multisrc.")) {
            return false
        }
        return name.startsWith("kotlin.") ||
               name.startsWith("kotlinx.") ||
               name.startsWith("okhttp3.") ||
               name.startsWith("okio.") ||
               name.startsWith("androidx.") ||
               name.startsWith("android.") ||
               name.startsWith("xyz.nulldev.") ||
               name.startsWith("com.anymex.") ||
               name.startsWith("com.lagradost.cloudstream3.") ||
               name.startsWith("com.google.gson.") ||
               name.startsWith("eu.kanade.tachiyomi.")
    }

    override fun loadClass(name: String?, resolve: Boolean): Class<*> {
        var c = findLoadedClass(name)

        if (c == null && systemClassLoader != null) {
            try {
                c = systemClassLoader.loadClass(name)
            } catch (_: ClassNotFoundException) {}
        }

        if (c == null && shouldDelegateToParent(name)) {
            try {
                c = parent.loadClass(name)
            } catch (_: ClassNotFoundException) {}
        }

        if (c == null && name != null) {
            try {
                c = findClass(name)
            } catch (_: ClassNotFoundException) {
                if (!shouldDelegateToParent(name)) {
                    try {
                        c = parent.loadClass(name)
                    } catch (_: ClassNotFoundException) {}
                }
            }
        }

        val result = c ?: throw ClassNotFoundException(name)

        if (resolve) {
            resolveClass(result)
        }

        return result
    }

    override fun findClass(name: String): Class<*> {
        val resourceName = name.replace('.', '/') + ".class"
        val url = findResource(resourceName)
        if (url != null) {
            val rawBytes = try { url.openStream().use { it.readBytes() } } catch (_: Throwable) { null }
            if (rawBytes != null) {
                try {
                    val fixedBytes = fixStackMapFrames(name, rawBytes)
                    return defineClass(name, fixedBytes, 0, fixedBytes.size)
                } catch (e: Throwable) {
                    System.err.println("  [CLASS DEFINE FAIL] $name: ${e.javaClass.simpleName}: ${e.message}")
                    e.printStackTrace(System.err)
                }
            }
        }
        return super.findClass(name)
    }

    private fun fixStackMapFrames(className: String, bytes: ByteArray): ByteArray {
        return bytes
    }
}
