# Keep plugin classes and members
-keep class com.ryan.runtimebridge.** { *; }

# Kotlinx Serialization
-if @kotlinx.serialization.Serializable class **
-keepclassmembers class <1> {
    static <1>$Companion Companion;
}

-if @kotlinx.serialization.Serializable class ** {
    static **$* *;
}
-keepclassmembers class <2>$<3> {
    kotlinx.serialization.KSerializer serializer(...);
}

-if @kotlinx.serialization.Serializable class ** {
    public static ** INSTANCE;
}
-keepclassmembers class <1> {
    public static <1> INSTANCE;
    kotlinx.serialization.KSerializer serializer(...);
}

-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses, RuntimeVisibleAnnotations, AnnotationDefault

-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
    @com.fasterxml.jackson.annotation.JsonProperty <fields>;
}

-keep class androidx.appcompat.** { *; }
-keep class com.google.android.material.** { *; }
-keep class androidx.lifecycle.** { *; }
-keep class androidx.preference.** { *; }
-keep class androidx.fragment.** { *; }
-keep class androidx.core.** { *; }

-keep,allowoptimization class kotlin.** { public protected *; }
-keep,allowoptimization class kotlinx.coroutines.** { public protected *; }
-keep,allowoptimization class kotlinx.serialization.** { public protected *; }

-keep,allowoptimization class uy.kohesive.injekt.** { public protected *; }
-keepclassmembers class uy.kohesive.injekt.api.FullTypeReference {
    <init>(...);
}

-keep class com.lagradost.** { *; }
-keep class com.ryan.** { *; }
-keep,allowoptimization class eu.kanade.tachiyomi.** { *; }

-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase
-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

-keep class retrofit2.** { *; }
-keepclasseswithmembers class * {
    @retrofit2.http.* <methods>;
}

-keep class com.fasterxml.jackson.** { *; }
-keepnames class com.fasterxml.jackson.databind.** { *; }
-dontwarn com.fasterxml.jackson.databind.**

-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

-keep class org.mozilla.** { *; }
-keep class app.cash.quickjs.** { *; }
-keep class org.schabi.newpipe.** { *; }
-keep class com.github.TeamNewPipe.** { *; }

-keep class org.jsoup.** { *; }
-keepclassmembers class org.jsoup.nodes.Document { *; }

-keep class me.xdrop.fuzzywuzzy.** { *; }
