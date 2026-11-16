package androidx.fragment.app

import android.app.Activity

open class FragmentActivity : Activity() {
    open val supportFragmentManager: FragmentManager = FragmentManager()
    override fun isFinishing(): Boolean = false
    override fun isDestroyed(): Boolean = false
}
