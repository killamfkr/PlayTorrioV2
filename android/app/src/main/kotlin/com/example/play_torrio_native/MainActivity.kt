package com.example.play_torrio_native

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
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
            "play_torrio/platform",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAndroidTv" -> {
                    val pm = packageManager
                    val leanback = pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                    @Suppress("DEPRECATION")
                    val television = pm.hasSystemFeature(PackageManager.FEATURE_TELEVISION)
                    val uiMode = resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
                    val televisionUi = uiMode == Configuration.UI_MODE_TYPE_TELEVISION
                    result.success(leanback || television || televisionUi)
                }
                else -> result.notImplemented()
            }
        }

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
