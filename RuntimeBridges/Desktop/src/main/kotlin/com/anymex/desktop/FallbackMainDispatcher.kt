package com.anymex.desktop

import kotlinx.coroutines.*
import kotlinx.coroutines.internal.MainDispatcherFactory
import kotlin.coroutines.CoroutineContext

@OptIn(InternalCoroutinesApi::class)
class FallbackMainDispatcherFactory : MainDispatcherFactory {
    override val loadPriority: Int
        get() = Int.MAX_VALUE // Set high priority to override any other missing ones

    override fun createDispatcher(allFactories: List<MainDispatcherFactory>): MainCoroutineDispatcher {
        return FallbackMainDispatcher(Dispatchers.Default)
    }

    override fun hintOnError(): String? = null
}

@InternalCoroutinesApi
class FallbackMainDispatcher(private val delegate: CoroutineDispatcher) : MainCoroutineDispatcher() {
    override val immediate: MainCoroutineDispatcher
        get() = this

    override fun dispatch(context: CoroutineContext, block: Runnable) {
        delegate.dispatch(context, block)
    }

    override fun isDispatchNeeded(context: CoroutineContext): Boolean {
        return delegate.isDispatchNeeded(context)
    }
}
