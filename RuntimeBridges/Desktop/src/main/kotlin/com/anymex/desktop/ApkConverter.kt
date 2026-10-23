package com.anymex.desktop

import com.google.gson.Gson
import com.google.gson.JsonObject
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
            com.anymex.desktop.util.BytecodeEditor.fixAndroidClasses(tempJar.toPath(), apkFile.toPath())

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

    fun convertCs3ToJar(cs3Path: String, outJarPath: String) {
        val cs3File = File(cs3Path)
        require(cs3File.exists()) { "CS3 not found: $cs3Path" }

        val tempJar = File.createTempFile("cs3_d2j_", ".jar")
        tempJar.deleteOnExit()

        try {
            PackageTools.dex2jar(cs3File, tempJar)
            com.anymex.desktop.util.BytecodeEditor.fixAndroidClasses(tempJar.toPath(), cs3File.toPath())

            val outFile = File(outJarPath)
            outFile.parentFile?.mkdirs()
            bundleCs3AssetsAndManifest(cs3File, tempJar, outFile)

            System.err.println("[ApkConverter] Converted CS3 ${cs3File.name} → ${outFile.name}")
        } finally {
            tempJar.delete()
        }
    }

    private fun bundleCs3AssetsAndManifest(cs3File: File, tempJar: File, outFile: File) {
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

            var manifestContent: String? = null
            var hasManifestJson = false

            ZipInputStream(cs3File.inputStream()).use { cs3In ->
                var entry = cs3In.nextEntry
                val written = mutableSetOf<String>()
                while (entry != null) {
                    val name = entry.name
                    if (!entry.isDirectory) {
                        if (name == "manifest.json") {
                            hasManifestJson = true
                            jarOut.putNextEntry(ZipEntry(name))
                            cs3In.copyTo(jarOut)
                            jarOut.closeEntry()
                            written.add(name)
                        } else if (name == "plugins.manifest") {
                            manifestContent = cs3In.bufferedReader().readText()
                        } else if (name.startsWith("assets/") || name.startsWith("res/") || name == "resources.arsc") {
                            if (name !in written) {
                                jarOut.putNextEntry(ZipEntry(name))
                                cs3In.copyTo(jarOut)
                                jarOut.closeEntry()
                                written.add(name)
                            }
                        }
                    }
                    entry = cs3In.nextEntry
                }
            }

            if (!hasManifestJson && manifestContent != null) {
                try {
                    val csJson = gson.fromJson(manifestContent, JsonObject::class.java)
                    val bridgeJson = JsonObject().apply {
                        addProperty("pluginClassName", csJson.get("pluginClassName")?.asString ?: "")
                        addProperty("name", csJson.get("name")?.asString ?: "")
                        addProperty("version", csJson.get("version")?.asString ?: "1.0.0")
                        addProperty("requires", 1)
                    }
                    jarOut.putNextEntry(ZipEntry("manifest.json"))
                    jarOut.write(gson.toJson(bridgeJson).toByteArray(Charsets.UTF_8))
                    jarOut.closeEntry()
                } catch (_: Exception) {}
            }
        }
    }
}
