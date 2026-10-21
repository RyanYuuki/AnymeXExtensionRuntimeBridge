package com.anymex.desktop.util

import java.io.IOException
import java.io.InputStream
import java.net.URL
import java.net.URLClassLoader
import java.util.Enumeration

class ChildFirstURLClassLoader(
    urls: Array<URL>,
    parent: ClassLoader? = null,
) : URLClassLoader(urls, parent) {
    // The runtime this loader delegates non-extension classes to. On desktop
    // (`java -jar`) the loader of this class IS the system class loader, so
    // this is identical to `getSystemClassLoader()`. Under the iOS embedded VM
    // the backend runtime lives in EmbeddedBridge's per-backend URLClassLoader,
    // not on the system class path, and `getSystemClassLoader()` would only see
    // the tiny shim — hence delegate to this class' own loader instead.
    private val systemClassLoader: ClassLoader? =
        ChildFirstURLClassLoader::class.java.classLoader ?: getSystemClassLoader()

    override fun loadClass(
        name: String?,
        resolve: Boolean,
    ): Class<*> {
        var c = findLoadedClass(name)

        if (c == null && systemClassLoader != null) {
            try {
                c = systemClassLoader.loadClass(name)
            } catch (_: ClassNotFoundException) {
            }
        }

        if (c == null) {
            c =
                try {
                    findClass(name)
                } catch (_: ClassNotFoundException) {
                    super.loadClass(name, resolve)
                }
        }

        if (resolve) {
            resolveClass(c)
        }

        return c
    }

    override fun getResource(name: String?): URL? =
        systemClassLoader?.getResource(name)
            ?: findResource(name)
            ?: super.getResource(name)

    override fun getResources(name: String?): Enumeration<URL> {
        val systemUrls = systemClassLoader?.getResources(name)
        val localUrls = findResources(name)
        val parentUrls = parent?.getResources(name)
        val urls =
            buildList {
                while (systemUrls?.hasMoreElements() == true) {
                    add(systemUrls.nextElement())
                }

                while (localUrls?.hasMoreElements() == true) {
                    add(localUrls.nextElement())
                }

                while (parentUrls?.hasMoreElements() == true) {
                    add(parentUrls.nextElement())
                }
            }

        return object : Enumeration<URL> {
            val iterator = urls.iterator()

            override fun hasMoreElements() = iterator.hasNext()

            override fun nextElement() = iterator.next()
        }
    }

    override fun getResourceAsStream(name: String?): InputStream? {
        return try {
            getResource(name)?.openStream()
        } catch (_: IOException) {
            return null
        }
    }
}
