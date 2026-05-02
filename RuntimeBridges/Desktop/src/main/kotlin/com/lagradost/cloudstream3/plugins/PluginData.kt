package com.lagradost.cloudstream3.plugins

import java.io.File

data class PluginData(
    val pluginClass: Any?,
    val jarFile: File,
    val classLoader: ClassLoader,
    val manifest: BasePlugin.Manifest
)
