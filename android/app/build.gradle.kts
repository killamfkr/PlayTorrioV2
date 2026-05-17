import kotlin.math.max

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.play_torrio_native"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by ota_update and other deps that use newer java.time APIs on older minSdk
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.play_torrio_native"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // ffmpeg_kit_flutter_new_https documents Android API 24+.
        minSdk = max(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Enable minification and resource shrinking
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )

            // Use release signing config if available, otherwise fall back to debug
            signingConfig = if (project.hasProperty("PLAYTORRIO_KEYSTORE_PATH")) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
    
    // Release signing configuration (uses environment variables or gradle.properties)
    signingConfigs {
        create("release") {
            storeFile = file(project.findProperty("PLAYTORRIO_KEYSTORE_PATH") as String? ?: "release.keystore")
            storePassword = project.findProperty("PLAYTORRIO_KEYSTORE_PASSWORD") as String? ?: ""
            keyAlias = project.findProperty("PLAYTORRIO_KEY_ALIAS") as String? ?: "playtorrio"
            keyPassword = project.findProperty("PLAYTORRIO_KEY_PASSWORD") as String? ?: ""
        }
    }

    packaging {
        jniLibs {
            pickFirsts += listOf(
                "**/libc++_shared.so",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
