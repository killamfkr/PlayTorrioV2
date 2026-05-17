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

    /** Best non-loopback IPv4 for LAN URLs (Wi‑Fi / Ethernet over VPN / tailscale). */
    private fun preferredLanIpv4(): String? {
        val candidates = mutableListOf<Pair<Int, String>>()
        try {
            val ifaces = NetworkInterface.getNetworkInterfaces() ?: return null
            while (ifaces.hasMoreElements()) {
                val ni = ifaces.nextElement() ?: continue
                if (!ni.isUp || ni.isLoopback) continue
                val ifaceMod = lanIfaceModifier(ni.name)
                val addrs = ni.inetAddresses ?: continue
                while (addrs.hasMoreElements()) {
                    val addr = addrs.nextElement() ?: continue
                    val host = addr.hostAddress ?: continue
                    if (!host.contains('.') || host.contains(':')) continue // IPv4 only
                    if (host.startsWith("169.254.")) continue
                    val ipScore = when {
                        host.startsWith("192.168.") -> 5000
                        host.startsWith("172.") -> {
                            val p = host.substringAfter("172.").substringBefore('.').toIntOrNull()
                            if (p != null && p in 16..31) 4500 else 600
                        }
                        host.startsWith("10.") -> 2000
                        host.startsWith("100.") -> {
                            val p = host.substringAfter("100.").substringBefore('.').toIntOrNull()
                            if (p != null && p in 64..127) 500 else 800
                        }
                        else -> 800
                    }
                    candidates.add((ipScore + ifaceMod) to host)
                }
            }
        } catch (_: Exception) {
            return null
        }
        return candidates.maxByOrNull { it.first }?.second
    }

    private fun lanIfaceModifier(name: String): Int {
        val n = name.lowercase()
        val vpnish = listOf(
            "tailscale", "tun", "tap", "wg", "ppp", "nordlynx", "nordtap",
            "vpn", "veth", "docker", "br-", "virbr", "zt", "hamachi",
            "outline", "warp", "rndis", "ipsec", "l2tp", "pptp",
        )
        for (b in vpnish) {
            if (n.contains(b)) return -8000
        }
        if (n.contains("wlan") || n.contains("wifi") || n.contains("wlp") || n.contains("wl")) {
            return 80
        }
        if (n.contains("en") || n.contains("eth")) return 60
        return 0
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

    /**
     * Re-apply immersive mode after configuration changes. Also works around a Flutter
     * engine race where FlutterView may suppress viewport metrics during rapid resize.
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
        window.decorView.setBackgroundColor(0xFF0B0B12.toInt())

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }
}
