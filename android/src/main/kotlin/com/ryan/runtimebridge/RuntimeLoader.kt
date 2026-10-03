package com.ryan.runtimebridge

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.util.Log
import dalvik.system.BaseDexClassLoader
import java.io.File
import java.util.zip.ZipFile

object RuntimeLoader {

    private const val TAG = "RuntimeLoader"

    @SuppressLint("UnsafeDynamicallyLoadedCode")
    private fun preloadNativeLibraries(context: Context, apkFile: File) {
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
                            zip.getInputStream(entry).use { input ->
                                out.outputStream().use(input::copyTo)
                            }
                            out.setReadable(true)
                            out.setExecutable(true)
                        }

                        try {
                            System.load(out.absolutePath)
                            Log.i(TAG, "Loaded native library: ${out.name}")
                        } catch (e: UnsatisfiedLinkError) {
                            Log.w(TAG, "Native library already loaded or failed: ${out.name}")
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
            if (!tmp.renameTo(dst)) {
                tmp.delete()
                throw IllegalStateException("Failed to replace runtime APK file")
            }
        }

        dst.setReadable(true, false)
        dst.setWritable(false, false)
        dst.setExecutable(false)

        val optimizedDir = File(context.codeCacheDir, "plugin_opt").apply {
            if (!exists()) mkdirs()
        }

        preloadNativeLibraries(context, dst)

        val classLoader = context.classLoader
        val pathListField = BaseDexClassLoader::class.java.getDeclaredField("pathList").apply {
            isAccessible = true
        }
        val pathList = pathListField.get(classLoader)
        val dexElementsField = pathList.javaClass.getDeclaredField("dexElements").apply {
            isAccessible = true
        }
        val beforeElements = dexElementsField.get(pathList) as? Array<*>
        val beforeCount = beforeElements?.size ?: 0

        val addDexPath = pathList.javaClass.getDeclaredMethod(
            "addDexPath",
            String::class.java,
            File::class.java
        ).apply {
            isAccessible = true
        }

        addDexPath.invoke(pathList, dst.absolutePath, optimizedDir)

        try {
            val afterElements = dexElementsField.get(pathList) as? Array<*>
            if (afterElements != null && afterElements.size > beforeCount && beforeElements != null) {
                val newCount = afterElements.size - beforeCount
                val reordered = java.lang.reflect.Array.newInstance(
                    beforeElements.javaClass.componentType!!,
                    afterElements.size
                ) as Array<Any>
                System.arraycopy(afterElements, beforeCount, reordered, 0, newCount)
                System.arraycopy(afterElements, 0, reordered, newCount, beforeCount)
                dexElementsField.set(pathList, reordered)
            }
        } catch (_: Exception) {
        }

        val clazz = classLoader.loadClass(className)
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
