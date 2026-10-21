package com.anymex.desktop.util

object Logger {
    @JvmStatic
    fun log(message: String, level: LogLevel = LogLevel.INFO): Int {
        System.err.println("[${level.name}] $message")
        return 1
    }

    @JvmStatic
    fun log(message: String, throwable: Throwable, level: LogLevel = LogLevel.ERROR) {
        System.err.println("[${level.name}] $message\n${throwable.stackTraceToString()}")
    }
}

enum class LogLevel {
    ERROR, WARNING, INFO, DEBUG
}
