package android.content.res

import android.util.DisplayMetrics

class Resources private constructor() {

    val displayMetrics: DisplayMetrics = DisplayMetrics()

    fun getString(id: Int): String = ""

    fun getString(id: Int, vararg formatArgs: Any?): String = ""

    fun getInteger(id: Int): Int = 0

    fun getBoolean(id: Int): Boolean = false

    fun getIdentifier(name: String, defType: String?, defPackage: String?): Int = 0

    fun getDrawable(id: Int): Any? = null

    fun getDimension(id: Int): Float = 0f

    companion object {
        @JvmStatic
        private val INSTANCE = Resources()

        @JvmStatic
        fun getSystem(): Resources = INSTANCE
    }
}
