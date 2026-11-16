package androidx.fragment.app

open class FragmentManager {
    open fun beginTransaction(): Any? = null
    open fun executePendingTransactions(): Boolean = false
    open fun findFragmentById(id: Int): Fragment? = null
    open fun findFragmentByTag(tag: String?): Fragment? = null
    open fun getFragments(): List<Fragment> = emptyList()
    open fun getBackStackEntryCount(): Int = 0
    open fun popBackStack() {}
    open fun popBackStackImmediate(): Boolean = false
    open fun isDestroyed(): Boolean = false
    open fun isStateSaved(): Boolean = false
}
