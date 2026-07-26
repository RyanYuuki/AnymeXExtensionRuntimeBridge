plugins {
    kotlin("jvm")
    kotlin("plugin.serialization")
    `maven-publish`
}

group = "org.draken"
version = "1.0.3"

java {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
    sourceSets {
        main {
            java {
                exclude("androidx/**")
            }
        }
    }
}

kotlin {
    sourceSets {
        val main by getting {
            kotlin.exclude("eu/kanade/**")
            kotlin.exclude("keiyoushi/**")
            kotlin.exclude("rx/**")
            kotlin.exclude("uy/kohesive/injekt/**")
        }
    }
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        freeCompilerArgs.addAll(
            "-opt-in=kotlin.RequiresOptIn",
            "-opt-in=kotlin.contracts.ExperimentalContracts",
            "-opt-in=kotlinx.coroutines.ExperimentalCoroutinesApi",
            "-opt-in=org.koitharu.kotatsu.parsers.InternalParsersApi"
        )
    }
}

publishing {
    publications {
        create<MavenPublication>("maven") {
            from(components["java"])
        }
    }
}

tasks.jar {
    exclude("android/**")
    exclude("androidx/annotation/**")
    exclude("androidx/preference/**")
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        freeCompilerArgs.addAll(
            "-Xannotation-default-target=param-property",
            "-opt-in=kotlin.RequiresOptIn",
            "-opt-in=kotlin.contracts.ExperimentalContracts",
            "-opt-in=kotlinx.coroutines.ExperimentalCoroutinesApi",
            "-opt-in=org.koitharu.kotatsu.parsers.InternalParsersApi",
        )
    }
}

dependencies {
    compileOnly(libs.androidx.collection.ktx) {
        exclude(group = "androidx.annotation")
    }
    compileOnly(libs.androidx.annotation)

    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)

    api(libs.jsoup)
    implementation(libs.json)

    implementation(libs.bundles.okhttp)
    implementation(libs.okio)
}

configurations.matching { it.name.contains("runtime", ignoreCase = true) }.all {
    exclude(group = "androidx.annotation")
}