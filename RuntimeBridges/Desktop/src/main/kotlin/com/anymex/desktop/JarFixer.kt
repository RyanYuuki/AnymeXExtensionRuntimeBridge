package com.anymex.desktop

import org.objectweb.asm.ClassReader
import org.objectweb.asm.ClassWriter
import org.objectweb.asm.Opcodes
import org.objectweb.asm.Type
import org.objectweb.asm.tree.ClassNode
import org.objectweb.asm.tree.FieldInsnNode
import org.objectweb.asm.tree.FrameNode
import org.objectweb.asm.tree.InsnList
import org.objectweb.asm.tree.InsnNode
import org.objectweb.asm.tree.LabelNode
import org.objectweb.asm.tree.LdcInsnNode
import org.objectweb.asm.tree.LineNumberNode
import org.objectweb.asm.tree.MethodInsnNode
import org.objectweb.asm.tree.MethodNode
import org.objectweb.asm.tree.TypeInsnNode
import org.objectweb.asm.tree.VarInsnNode
import java.io.File
import java.io.FileOutputStream
import java.util.jar.JarEntry
import java.util.jar.JarFile
import java.util.jar.JarOutputStream

object JarFixer {

    private const val FIX_MARKER = "META-INF/anymex-jarfixed-v3"

    fun isFixed(jar: File): Boolean = try {
        JarFile(jar).use { jf -> 
            jf.getJarEntry(FIX_MARKER) != null
        }
    } catch (e: Exception) {
        false
    }

    fun fixStackmapFrames(jar: File) {
        val appLoader = Thread.currentThread().contextClassLoader ?: javaClass.classLoader

        @Suppress("UNUSED_VARIABLE")
        val loader = java.net.URLClassLoader(arrayOf(jar.toURI().toURL()), appLoader)
        try {
            val classes = LinkedHashMap<String, ClassNode>()
            val originalBytes = HashMap<String, ByteArray>()
            val others = mutableListOf<Pair<String, ByteArray>>()
            val needInit = mutableSetOf<Pair<String, String>>()
            JarFile(jar).use { jf ->
                val e = jf.entries()
                while (e.hasMoreElements()) {
                    val entry = e.nextElement()
                    if (entry.isDirectory) continue
                    val data = jf.getInputStream(entry).readBytes()
                    if (entry.name.endsWith(".class")) {
                        try {
                            val cn = ClassNode()
                            ClassReader(data).accept(cn, 0)
                            classes[entry.name] = cn
                            originalBytes[entry.name] = data
                        } catch (_: Throwable) {
                            others.add(entry.name to data)
                        }
                    } else {
                        others.add(entry.name to data)
                    }
                }
            }

            val plainBefore = HashMap<String, ByteArray?>()
            classes.forEach { (name, cn) ->
                try {
                    plainBefore[name] = ClassWriter(0).apply { cn.accept(this) }.toByteArray()
                } catch (_: Throwable) {
                    plainBefore[name] = null
                }
            }

            classes.values.forEach { cn ->
                fixWrongInitOwner(cn, needInit, classes)
            }
            fixBogusInterceptors(classes)

            var changed = true
            while (changed) {
                changed = false
                needInit.toList().forEach { (internal, desc) ->
                    val cn = classes[internal + ".class"] ?: return@forEach
                    if (cn.access and Opcodes.ACC_INTERFACE != 0) return@forEach
                    val has = cn.methods.any { it.name == "<init>" && it.desc == desc }
                    if (!has) {
                        val m = MethodNode(Opcodes.ACC_PUBLIC, "<init>", desc, null, null)
                        m.instructions.add(VarInsnNode(Opcodes.ALOAD, 0))
                        var slot = 1
                        for (t in Type.getArgumentTypes(desc)) {
                            when (t.sort) {
                                Type.LONG -> { m.instructions.add(VarInsnNode(Opcodes.LLOAD, slot)); slot += 2 }
                                Type.DOUBLE -> { m.instructions.add(VarInsnNode(Opcodes.DLOAD, slot)); slot += 2 }
                                Type.FLOAT -> { m.instructions.add(VarInsnNode(Opcodes.FLOAD, slot)); slot++ }
                                Type.INT, Type.SHORT, Type.BYTE, Type.CHAR, Type.BOOLEAN -> { m.instructions.add(VarInsnNode(Opcodes.ILOAD, slot)); slot++ }
                                else -> { m.instructions.add(VarInsnNode(Opcodes.ALOAD, slot)); slot++ }
                            }
                        }
                        m.instructions.add(MethodInsnNode(Opcodes.INVOKESPECIAL, cn.superName ?: "java/lang/Object", "<init>", desc, false))
                        m.instructions.add(InsnNode(Opcodes.RETURN))
                        m.maxStack = maxOf(1, slot)
                        m.maxLocals = slot
                        cn.methods.add(m)
                        if (classes.containsKey(cn.superName + ".class")) {
                            needInit.add(cn.superName to desc)
                        }
                        changed = true
                    }
                }
            }

            val dirty = HashSet<String>()
            classes.forEach { (name, cn) ->
                val before = plainBefore[name]
                if (before != null) {
                    val after = try {
                        ClassWriter(0).apply { cn.accept(this) }.toByteArray()
                    } catch (_: Throwable) {
                        null
                    }
                    if (after == null || !before.contentEquals(after)) {
                        dirty.add(name)
                    }
                }
            }

            val tmp = File(jar.parentFile, jar.name + ".tmp")
            try {
                JarOutputStream(FileOutputStream(tmp)).use { jos ->
                    jos.putNextEntry(JarEntry(FIX_MARKER))
                    jos.write("fixed\n".toByteArray())
                    jos.closeEntry()
                    classes.forEach { (name, cn) ->
                        val bytes = if (!dirty.contains(name)) {
                            originalBytes[name]
                        } else {
                            ClassWriter(0).apply { cn.accept(this) }.toByteArray()
                        }
                        if (bytes != null) {
                            jos.putNextEntry(JarEntry(name))
                            jos.write(bytes)
                            jos.closeEntry()
                        }
                    }
                    others.forEach { (name, data) ->
                        jos.putNextEntry(JarEntry(name))
                        jos.write(data)
                        jos.closeEntry()
                    }
                }
                try {
                    java.nio.file.Files.move(
                        tmp.toPath(), jar.toPath(),
                        java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                        java.nio.file.StandardCopyOption.ATOMIC_MOVE,
                    )
                } catch (_: Exception) {
                    java.nio.file.Files.move(
                        tmp.toPath(), jar.toPath(),
                        java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                    )
                }
            } catch (e: Exception) {
                tmp.delete()
                throw e
            }
        } catch (e: Exception) {
            System.err.println("fixStackmapFrames error in $jar: $e")
        }
    }

    private fun fixWrongInitOwner(cn: ClassNode, needInit: MutableSet<Pair<String, String>>, classes: Map<String, ClassNode>) {
        cn.methods.forEach { m ->
            val insns = m.instructions
            val pending = java.util.ArrayDeque<TypeInsnNode>()
            var pendingDup: TypeInsnNode? = null
            var lastNew: TypeInsnNode? = null
            val localNew = HashMap<Int, String>()
            var lastLoadedLocalType: String? = null
            var i = 0
            while (i < insns.size()) {
                val n = insns[i]
                when {
                    n is LabelNode || n is LineNumberNode || n is FrameNode -> {}
                    n is TypeInsnNode && n.opcode == Opcodes.NEW -> {
                        pendingDup = n
                        lastNew = n
                        lastLoadedLocalType = null
                    }
                    n is InsnNode && n.opcode == Opcodes.DUP && pendingDup != null -> {
                        pending.push(pendingDup)
                        pendingDup = null
                        lastLoadedLocalType = null
                    }
                    n is VarInsnNode && n.opcode == Opcodes.ASTORE -> {
                        pendingDup = null
                        if (lastNew != null) {
                            localNew[n.`var`] = lastNew.desc
                            lastNew = null
                        }
                        lastLoadedLocalType = null
                    }
                    n is VarInsnNode && n.opcode == Opcodes.ALOAD -> {
                        pendingDup = null
                        lastNew = null
                        lastLoadedLocalType = localNew[n.`var`]
                    }
                    n is MethodInsnNode && n.opcode == Opcodes.INVOKESPECIAL && n.name == "<init>" -> {
                        pendingDup = null
                        lastNew = null
                        if (!pending.isEmpty()) {
                            val newInsn = pending.pop()
                            val t = newInsn.desc
                            if (n.owner != t && classes.containsKey(t + ".class")) {
                                n.owner = t
                                needInit.add(t to n.desc)
                            }
                        } else if (lastLoadedLocalType != null && n.owner != lastLoadedLocalType) {
                            if (n.owner == "javax/crypto/spec/SecretKeySpec" || classes.containsKey(lastLoadedLocalType + ".class")) {
                                n.owner = lastLoadedLocalType
                                if (classes.containsKey(lastLoadedLocalType + ".class")) {
                                    needInit.add(lastLoadedLocalType to n.desc)
                                }
                            }
                        } else if (n.owner == "javax/crypto/spec/SecretKeySpec" && n.desc == "()V") {
                            n.owner = "java/lang/StringBuilder"
                        }
                        lastLoadedLocalType = null
                    }
                    else -> {
                        pendingDup = null
                        lastNew = null
                        lastLoadedLocalType = null
                    }
                }
                i++
            }
        }
    }

    private fun fixBogusInterceptors(classes: Map<String, ClassNode>) {
        val instantiated = HashSet<String>()
        classes.values.forEach { cn ->
            cn.methods.forEach { mn ->
                val insns = mn.instructions
                for (idx in 0 until insns.size()) {
                    val insn = insns[idx]
                    if (insn is TypeInsnNode && insn.opcode == Opcodes.NEW) {
                        instantiated.add(insn.desc)
                    }
                }
            }
        }

        val uninstantiatedInterceptors = ArrayDeque<String>()
        classes.values.forEach { cn ->
            if ((cn.access and Opcodes.ACC_INTERFACE) == 0 && (cn.access and Opcodes.ACC_ABSTRACT) == 0) {
                if (cn.interfaces != null && cn.interfaces.contains("okhttp3/Interceptor")) {
                    val hasInit = cn.methods.any { it.name == "<init>" }
                    if (!hasInit) {
                        val m = MethodNode(Opcodes.ACC_PUBLIC, "<init>", "()V", null, null)
                        m.maxStack = 1
                        m.maxLocals = 1
                        m.instructions.add(VarInsnNode(Opcodes.ALOAD, 0))
                        m.instructions.add(MethodInsnNode(Opcodes.INVOKESPECIAL, cn.superName ?: "java/lang/Object", "<init>", "()V", false))
                        m.instructions.add(InsnNode(Opcodes.RETURN))
                        cn.methods.add(m)
                    }
                    if (!instantiated.contains(cn.name)) {
                        uninstantiatedInterceptors.add(cn.name)
                    }
                }
            }
        }

        classes.values.forEach { cn ->
            cn.methods.forEach { mn ->
                val insns = mn.instructions
                var i = 0
                while (i < insns.size()) {
                    val insn = insns[i]
                    if (insn is MethodInsnNode &&
                        (insn.owner == "okhttp3/OkHttpClient\$Builder" || insn.owner == "okhttp3/OkHttpClient") &&
                        (insn.name == "addInterceptor" || insn.name == "addNetworkInterceptor")
                    ) {
                        var prev = insn.previous
                        while (prev is LabelNode || prev is LineNumberNode || prev is FrameNode) {
                            prev = prev?.previous
                        }
                        if (prev is MethodInsnNode && prev.owner == "java/lang/Object" && prev.name == "<init>") {
                            var dup = prev.previous
                            while (dup is LabelNode || dup is LineNumberNode || dup is FrameNode) {
                                dup = dup?.previous
                            }
                            if (dup != null && dup.opcode == Opcodes.DUP) {
                                var newInsn = dup.previous
                                while (newInsn is LabelNode || newInsn is LineNumberNode || newInsn is FrameNode) {
                                    newInsn = newInsn?.previous
                                }
                                if (newInsn is TypeInsnNode && newInsn.opcode == Opcodes.NEW && newInsn.desc == "java/lang/Object") {
                                    val target = if (uninstantiatedInterceptors.isNotEmpty()) uninstantiatedInterceptors.removeFirst() else null
                                    if (target != null) {
                                        newInsn.desc = target
                                        prev.owner = target
                                    } else {
                                        var builderLoad = newInsn.previous
                                        while (builderLoad is LabelNode || builderLoad is LineNumberNode || builderLoad is FrameNode) {
                                            builderLoad = builderLoad?.previous
                                        }
                                        var next = insn.next
                                        while (next is LabelNode || next is LineNumberNode || next is FrameNode) {
                                            next = next?.next
                                        }
                                        if (next != null && next.opcode == Opcodes.POP && builderLoad != null) {
                                            insns.remove(builderLoad)
                                            insns.remove(newInsn)
                                            insns.remove(dup)
                                            insns.remove(prev)
                                            insns.remove(insn)
                                            insns.remove(next)
                                            i = 0
                                            continue
                                        } else {
                                            insns.remove(newInsn)
                                            insns.remove(dup)
                                            insns.remove(prev)
                                            insns.remove(insn)
                                            i = 0
                                            continue
                                        }
                                    }
                                }
                            }
                        }
                    }
                    i++
                }
            }
        }
    }
}
