package com.anymex.desktop

import java.net.URL
import java.net.URLClassLoader

class ChildFirstURLClassLoader(
    urls: Array<URL>,
    parent: ClassLoader
) : URLClassLoader(urls, parent) {

    private val systemClassLoader: ClassLoader? = getSystemClassLoader()

    private fun shouldDelegateToParent(name: String?): Boolean {
        if (name == null) return false
        return name.startsWith("kotlin.") ||
               name.startsWith("kotlinx.") ||
               name.startsWith("okhttp3.") ||
               name.startsWith("okio.") ||
               name.startsWith("androidx.") ||
               name.startsWith("android.") ||
               name.startsWith("com.anymex.") ||
               name.startsWith("eu.kanade.tachiyomi.network.") ||
               name.startsWith("eu.kanade.tachiyomi.PreferenceScreen")
    }

    override fun loadClass(name: String?, resolve: Boolean): Class<*> {
        var c = findLoadedClass(name)

        if (c == null && systemClassLoader != null) {
            try {
                c = systemClassLoader.loadClass(name)
            } catch (_: ClassNotFoundException) {}
        }

        if (c == null && shouldDelegateToParent(name)) {
            try {
                c = parent.loadClass(name)
            } catch (_: ClassNotFoundException) {}
        }

        if (c == null && name != null && !shouldDelegateToParent(name)) {
            try {
                c = findClass(name)
            } catch (_: ClassNotFoundException) {
                c = parent.loadClass(name)
            }
        }

        val result = c ?: throw ClassNotFoundException(name)

        if (resolve) {
            resolveClass(result)
        }

        return result
    }

    override fun findClass(name: String): Class<*> {
        val resourceName = name.replace('.', '/') + ".class"
        val url = findResource(resourceName)
        if (url != null) {
            val rawBytes = try { url.openStream().use { it.readBytes() } } catch (_: Throwable) { null }
            if (rawBytes != null) {
                try {
                    val fixedBytes = fixStackMapFrames(name, rawBytes)
                    return defineClass(name, fixedBytes, 0, fixedBytes.size)
                } catch (e: Throwable) {
                    System.err.println("  [CLASS DEFINE FAIL] $name: ${e.javaClass.simpleName}: ${e.message}")
                    e.printStackTrace(System.err)
                }
            }
        }
        return super.findClass(name)
    }

    private fun fixStackMapFrames(className: String, bytes: ByteArray): ByteArray {
        return try {
            val reader = org.objectweb.asm.ClassReader(bytes)
            val classNode = org.objectweb.asm.tree.ClassNode()
            reader.accept(classNode, 0)

            val classInternalName = className.replace('.', '/')
            val currentSuperName = classNode.superName

            val isInterface = (classNode.access and org.objectweb.asm.Opcodes.ACC_INTERFACE) != 0
            val hasConstructor = classNode.methods.any { it.name == "<init>" }
            if (!isInterface && !hasConstructor) {
                val constructor = org.objectweb.asm.tree.MethodNode(
                    org.objectweb.asm.Opcodes.ACC_PUBLIC,
                    "<init>",
                    "()V",
                    null,
                    null
                )
                val instructions = constructor.instructions
                instructions.add(org.objectweb.asm.tree.VarInsnNode(org.objectweb.asm.Opcodes.ALOAD, 0))
                instructions.add(org.objectweb.asm.tree.MethodInsnNode(
                    org.objectweb.asm.Opcodes.INVOKESPECIAL,
                    classNode.superName ?: "java/lang/Object",
                    "<init>",
                    "()V",
                    false
                ))
                instructions.add(org.objectweb.asm.tree.InsnNode(org.objectweb.asm.Opcodes.RETURN))
                constructor.maxStack = 1
                constructor.maxLocals = 1
                classNode.methods.add(constructor)
            }

            for (method in classNode.methods) {
                val instructions = method.instructions
                for (i in 0 until instructions.size()) {
                    val insn = instructions.get(i)
                    if (insn is org.objectweb.asm.tree.TypeInsnNode && insn.opcode == org.objectweb.asm.Opcodes.NEW) {
                        if (insn.desc == "kotlin/jvm/internal/Lambda") {
                            insn.desc = classInternalName
                        } else if (insn.desc == "java/lang/Enum" && currentSuperName == "java/lang/Enum") {
                            insn.desc = classInternalName
                        } else if (insn.desc == "java/lang/Object") {
                            var j = i + 1
                            while (j < instructions.size()) {
                                val nextInsn = instructions.get(j)
                                 if (nextInsn is org.objectweb.asm.tree.FieldInsnNode && 
                                    (nextInsn.opcode == org.objectweb.asm.Opcodes.PUTSTATIC || nextInsn.opcode == org.objectweb.asm.Opcodes.PUTFIELD)) {
                                    val fieldType = nextInsn.desc
                                    if (fieldType.startsWith("L") && fieldType != "Ljava/lang/Object;") {
                                        val targetClassInternalName = fieldType.substring(1, fieldType.length - 1)
                                         if (nextInsn.name == "Companion" || nextInsn.name == "INSTANCE" || targetClassInternalName == classInternalName) {
                                             insn.desc = targetClassInternalName
                                             
                                             var k = i + 1
                                             while (k < j) {
                                                 val initInsn = instructions.get(k)
                                                 if (initInsn is org.objectweb.asm.tree.MethodInsnNode && 
                                                     initInsn.opcode == org.objectweb.asm.Opcodes.INVOKESPECIAL && 
                                                     initInsn.owner == "java/lang/Object" && 
                                                     initInsn.name == "<init>") {
                                                     initInsn.owner = targetClassInternalName
                                                     break
                                                 }
                                                 k++
                                             }
                                         }
                                     }
                                     break
                                 }
                                if (nextInsn.opcode == org.objectweb.asm.Opcodes.NEW || 
                                    nextInsn is org.objectweb.asm.tree.JumpInsnNode || 
                                    nextInsn is org.objectweb.asm.tree.LabelNode) {
                                    break
                                }
                                j++
                            }
                        }
                    }
                }
            }

            val writer = org.objectweb.asm.ClassWriter(0)
            classNode.accept(writer)
            writer.toByteArray()
        } catch (e: Throwable) {
            bytes
        }
    }
}
