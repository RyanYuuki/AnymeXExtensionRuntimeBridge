package com.anymex.desktop

import com.googlecode.d2j.dex.Dex2jar
import com.googlecode.d2j.reader.MultiDexFileReader
import com.googlecode.dex2jar.tools.BaksmaliBaseDexExceptionHandler
import java.io.File
import java.nio.file.Files
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

object ApkConverter {

    fun convertApkToJar(apkPath: String, outJarPath: String) {
        val apkFile = File(apkPath)
        require(apkFile.exists()) { "APK not found: $apkPath" }

        val tempDex = File.createTempFile("dex2jar_classes_", ".dex")
        tempDex.deleteOnExit()

        ZipInputStream(apkFile.inputStream()).use { zip ->
            var entry = zip.nextEntry
            var found = false
            while (entry != null) {
                if (entry.name == "classes.dex") {
                    tempDex.outputStream().use { zip.copyTo(it) }
                    found = true
                    break
                }
                entry = zip.nextEntry
            }
            if (!found) throw IllegalArgumentException("No classes.dex found in APK: $apkPath")
        }

        val tempJar = File.createTempFile("dex2jar_out_", ".jar")
        tempJar.deleteOnExit()
        dex2jar(tempDex.absolutePath, tempJar.absolutePath)
        tempDex.delete()

        val outFile = File(outJarPath)
        outFile.parentFile?.mkdirs()
        bundleAssetsFromApk(apkFile, tempJar, outFile)
        tempJar.delete()

        System.err.println("[ApkConverter] Converted ${apkFile.name} → ${outFile.name}")
    }

    private fun dex2jar(dexFile: String, jarFile: String) {
        val jarFilePath = File(jarFile).toPath()
        val reader = MultiDexFileReader.open(Files.readAllBytes(File(dexFile).toPath()))
        val handler = BaksmaliBaseDexExceptionHandler()

        Dex2jar
            .from(reader)
            .withExceptionHandler(handler)
            .reUseReg(false)
            .topoLogicalSort()
            .skipDebug(true)
            .optimizeSynchronized(false)
            .printIR(false)
            .noCode(false)
            .skipExceptions(false)
            .dontSanitizeNames(true)
            .to(jarFilePath)
    }

    private fun bundleAssetsFromApk(apkFile: File, tempJar: File, outFile: File) {
        ZipOutputStream(outFile.outputStream()).use { jarOut ->
            ZipInputStream(tempJar.inputStream()).use { jarIn ->
                var entry = jarIn.nextEntry
                while (entry != null) {
                    if (!entry.name.startsWith("META-INF/")) {
                        jarOut.putNextEntry(ZipEntry(entry.name))
                        jarIn.copyTo(jarOut)
                        jarOut.closeEntry()
                    }
                    entry = jarIn.nextEntry
                }
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
