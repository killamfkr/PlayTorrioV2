# PlayTorrio — Android Auto binds to MediaBrowserService via audio_service.
# Without these keeps, R8 can strip or rename classes and the app disappears from Android Auto.

-keep class com.example.play_torrio_native.MainActivity { *; }

-keep class com.ryanheise.audioservice.** { *; }
-dontwarn com.ryanheise.audioservice.**

-keep class androidx.media.** { *; }
-keep interface androidx.media.** { *; }
