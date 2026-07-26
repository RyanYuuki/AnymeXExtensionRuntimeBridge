package eu.kanade.tachiyomi

@Suppress("UNUSED")
object AppInfo {
    fun getVersionCode(): Int = 81 
    fun getVersionName(): String = "1.5.0"
    fun getSupportedImageMimeTypes(): List<String> = listOf(
        "image/jpeg",
        "image/png",
        "image/gif",
        "image/webp",
        "image/heic",
        "image/heif"
    )
}
