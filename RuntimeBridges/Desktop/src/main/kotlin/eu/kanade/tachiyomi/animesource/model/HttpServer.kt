package eu.kanade.tachiyomi.animesource.model

import fi.iki.elonen.NanoHTTPD

open class HttpServer : NanoHTTPD(0) {
    val url: String
        get() = "http://localhost:$listeningPort"

    fun isRunning(): Boolean {
        return isRunning
    }

    @Volatile
    private var isRunning = false

    override fun start() {
        try {
            super.start()
            isRunning = true
        } catch (e: Exception) {
            System.err.println("Failed to start http server: ${e.message}")
        }
    }

    override fun stop() {
        super.stop()
        isRunning = false
    }
}
