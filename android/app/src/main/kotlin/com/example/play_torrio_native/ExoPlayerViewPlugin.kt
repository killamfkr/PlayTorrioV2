package com.example.play_torrio_native

import io.flutter.embedding.engine.plugins.FlutterPlugin

/** Registers [ExoPlayerPlatformViewFactory] for view type `playtorrio_native_exo_player`. */
class ExoPlayerViewPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binding.platformViewRegistry.registerViewFactory(
            "playtorrio_native_exo_player",
            ExoPlayerPlatformViewFactory(binding.binaryMessenger),
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
