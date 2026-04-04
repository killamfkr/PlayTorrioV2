package com.example.play_torrio_native

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class ExoPlayerPlatformViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?>
        return ExoPlayerPlatformView(context, viewId, params, messenger)
    }
}

/**
 * Embedded Media3 ExoPlayer for Flutter [AndroidView] — native surface path (TV-friendly).
 */
class ExoPlayerPlatformView(
    private val context: Context,
    @Suppress("unused")
    private val viewId: Int,
    creationParams: Map<String, Any?>?,
    messenger: BinaryMessenger,
) : PlatformView {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val playerView: PlayerView = PlayerView(context)
    private val player: ExoPlayer
    private var released = false

    private val eventSuffix =
        (creationParams?.get("eventChannelSuffix") as? Number)?.toInt() ?: viewId

    private val eventChannel = EventChannel(
        messenger,
        "com.example.play_torrio_native/exo_player_events_$eventSuffix",
    )

    private var eventSink: EventChannel.EventSink? = null

    init {
        playerView.useController = true
        playerView.setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS)

        val uri = creationParams?.get("uri")?.toString()?.trim().orEmpty()
        val positionMs = (creationParams?.get("positionMs") as? Number)?.toLong() ?: 0L
        @Suppress("UNCHECKED_CAST")
        val headersRaw = creationParams?.get("headers") as? Map<String, Any?>
        val headers = LinkedHashMap<String, String>()
        headersRaw?.forEach { (k, v) ->
            if (k.isNotEmpty() && v != null) headers[k] = v.toString()
        }

        val httpFactory = DefaultHttpDataSource.Factory()
        if (headers.isNotEmpty()) {
            httpFactory.setDefaultRequestProperties(headers)
        }
        val dataSourceFactory = DefaultDataSource.Factory(context, httpFactory)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
        player = ExoPlayer.Builder(context)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()

        playerView.player = player

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED) {
                    eventSink?.success(mapOf("type" to "ended"))
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                val msg = error.message ?: error.errorCodeName
                eventSink?.success(
                    mapOf(
                        "type" to "error",
                        "message" to msg,
                    ),
                )
            }
        })

        if (uri.isNotEmpty()) {
            val item = MediaItem.fromUri(uri)
            mainHandler.post {
                player.setMediaItem(item)
                player.prepare()
                if (positionMs > 0) {
                    player.seekTo(positionMs)
                }
                player.playWhenReady = true
            }
        }
    }

    override fun getView(): View = playerView

    override fun dispose() {
        if (released) return
        released = true
        mainHandler.post {
            try {
                player.release()
            } catch (_: Throwable) {}
        }
        eventChannel.setStreamHandler(null)
        eventSink = null
    }
}
