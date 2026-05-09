# PlayTorrio — Google Cast / flutter_chrome_cast (required for release minify)
# Without these keeps, R8 can strip Cast OptionsProvider / framework classes and
# CastContext.getSharedInstance() fails at runtime.

-keepattributes Signature
-keepattributes Exceptions
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod

-keep class com.google.android.gms.cast.** { *; }
-keep interface com.google.android.gms.cast.** { *; }
-dontwarn com.google.android.gms.cast.**

-keep class com.google.android.gms.common.** { *; }

# Plugin + manifest OPTIONS_PROVIDER_CLASS_NAME (must not be renamed or removed)
-keep class com.felnanuke.google_cast.** { *; }

-keepclassmembers class * implements com.google.android.gms.cast.framework.OptionsProvider {
    <methods>;
}

# FFmpeg Kit (Android HW transcode path for Chromecast)
-keep class com.arthenica.** { *; }
-dontwarn com.arthenica.**
