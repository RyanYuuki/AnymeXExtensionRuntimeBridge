package eu.kanade.tachiyomi.network

object RequestTag {
    val threadLocalId = ThreadLocal<String>()

    fun set(id: String?) {
        if (id == null) threadLocalId.remove()
        else threadLocalId.set(id)
    }

    fun get(): String? = threadLocalId.get()
}
