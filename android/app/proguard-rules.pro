# PlayTorrio — release (R8) rules. Empty rules + minify caused plugin / JNI
# breakages that show up as instant process death on launch.

# Preserve line numbers for stack traces
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Flutter engine & plugins (method channels, reflection)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# JNI
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# audio_service + just_audio stack
-keep class com.ryanheise.** { *; }
-dontwarn com.ryanheise.**

# media_kit / mpv Android bindings
-keep class com.alexmercerind.** { *; }
-dontwarn com.alexmercerind.**

# FFmpeg Kit (multiple forks / repackages — keep broadly)
-keep class com.arthenica.** { *; }
-keep class com.antonkarpenko.** { *; }
-dontwarn com.arthenica.**
-dontwarn com.antonkarpenko.**

# In-app WebView
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-dontwarn com.pichillilorenzo.flutter_inappwebview.**

# Google Fonts / path / secure storage / connectivity
-keep class dev.fluttercommunity.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class dev.flutterplugins.** { *; }

# Kotlin / coroutines (used by many plugins)
-dontwarn kotlinx.coroutines.**
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}

# OkHttp / TLS (used by Flutter tooling and many HTTP stacks)
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
