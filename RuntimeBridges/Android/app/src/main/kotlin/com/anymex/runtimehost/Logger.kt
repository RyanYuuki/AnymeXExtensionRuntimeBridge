package com.anymex.runtimehost

import android.util.Log

object Logger {
    fun log(message: String, level: LogLevel = LogLevel.INFO) {
        when (level) {
            LogLevel.ERROR -> Log.e("AnymeXRuntime", message)
            LogLevel.WARNING -> Log.w("AnymeXRuntime", message)
            LogLevel.INFO -> Log.i("AnymeXRuntime", message)
            LogLevel.DEBUG -> Log.d("AnymeXRuntime", message)
        }
    }
}

enum class LogLevel {
    ERROR, WARNING, INFO, DEBUG
}