package com.aayush262.dartotsu_extension_bridge

object Main {
    @JvmStatic
    fun handle(requestJson: String): String =
        com.anymex.desktop.DesktopExtensionLoader.handleRequest(requestJson)
}
