import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// android/key.properties (see key.properties.example) or -P PLAYTORRIO_KEYSTORE_* for CI.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val storeFileFromKeyProps = keystoreProperties.getProperty("storeFile")
val useKeyPropertiesSigning =
    keystorePropertiesFile.exists() &&
        !storeFileFromKeyProps.isNullOrBlank() &&
        rootProject.file(storeFileFromKeyProps).isFile

val keystorePathGradleProp = project.findProperty("PLAYTORRIO_KEYSTORE_PATH") as String?
val useGradlePropertySigning =
    !keystorePathGradleProp.isNullOrBlank() &&
        file(keystorePathGradleProp).isFile

android {
    namespace = "com.example.play_torrio_native"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Enable desugaring for modern Java features (required by ota_update)
        isCoreLibraryDesugaringEnabled = true
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
        // Enable multidex for desugaring
        multiDexEnabled = true
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

            // Same signing key every release → OTA / in-app updates can install over the old APK.
            signingConfig =
                signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    // In-place updates: every APK must use the SAME keystore as the build already on the device.
    signingConfigs {
        if (useKeyPropertiesSigning || useGradlePropertySigning) {
            create("release") {
                if (useKeyPropertiesSigning) {
                    storeFile = rootProject.file(storeFileFromKeyProps!!)
                    storePassword = keystoreProperties.getProperty("storePassword") ?: ""
                    keyAlias = keystoreProperties.getProperty("keyAlias") ?: "playtorrio"
                    keyPassword = keystoreProperties.getProperty("keyPassword") ?: ""
                } else {
                    storeFile = file(keystorePathGradleProp!!)
                    storePassword =
                        project.findProperty("PLAYTORRIO_KEYSTORE_PASSWORD") as String? ?: ""
                    keyAlias = project.findProperty("PLAYTORRIO_KEY_ALIAS") as String? ?: "playtorrio"
                    keyPassword =
                        project.findProperty("PLAYTORRIO_KEY_PASSWORD") as String? ?: ""
                }
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring for modern Java features
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
