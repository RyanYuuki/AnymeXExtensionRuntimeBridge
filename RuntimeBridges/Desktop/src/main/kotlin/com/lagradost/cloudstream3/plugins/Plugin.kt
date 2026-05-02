package com.lagradost.cloudstream3.plugins

import kotlin.Throws

abstract class Plugin : BasePlugin() {
    /**
     * Called when your Plugin is loaded
     */
    @Throws(Throwable::class)
    open fun load(context: Any? = null) {
        // If not overridden by an extension then try the cross-platform load()
        load()
    }
}
