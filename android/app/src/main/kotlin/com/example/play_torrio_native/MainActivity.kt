package com.example.play_torrio_native

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.play_torrio_native/device",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAndroidTv" -> {
                    val uiModeManager =
                        getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                    val isTv =
                        uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
                    result.success(isTv)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Match the window background to the app's dark theme so any area
        // exposed during a Flutter surface resize (rotation) is the same
        // colour — not white/black.  Everything else (immersive mode,
        // orientation, system-bar visibility) is handled by Flutter's
        // SystemChrome from the Dart side to avoid conflicts.
        window.decorView.setBackgroundColor(0xFF0B0B12.toInt())
    }
}
