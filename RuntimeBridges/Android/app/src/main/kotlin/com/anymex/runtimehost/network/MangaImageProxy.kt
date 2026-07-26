package com.anymex.runtimehost.network

import android.content.Context
import eu.kanade.tachiyomi.source.online.HttpSource
import eu.kanade.tachiyomi.source.model.Page
import kotlinx.coroutines.runBlocking
import java.io.OutputStream
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import kotlin.concurrent.thread
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get

object MangaImageProxy {
    private var serverSocket: ServerSocket? = null
    var port: Int = 0
        private set

    fun start() {
        if (serverSocket != null) return
        thread(isDaemon = true, name = "MangaImageProxy") {
            try {
                val socket = ServerSocket(0, 50, java.net.InetAddress.getByName("127.0.0.1"))
                serverSocket = socket
                port = socket.localPort
                System.err.println("[INFO] MangaImageProxy started on port $port")
                while (!socket.isClosed) {
                    val client = socket.accept()
                    thread(isDaemon = true) {
                        handleClient(client)
                    }
                }
            } catch (e: Exception) {
                System.err.println("[ERROR] MangaImageProxy server error: ${e.message}")
            }
        }
    }

    fun stop() {
        try {
            serverSocket?.close()
        } catch (e: Exception) {}
        serverSocket = null
        port = 0
    }

    private fun handleClient(client: Socket) {
        try {
            val reader = client.getInputStream().bufferedReader()
            val firstLine = reader.readLine() ?: return
            if (!firstLine.startsWith("GET ")) {
                sendError(client.getOutputStream(), 400, "Bad Request")
                return
            }

            val path = firstLine.substringAfter("GET ").substringBefore(" HTTP/")
            if (!path.startsWith("/image?")) {
                sendError(client.getOutputStream(), 404, "Not Found")
                return
            }

            val query = path.substringAfter("/image?")
            val params = parseQuery(query)

            val sourceId = params["sourceId"] ?: return sendError(client.getOutputStream(), 400, "Missing sourceId")
            val imageUrl = params["imageUrl"]?.let { URLDecoder.decode(it, "UTF-8") } ?: return sendError(client.getOutputStream(), 400, "Missing imageUrl")
            val pageUrl = params["pageUrl"]?.let { URLDecoder.decode(it, "UTF-8") } ?: ""
            val pageNumber = params["pageNumber"]?.toIntOrNull() ?: 0

            val responseData = fetchImage(sourceId, imageUrl, pageUrl, pageNumber)
            if (responseData == null) {
                sendError(client.getOutputStream(), 500, "Failed to fetch image")
                return
            }

            val out = client.getOutputStream()
            out.write("HTTP/1.1 200 OK\r\n".toByteArray())
            out.write("Content-Type: ${responseData.contentType}\r\n".toByteArray())
            out.write("Content-Length: ${responseData.bytes.size}\r\n".toByteArray())
            out.write("Access-Control-Allow-Origin: *\r\n".toByteArray())
            out.write("\r\n".toByteArray())
            out.write(responseData.bytes)
            out.flush()
        } catch (e: Exception) {
            e.printStackTrace()
            try {
                sendError(client.getOutputStream(), 500, "Internal Error: ${e.message}")
            } catch (e: Exception) {}
        } finally {
            try { client.close() } catch (e: Exception) {}
        }
    }

    private fun sendError(out: OutputStream, code: Int, message: String) {
        try {
            out.write("HTTP/1.1 $code $message\r\n".toByteArray())
            out.write("Content-Type: text/plain\r\n".toByteArray())
            out.write("Access-Control-Allow-Origin: *\r\n".toByteArray())
            out.write("\r\n".toByteArray())
            out.write(message.toByteArray())
            out.flush()
        } catch (e: Exception) {}
    }

    private fun parseQuery(query: String): Map<String, String> {
        val result = mutableMapOf<String, String>()
        val pairs = query.split("&")
        for (pair in pairs) {
            val idx = pair.indexOf("=")
            if (idx > 0) {
                val key = pair.substring(0, idx)
                val value = pair.substring(idx + 1)
                result[key] = value
            }
        }
        return result
    }

    private fun fetchImage(
        sourceId: String,
        imageUrl: String,
        pageUrl: String,
        pageNumber: Int
    ): ResponseData? {
        val context = com.lagradost.cloudstream3.CloudStreamApp.context ?: return null
        val manager = uy.kohesive.injekt.Injekt.get<com.anymex.runtimehost.aniyomi.AniyomiExtensionManager>()
        
        val src = manager.installedMangaExtensions
            .asSequence()
            .flatMap { it.sources.asSequence() }
            .firstOrNull { it.id.toString() == sourceId } as? HttpSource ?: return null

        val page = Page(
            index = pageNumber,
            url = pageUrl,
            imageUrl = imageUrl
        )

        return runBlocking {
            try {
                if (page.imageUrl.isNullOrEmpty()) {
                    page.imageUrl = src.getImageUrl(page)
                }
                val response = src.getImage(page)
                if (response.isSuccessful) {
                    val bytes = response.body.bytes()
                    val contentType = response.body.contentType()?.toString() ?: "image/jpeg"
                    ResponseData(bytes, contentType)
                } else null
            } catch (e: Exception) {
                System.err.println("[ERROR] fetchImage failed in proxy: ${e.message}")
                e.printStackTrace()
                null
            }
        }
    }

    class ResponseData(val bytes: ByteArray, val contentType: String)
}
