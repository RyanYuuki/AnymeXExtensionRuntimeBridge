package android.graphics

import java.io.InputStream

object BitmapFactory {

    @JvmStatic
    fun decodeStream(inputStream: InputStream?): Bitmap? = null

    @JvmStatic
    fun decodeStream(inputStream: InputStream?, outPadding: Rect?, opts: Options?): Bitmap? = null

    @JvmStatic
    fun decodeFile(pathName: String?): Bitmap? = null

    @JvmStatic
    fun decodeFile(pathName: String?, opts: Options?): Bitmap? = null

    @JvmStatic
    fun decodeByteArray(data: ByteArray?, offset: Int, length: Int): Bitmap? = null

    @JvmStatic
    fun decodeByteArray(data: ByteArray?, offset: Int, length: Int, opts: Options?): Bitmap? = null

    class Options {
        var inPreferredConfig: Bitmap.Config? = null
        var inSampleSize: Int = 1
        var inJustDecodeBounds: Boolean = false
        var outWidth: Int = 0
        var outHeight: Int = 0
        var inScaled: Boolean = false
    }
}

class Rect(
    var left: Int = 0,
    var top: Int = 0,
    var right: Int = 0,
    var bottom: Int = 0,
) {
    fun width(): Int = right - left
    fun height(): Int = bottom - top
    fun isEmpty(): Boolean = left >= right || top >= bottom
}
