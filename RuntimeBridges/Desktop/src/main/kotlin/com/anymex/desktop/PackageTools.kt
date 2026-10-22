package com.anymex.desktop

import com.googlecode.d2j.dex.Dex2jar
import com.googlecode.dex2jar.tools.BaksmaliBaseDexExceptionHandler
import net.dongliu.apk.parser.ApkFile
import java.io.BufferedOutputStream
import java.io.File
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.spi.FileSystemProvider
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

object PackageTools {

    private const val MD_NAME = "tachiyomi.extension.name"
    private const val MD_SOURCE_CLASS = "tachiyomi.extension.class"
    private const val MD_SOURCE_FACTORY = "tachiyomi.extension.factory"
    private const val MD_NSFW = "tachiyomi.extension.nsfw"

    private const val MD_ANIME_SOURCE_CLASS = "tachiyomi.animeextension.class"
    private const val MD_ANIME_SOURCE_FACTORY = "tachiyomi.animeextension.factory"
    private const val MD_ANIME_NSFW = "tachiyomi.animeextension.nsfw"

    private val metaDataTag = Regex("""<meta-data\b[^>]*>""")
    private val attribute = Regex("""([\w:.-]+)\s*=\s*["']([^"']*)["']""")

    private fun metaDataOf(manifestXml: String): Map<String, String> {
        val start = manifestXml.indexOf("<application")
        if (start < 0) return emptyMap()
        val end = manifestXml.indexOf("</application>", start).let { if (it < 0) manifestXml.length else it }
        val out = LinkedHashMap<String, String>()
        for (tag in metaDataTag.findAll(manifestXml, start).takeWhile { it.range.first < end }) {
            var name: String? = null
            var value: String? = null
            for (attr in attribute.findAll(tag.value)) {
                when (attr.groupValues[1].substringAfterLast(':')) {
                    "name" -> name = unescapeXml(attr.groupValues[2])
                    "value" -> value = unescapeXml(attr.groupValues[2])
                }
            }
            if (name != null && value != null) out[name] = value
        }
        return out
    }

    private fun unescapeXml(s: String) = s
        .replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")
        .replace("&apos;", "'").replace("&amp;", "&")

    fun parseMeta(apk: File): ExtensionMeta? {
        return try {
            ApkFile(apk).use { parsed ->
                val meta = metaDataOf(parsed.manifestXml)
                val pkgName = parsed.apkMeta.packageName
                val animeClass = meta[MD_ANIME_SOURCE_CLASS]
                val mangaClass = meta[MD_SOURCE_CLASS]
                val isAnime = !animeClass.isNullOrEmpty()

                val sourceClasses = (if (isAnime) animeClass else mangaClass)
                    ?.split(";")
                    ?.map { it.trim() }
                    ?.filter { it.isNotEmpty() }
                    ?: emptyList()
                val factoryClass = if (isAnime) meta[MD_ANIME_SOURCE_FACTORY] else meta[MD_SOURCE_FACTORY]
                val nsfw = (if (isAnime) meta[MD_ANIME_NSFW] else meta[MD_NSFW])?.toIntOrNull() == 1

                ExtensionMeta(
                    pkgName = pkgName,
                    versionName = parsed.apkMeta.versionName ?: "0",
                    versionCode = parsed.apkMeta.versionCode,
                    isNsfw = nsfw,
                    isAnime = isAnime,
                    sourceClasses = sourceClasses,
                    factoryClass = factoryClass,
                    name = meta[MD_NAME] ?: pkgName.substringAfterLast('.'),
                )
            }
        } catch (e: Exception) {
            System.err.println("Error reading manifest of $apk: $e")
            null
        }
    }

    private val zipFsAvailable: Boolean by lazy {
        FileSystemProvider.installedProviders().any { it.scheme.equals("jar", ignoreCase = true) }
    }

    private fun writeJar(converter: Dex2jar, target: Path) {
        if (zipFsAvailable) {
            converter.to(target)
            return
        }
        val dir = Files.createTempDirectory(target.parent ?: Paths.get(""), "anymex-d2j-")
        try {
            converter.to(dir)
            ZipOutputStream(BufferedOutputStream(Files.newOutputStream(target))).use { zip ->
                Files.walk(dir).use { paths ->
                    paths.filter { Files.isRegularFile(it) }.sorted().forEach { file ->
                        zip.putNextEntry(ZipEntry(dir.relativize(file).joinToString("/")))
                        Files.copy(file, zip)
                        zip.closeEntry()
                    }
                }
            }
        } finally {
            dir.toFile().deleteRecursively()
        }
    }

    fun dex2jar(apk: File, jarFile: File) {
        val handler = BaksmaliBaseDexExceptionHandler()
        val converter = Dex2jar.from(apk)
            .withExceptionHandler(handler)
            .reUseReg(false)
            .topoLogicalSort()
            .skipDebug(true)
            .optimizeSynchronized(false)
            .printIR(false)
            .noCode(false)
            .skipExceptions(false)
            .dontSanitizeNames(true)
        writeJar(converter, jarFile.toPath())

        if (handler.hasException()) {
            System.err.println("dex2jar finished with errors for $apk (some classes may be missing)")
        }
    }

    fun resolveClassName(className: String, pkgName: String): String =
        if (className.startsWith(".")) pkgName + className else className
}
