package com.anymex.desktop

data class ExtensionMeta(
    val pkgName: String,
    val versionName: String,
    val versionCode: Long,
    val isNsfw: Boolean,
    val isAnime: Boolean,
    val sourceClasses: List<String>,
    val factoryClass: String?,
    val name: String,
)
