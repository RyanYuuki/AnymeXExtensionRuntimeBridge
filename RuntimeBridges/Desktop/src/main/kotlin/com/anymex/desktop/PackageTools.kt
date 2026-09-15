package com.anymex.desktop

import com.googlecode.d2j.dex.Dex2jar
import com.googlecode.dex2jar.tools.BaksmaliBaseDexExceptionHandler
import net.dongliu.apk.parser.ApkFile
import org.w3c.dom.Element
import org.w3c.dom.Node
import java.io.ByteArrayInputStream
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

object PackageTools {

    private const val MD_NAME = "tachiyomi.extension.name"
    private const val MD_SOURCE_CLASS = "tachiyomi.extension.class"
    private const val MD_SOURCE_FACTORY = "tachiyomi.extension.factory"
    private const val MD_NSFW = "tachiyomi.extension.nsfw"

    private const val MD_ANIME_SOURCE_CLASS = "tachiyomi.animeextension.class"
    private const val MD_ANIME_SOURCE_FACTORY = "tachiyomi.animeextension.factory"
    private const val MD_ANIME_NSFW = "tachiyomi.animeextension.nsfw"

    fun parseMeta(apk: File): ExtensionMeta? {
        return try {
            ApkFile(apk).use { parsed ->
                val meta = HashMap<String, String>()
                val manifestXml = parsed.manifestXml
                val doc = DocumentBuilderFactory.newInstance()
                    .newDocumentBuilder()
                    .parse(ByteArrayInputStream(manifestXml.toByteArray()))
                val appTag = doc.getElementsByTagName("application").item(0) ?: return@use null
                val children = appTag.childNodes
                for (i in 0 until children.length) {
                    val node = children.item(i)
                    if (node.nodeType == Node.ELEMENT_NODE && node.nodeName == "meta-data") {
                        val elem = node as Element
                        val name = elem.getAttribute("android:name")
                        val value = elem.getAttribute("android:value")
                        if (name.isNotEmpty()) meta[name] = value
                    }
                }

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

    fun dex2jar(apk: File, jarFile: File) {
        val handler = BaksmaliBaseDexExceptionHandler()
        Dex2jar.from(apk)
            .withExceptionHandler(handler)
            .reUseReg(false)
            .topoLogicalSort()
            .skipDebug(true)
            .optimizeSynchronized(false)
            .printIR(false)
            .noCode(false)
            .skipExceptions(false)
            .dontSanitizeNames(true)
            .to(jarFile.toPath())

        if (handler.hasException()) {
            System.err.println("dex2jar finished with errors for $apk (some classes may be missing)")
        }
    }

    fun resolveClassName(className: String, pkgName: String): String =
        if (className.startsWith(".")) pkgName + className else className
}
