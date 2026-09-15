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

    private const val FIX_MARKER = "META-INF/anymex-jarfixed"

    fun isFixed(jar: File): Boolean = try {
        JarFile(jar).use { jf -> 
            jf.getJarEntry(FIX_MARKER) != null || jf.getJarEntry("META-INF/miwayomi-jarfixed") != null 
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
                        m.instructions.add(MethodInsnNode(Opcodes.INVOKESPECIAL, cn.superName, "<init>", desc, false))
                        m.instructions.add(InsnNode(Opcodes.RETURN))
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
            var i = 0
            while (i < insns.size()) {
                val n = insns[i]
                when {
                    n is TypeInsnNode && n.opcode == Opcodes.NEW -> pendingDup = n
                    n is InsnNode && n.opcode == Opcodes.DUP && pendingDup != null -> {
                        pending.push(pendingDup)
                        pendingDup = null
                    }
                    n is MethodInsnNode && n.opcode == Opcodes.INVOKESPECIAL && n.name == "<init>" -> {
                        if (!pending.isEmpty()) {
                            val newInsn = pending.pop()
                            val t = newInsn.desc
                            if (n.owner != t) {
                                n.owner = t
                                needInit.add(t to n.desc)
                            }
                        }
                    }
                    else -> {}
                }
                i++
            }
        }
    }
}
