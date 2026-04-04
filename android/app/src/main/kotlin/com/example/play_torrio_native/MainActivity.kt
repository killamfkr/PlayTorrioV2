package com.example.play_torrio_native

import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import java.net.NetworkInterface
import com.ryanheise.audioservice.AudioServiceActivity
import com.thesparks.android_pip.PipCallbackHelper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    private val pipCallbackHelper = PipCallbackHelper()

    /** First non-loopback IPv4 (skips typical link-local), for phone → TV settings QR. */
    private fun preferredLanIpv4(): String? {
        val candidates = mutableListOf<Pair<Int, String>>()
        try {
            val ifaces = NetworkInterface.getNetworkInterfaces() ?: return null
            while (ifaces.hasMoreElements()) {
                val ni = ifaces.nextElement() ?: continue
                if (!ni.isUp || ni.isLoopback) continue
                val addrs = ni.inetAddresses ?: continue
                while (addrs.hasMoreElements()) {
                    val addr = addrs.nextElement() ?: continue
                    val host = addr.hostAddress ?: continue
                    if (!host.contains('.') || host.contains(':')) continue // IPv4 only
                    if (host.startsWith("169.254.")) continue
                    val score = when {
                        host.startsWith("192.168.") -> 300
                        host.startsWith("10.") -> 200
                        host.startsWith("172.") -> {
                            val p = host.substringAfter("172.").substringBefore('.').toIntOrNull()
                            if (p != null && p in 16..31) 250 else 50
                        }
                        else -> 100
                    }
                    candidates.add(score to host)
                }
            }
        } catch (_: Exception) {
            return null
        }
        return candidates.maxByOrNull { it.first }?.second
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        pipCallbackHelper.configureFlutterEngine(flutterEngine)
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
                "getLanIpv4" -> {
                    result.success(preferredLanIpv4())
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        pipCallbackHelper.onPictureInPictureModeChanged(isInPictureInPictureMode, this)
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    }

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
        window.decorView.setBackgroundColor(0xFF0B0B12.toInt())

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }
}
