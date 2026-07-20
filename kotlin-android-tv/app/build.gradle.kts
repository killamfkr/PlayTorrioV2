plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.playtorrio.tv"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.playtorrio.tv"
        minSdk = 24
        targetSdk = 35
        versionCode = 3
        versionName = "1.0.1"
        vectorDrawables {
            useSupportLibrary = true
        }
        buildConfigField("String", "TMDB_API_KEY", "\"c3515fdc674ea2bd7b514f4bc3616a4a\"")
        buildConfigField(
            "String",
            "DEFAULT_STREMIO_ADDON",
            "\"https://dlstreams.top/manifest.json\"",
        )
    }

    signingConfigs {
        // Debug keystore when ANDROID_KEYSTORE_* secrets are unset (same approach as Flutter releases).
        create("release") {
            val storePath = System.getenv("ANDROID_KEYSTORE_PATH")
                ?: "${System.getProperty("user.home")}/.android/debug.keystore"
            storeFile = file(storePath)
            storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD") ?: "android"
            keyAlias = System.getenv("ANDROID_KEY_ALIAS") ?: "androiddebugkey"
            keyPassword = System.getenv("ANDROID_KEY_PASSWORD") ?: "android"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        jvmToolchain(17)
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    // Pin a BOM that matches the Compose Compiler bundled with Kotlin 2.0.21
    val composeBom = platform("androidx.compose:compose-bom:2024.10.01")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.navigation:navigation-compose:2.8.3")

    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    implementation("io.coil-kt:coil-compose:2.7.0")

    val media3 = "1.5.0"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-exoplayer-hls:$media3")
    implementation("androidx.media3:media3-ui:$media3")
    implementation("androidx.media3:media3-session:$media3")

    debugImplementation("androidx.compose.ui:ui-tooling")
}

configurations.all {
    resolutionStrategy {
        force(
            "androidx.compose.ui:ui:1.7.5",
            "androidx.compose.ui:ui-android:1.7.5",
            "androidx.compose.ui:ui-tooling:1.7.5",
            "androidx.compose.ui:ui-tooling-preview:1.7.5",
            "androidx.compose.foundation:foundation:1.7.5",
            "androidx.compose.foundation:foundation-android:1.7.5",
            "androidx.compose.foundation:foundation-layout:1.7.5",
            "androidx.compose.foundation:foundation-layout-android:1.7.5",
            "androidx.compose.runtime:runtime:1.7.5",
            "androidx.compose.runtime:runtime-android:1.7.5",
            "androidx.compose.material3:material3:1.3.0",
            "androidx.compose.material3:material3-android:1.3.0",
            "androidx.compose.animation:animation:1.7.5",
            "androidx.compose.animation:animation-android:1.7.5",
        )
    }
}
