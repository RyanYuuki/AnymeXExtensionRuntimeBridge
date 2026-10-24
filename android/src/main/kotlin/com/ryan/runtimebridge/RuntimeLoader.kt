package com.ryan.runtimebridge

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.util.Log
import dalvik.system.DexClassLoader
import java.io.File
import java.util.zip.ZipFile

object RuntimeLoader {

    private const val TAG = "RuntimeLoader"

    private class ChildFirstClassLoader(
        dexPath: String,
        optimizedDirectory: String?,
        private val librarySearchPath: String?,
        parent: ClassLoader
    ) : DexClassLoader(dexPath, optimizedDirectory, librarySearchPath, parent) {

        private val systemClassLoader: ClassLoader? = getSystemClassLoader()

        private fun shouldDelegateToParent(name: String?): Boolean {
            if (name == null) return false
            return name.startsWith("android.") ||
                name.startsWith("androidx.") ||
                name.startsWith("java.") ||
                name.startsWith("javax.") ||
                name.startsWith("io.flutter.") ||
                name.startsWith("com.ryan.runtimebridge.")
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

            if (c == null) {
                try {
                    c = findClass(name)
                } catch (_: ClassNotFoundException) {
                    c = super.loadClass(name, resolve)
                }
            }

            if (resolve) {
                resolveClass(c)
            }

            return c
        }

        override fun findLibrary(name: String?): String? {
            if (name != null && librarySearchPath != null) {
                val direct = File(librarySearchPath, "lib$name.so")
                if (direct.exists()) {
                    return direct.absolutePath
                }
            }
            return super.findLibrary(name)
        }
    }

    private fun extractNativeLibraries(context: Context, apkFile: File) {
        val abiList = Build.SUPPORTED_ABIS
        val outDir = File(context.codeCacheDir, "plugin_libs").apply {
            mkdirs()
        }

        ZipFile(apkFile).use { zip ->
            var matchedAbi: String? = null
            for (abi in abiList) {
                val prefix = "lib/$abi/"
                val hasMatch = zip.entries().asSequence().any {
                    it.name.startsWith(prefix) && it.name.endsWith(".so")
                }
                if (hasMatch) {
                    matchedAbi = abi
                    break
                }
            }

            if (matchedAbi != null) {
                val prefix = "lib/$matchedAbi/"
                zip.entries().asSequence()
                    .filter { it.name.startsWith(prefix) && it.name.endsWith(".so") }
                    .forEach { entry ->
                        val libName = entry.name.substringAfterLast('/')
                        val out = File(outDir, libName)
                        if (!out.exists() || out.length() != entry.size) {
                            if (out.exists()) {
                                out.setWritable(true, false)
                                out.delete()
                            }
                            zip.getInputStream(entry).use { input ->
                                out.outputStream().use(input::copyTo)
                            }
                            out.setReadable(true, false)
                            out.setExecutable(true, false)
                            out.setWritable(false, false)
                        }
                    }
            }
        }
    }

    @SuppressLint("SetWorldReadable")
    fun loadRuntime(
        context: Context,
        path: String,
        className: String = "com.anymex.runtimehost.RuntimeBridge"
    ): LoadedBridge {
        val externalFile = File(path)
        if (!externalFile.exists()) {
            throw IllegalArgumentException("Runtime APK not found at $path")
        }

        val privateDir = File(context.filesDir, "plugins").apply {
            if (!exists()) mkdirs()
        }

        val dst = File(privateDir, externalFile.name)
        val shouldCopy = !dst.exists() ||
                externalFile.length() != dst.length() ||
                externalFile.lastModified() != dst.lastModified()

        if (shouldCopy) {
            val tmp = File(privateDir, "${externalFile.name}.tmp")
            externalFile.inputStream().use { input ->
                tmp.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            tmp.setLastModified(externalFile.lastModified())
            if (dst.exists()) {
                dst.setWritable(true, false)
                dst.delete()
            }
            if (!tmp.renameTo(dst)) {
                tmp.inputStream().use { input ->
                    dst.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                tmp.delete()
            }
            val optimizedDir = File(context.codeCacheDir, "plugin_opt")
            if (optimizedDir.exists()) {
                optimizedDir.deleteRecursively()
                optimizedDir.mkdirs()
            }
        }

        dst.setReadable(true, false)
        dst.setWritable(false, false)
        dst.setExecutable(false)

        val optimizedDir = File(context.codeCacheDir, "plugin_opt").apply {
            if (!exists()) mkdirs()
        }

        extractNativeLibraries(context, dst)

        val nativeLibsDir = File(context.codeCacheDir, "plugin_libs")
        val loader = ChildFirstClassLoader(
            dst.absolutePath,
            optimizedDir.absolutePath,
            nativeLibsDir.absolutePath,
            context.classLoader
        )

        val clazz = loader.loadClass(className)
        val instance = try {
            clazz.getField("INSTANCE").get(null)
        } catch (_: Exception) {
            clazz.getDeclaredConstructor().newInstance()
        }

        return LoadedBridge(clazz, instance)
    }
}

data class LoadedBridge(
    val bridgeClass: Class<*>,
    val bridgeInstance: Any
)
