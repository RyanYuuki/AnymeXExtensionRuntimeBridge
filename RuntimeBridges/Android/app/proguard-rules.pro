# Keep the RuntimeBridge entry point — this is what DexClassLoader reflects into
-keep class com.anymex.runtimehost.RuntimeBridge { *; }
-keepclassmembers class com.anymex.runtimehost.RuntimeBridge {
    public static final com.anymex.runtimehost.RuntimeBridge INSTANCE;
    public *;
}

# CloudStream & Lagradost
-keep class com.lagradost.cloudstream3.** { *; }
-keep interface com.lagradost.cloudstream3.** { *; }
-keepclassmembers class com.lagradost.cloudstream3.** { *; }

# Aniyomi / Tachiyomi framework
-keep class eu.kanade.tachiyomi.** { *; }
-keep interface eu.kanade.tachiyomi.** { *; }

# Injekt
-keep class uy.kohesive.injekt.** { *; }

# Kotlin serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keep,includedescriptorclasses class com.anymex.runtimehost.**$$serializer { *; }
-keepclassmembers class com.anymex.runtimehost.** {
    *** Companion;
}
-keepclasseswithmembers class com.anymex.runtimehost.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# Retrofit
-keep class retrofit2.** { *; }
-keepattributes Signature
-keepattributes Exceptions

# Jackson
-keep class com.fasterxml.jackson.** { *; }
-keepclassmembers class * {
    @com.fasterxml.jackson.annotation.* *;
}
-dontwarn com.fasterxml.jackson.**

# Gson
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# RxJava
-keep class rx.** { *; }
-keep class io.reactivex.** { *; }
-dontwarn rx.**

# QuickJS
-keep class app.cash.quickjs.** { *; }

# Rhino / JS engine
-keep class org.mozilla.** { *; }
-dontwarn org.mozilla.**

# NewPipe extractor
-keep class org.schabi.newpipe.** { *; }

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# AndroidX preferences (used by Aniyomi extensions)
-keep class androidx.preference.** { *; }
-keep interface androidx.preference.** { *; }

# Suppress warnings for missing classes we don't use
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
