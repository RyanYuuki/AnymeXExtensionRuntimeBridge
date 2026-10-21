package com.anymex.desktop.util
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/**
 * Bounded-parallel APK -> JAR conversion + load for the desktop extension
 * loaders.
 *
 * A cold install re-`dex2jar`s + `BytecodeEditor`s every extension, ~1-2s
 * each, so 15-20 extensions is a ~20-30s first launch when done one at a time.
 * `dex2jar` + ASM is CPU+IO bound, so a few at once is the sweet spot; more
 * just thrashes. The per-jar writes are already atomic (`PackageTools.dex2jar`
 * / `BytecodeEditor` swap in via `Files.move`) and each extension writes a
 * distinct path, so distinct APKs convert safely in parallel. The loaders stay
 * `@Synchronized`, so this only ever runs one batch at a time.
 */
object ExtensionConvert {
    private val parallelism =
        Runtime.getRuntime().availableProcessors().coerceIn(2, 4)

    /**
     * Runs [load] over [items] up to [parallelism] at a time, in the caller's
     * thread (via `runBlocking`). Per-item failures are logged with
     * `"Failed to load <name>"` and dropped; the returned list only has the
     * successes (order not guaranteed).
     */
    fun <T, R : Any> parallel(
        items: List<T>,
        nameOf: (T) -> String,
        load: (T) -> R,
    ): List<R> {
        if (items.isEmpty()) return emptyList()

        val one: (T) -> R? = { item ->
            try {
                load(item)
            } catch (e: Throwable) {
                Logger.log(
                    "Failed to load ${nameOf(item)}: ${e.message}\n${e.stackTraceToString()}",
                    LogLevel.ERROR,
                )
                null
            }
        }

        if (items.size == 1) return listOfNotNull(one(items[0]))

        val gate = Semaphore(parallelism)
        return runBlocking {
            items
                .map { item -> async(Dispatchers.IO) { gate.withPermit { one(item) } } }
                .awaitAll()
                .filterNotNull()
        }
    }
}
