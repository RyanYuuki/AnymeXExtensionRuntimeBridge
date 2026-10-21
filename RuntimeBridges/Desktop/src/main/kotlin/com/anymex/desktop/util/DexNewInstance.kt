package com.anymex.desktop.util
import com.googlecode.d2j.node.DexFileNode
import com.googlecode.d2j.node.insn.TypeStmtNode
import com.googlecode.d2j.reader.MultiDexFileReader
import com.googlecode.d2j.reader.Op
import java.nio.file.Files
import java.nio.file.Path

/**
 * BytecodeEditor's Pass C repairs NEW/INVOKESPECIAL construction sites using
 * only evidence available in the (already dex2jar-converted) jar. For
 * anonymous Function0/Function1/etc-implementing lambda classes, that
 * evidence can only ever narrow the required type down to the interface
 * itself (e.g. "this must be assignable to Function0") — never to the one
 * specific concrete implementer among several that dex2jar actually meant,
 * since all candidates satisfy the same usage constraints identically. That
 * information only exists in the original, uncorrupted DEX.
 *
 * This oracle reads the source DEX directly (via the same dex-reader library
 * dex2jar itself is built on, so no bespoke disassembler is needed) and
 * records, per method, the ordered sequence of NEW_INSTANCE target types as
 * they appear in the original bytecode. BytecodeEditor then walks the
 * jar-side NEW instructions for that same method in instruction order and
 * matches them positionally against this list.
 *
 * This is a positional heuristic, not a proof — dex2jar's topological sort
 * could in principle reorder blocks such that NEW_INSTANCE ordinal position
 * isn't preserved. This oracle only supplies the raw per-method type
 * sequence; the caller (BytecodeEditor) is responsible for checking that
 * the jar-side and dex-side NEW-instruction counts for a method actually
 * match before trusting any positional lookup into it, and must treat a
 * mismatch as "don't use this data for this method," not "best effort
 * anyway."
 */
object DexNewInstanceOracle {

    private fun stripDescriptor(typeDescriptor: String): String =
        typeDescriptor.removePrefix("L").removeSuffix(";")

    /**
     * Key format matches what BytecodeEditor already needs at the call site:
     * "<ownerInternalName>#<methodName>#<methodDesc>", e.g.
     * "eu/kanade/tachiyomi/extension/en/mangadistrict/ExtensionGenerated#<init>#()V"
     */
    fun load(dexFile: Path, jarLabel: String): Map<String, List<String>> {
        val result = LinkedHashMap<String, MutableList<String>>()
        try {
            val reader = MultiDexFileReader.open(Files.readAllBytes(dexFile))
            val fileNode = DexFileNode()
            reader.accept(fileNode)

            for (classNode in fileNode.clzs) {
                val methods = classNode.methods ?: continue
                for (methodNode in methods) {
                    val code = methodNode.codeNode ?: continue
                    val key = "${stripDescriptor(classNode.className)}#${methodNode.method.name}#${methodNode.method.desc}"
                    val ordered = result.getOrPut(key) { mutableListOf() }
                    for (stmt in code.stmts) {
                        if (stmt is TypeStmtNode && stmt.op == Op.NEW_INSTANCE) {
                            ordered += stripDescriptor(stmt.type)
                        }
                    }
                }
            }
        } catch (e: Throwable) {
            Logger.log(
                "[$jarLabel] Failed to load DEX oracle from $dexFile: ${e.javaClass.simpleName}: ${e.message} " +
                        "— proceeding without it, ambiguous constructions will be left unrepaired",
                LogLevel.ERROR,
            )
        }
        return result
    }
}