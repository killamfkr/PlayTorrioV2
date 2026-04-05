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
        minSdk = flutter.minSdkVersion
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
}

flutter {
    source = "../.."
}
