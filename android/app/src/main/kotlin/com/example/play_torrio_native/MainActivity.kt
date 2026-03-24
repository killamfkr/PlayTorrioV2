package com.example.play_torrio_native

import android.app.PictureInPictureParams
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Match the window background to the app's dark theme so any area
        // exposed during a Flutter surface resize (rotation) is the same
        // colour — not white/black.  Everything else (immersive mode,
        // orientation, system-bar visibility) is handled by Flutter's
        // SystemChrome from the Dart side to avoid conflicts.
        window.decorView.setBackgroundColor(0xFF0B0B12.toInt())
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "play_torrio/builtin_player",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPictureInPicture" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val params = PictureInPictureParams.Builder().build()
                            enterPictureInPictureMode(params)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
