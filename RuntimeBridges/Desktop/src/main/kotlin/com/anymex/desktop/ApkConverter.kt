package com.anymex.desktop

import com.google.gson.Gson
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

object ApkConverter {

    private val gson = Gson()

    fun convertApkToJar(apkPath: String, outJarPath: String) {
        val apkFile = File(apkPath)
        require(apkFile.exists()) { "APK not found: $apkPath" }

        val meta = PackageTools.parseMeta(apkFile)

        val tempJar = File.createTempFile("dex2jar_out_", ".jar")
        tempJar.deleteOnExit()

        try {
            PackageTools.dex2jar(apkFile, tempJar)
            JarFixer.fixStackmapFrames(tempJar)

            val outFile = File(outJarPath)
            outFile.parentFile?.mkdirs()
            bundleAssetsAndMetadata(apkFile, tempJar, outFile, meta)

            System.err.println("[ApkConverter] Converted & bytecode-fixed ${apkFile.name} → ${outFile.name}")
        } finally {
            tempJar.delete()
        }
    }

    private fun bundleAssetsAndMetadata(apkFile: File, tempJar: File, outFile: File, meta: ExtensionMeta?) {
        ZipOutputStream(outFile.outputStream()).use { jarOut ->
            ZipInputStream(tempJar.inputStream()).use { jarIn ->
                var entry = jarIn.nextEntry
                while (entry != null) {
                    jarOut.putNextEntry(ZipEntry(entry.name))
                    jarIn.copyTo(jarOut)
                    jarOut.closeEntry()
                    entry = jarIn.nextEntry
                }
            }

            if (meta != null) {
                try {
                    jarOut.putNextEntry(ZipEntry("META-INF/anymex-extension.json"))
                    jarOut.write(gson.toJson(meta).toByteArray(Charsets.UTF_8))
                    jarOut.closeEntry()
                } catch (_: Exception) {}
            }

            ZipInputStream(apkFile.inputStream()).use { apkIn ->
                var entry = apkIn.nextEntry
                val written = mutableSetOf<String>()
                while (entry != null) {
                    val name = entry.name
                    if (!entry.isDirectory &&
                        (name == "manifest.json" || name.startsWith("assets/")) &&
                        name !in written
                    ) {
                        try {
                            jarOut.putNextEntry(ZipEntry(name))
                            apkIn.copyTo(jarOut)
                            jarOut.closeEntry()
                            written.add(name)
                        } catch (_: Exception) {}
                    }
                    entry = apkIn.nextEntry
                }
            }
        }
    }
}
