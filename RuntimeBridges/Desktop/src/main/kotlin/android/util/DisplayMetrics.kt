package android.util

class DisplayMetrics {
    var widthPixels: Int = 1080
    var heightPixels: Int = 1920
    var density: Float = 2.75f
    var densityDpi: Int = 440
    var scaledDensity: Float = 2.75f
    var xdpi: Float = 440f
    var ydpi: Float = 440f

    fun setTo(o: DisplayMetrics) {
        widthPixels = o.widthPixels
        heightPixels = o.heightPixels
        density = o.density
        densityDpi = o.densityDpi
        scaledDensity = o.scaledDensity
        xdpi = o.xdpi
        ydpi = o.ydpi
    }

    companion object {
        const val DENSITY_LOW = 120
        const val DENSITY_MEDIUM = 160
        const val DENSITY_HIGH = 240
        const val DENSITY_XHIGH = 320
        const val DENSITY_XXHIGH = 480
        const val DENSITY_XXXHIGH = 640
        const val DENSITY_DEFAULT = DENSITY_MEDIUM
    }
}
