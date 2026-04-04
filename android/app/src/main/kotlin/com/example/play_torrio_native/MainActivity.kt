package com.example.play_torrio_native

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.Display
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import com.thesparks.android_pip.PipCallbackHelper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

class MainActivity : AudioServiceActivity() {

    private val pipCallbackHelper = PipCallbackHelper()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        pipCallbackHelper.configureFlutterEngine(flutterEngine)
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(ExoPlayerViewPlugin())
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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.play_torrio_native/display",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setPreferredVideoRefreshRate" -> {
                    val fpsAny = call.argument<Any>("fps")
                    val fps = when (fpsAny) {
                        is Double -> fpsAny
                        is Float -> fpsAny.toDouble()
                        is Int -> fpsAny.toDouble()
                        else -> 0.0
                    }
                    if (fps < 10.0 || fps > 240.0) {
                        result.success(false)
                    } else {
                        result.success(setPreferredVideoRefreshRate(fps))
                    }
                }
                "clearPreferredDisplayMode" -> {
                    clearPreferredDisplayMode()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun displayCompat(): Display? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        }

    /**
     * Picks a [Display.Mode] that **divides evenly** into [contentFps] (within tolerance),
     * like Stremio / frame-rate match: e.g. 23.976 fps → prefer 24 Hz, 48 Hz, 120 Hz over 60 Hz
     * (60/23.976 ≈ 2.5 → heavy judder; 120/5 ≈ 24 → clean).
     */
    private fun setPreferredVideoRefreshRate(contentFps: Double): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        if (contentFps < 10.0 || contentFps > 240.0) return false
        return try {
            val display = displayCompat() ?: return false
            val modes = display.supportedModes ?: return false
            if (modes.isEmpty()) return false
            val best = bestDisplayModeForContentFps(modes, contentFps) ?: return false
            val attrs = window.attributes
            attrs.preferredDisplayModeId = best.modeId
            window.attributes = attrs
            true
        } catch (_: Throwable) {
            false
        }
    }

    /** Minimize |refreshRate/n - contentFps| over n in 1..6; tie-break higher refresh rate. */
    private fun bestDisplayModeForContentFps(
        modes: Array<Display.Mode>,
        contentFps: Double,
    ): Display.Mode? {
        var best: Display.Mode? = null
        var bestRelErr = Double.MAX_VALUE
        for (mode in modes) {
            val r = mode.refreshRate.toDouble()
            if (r < 20.0) continue
            var minAbsErr = Double.MAX_VALUE
            for (n in 1..6) {
                val err = abs(r / n.toDouble() - contentFps)
                if (err < minAbsErr) minAbsErr = err
            }
            val relErr = minAbsErr / contentFps
            if (relErr < bestRelErr - 1e-5) {
                best = mode
                bestRelErr = relErr
            } else if (abs(relErr - bestRelErr) <= 1e-5 && best != null && r > best.refreshRate) {
                best = mode
            }
        }
        return best
    }

    private fun clearPreferredDisplayMode() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val attrs = window.attributes
            attrs.preferredDisplayModeId = 0
            window.attributes = attrs
        } catch (_: Throwable) {}
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        pipCallbackHelper.onPictureInPictureModeChanged(isInPictureInPictureMode, this)
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    }

    /**
     * From ayman708-UX fork: after configuration changes (rotation, TV display mode),
     * re-apply immersive bars so FlutterView picks up correct viewport metrics.
     */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        window.decorView.postDelayed({ applyImmersiveMode() }, 300)
    }

    private fun applyImmersiveMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.apply {
                hide(WindowInsets.Type.systemBars())
                systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                )
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Match the window background to the app's dark theme so any area
        // exposed during a Flutter surface resize (rotation) is the same
        // colour — not white/black.
        window.decorView.setBackgroundColor(0xFF0B0B12.toInt())

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }
}
