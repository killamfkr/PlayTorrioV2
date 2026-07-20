package com.example.play_torrio_native

import android.content.Context
import android.util.Log
import com.arthenica.ffmpegkit.FFmpegKit
import com.arthenica.ffmpegkit.FFmpegSession
import com.arthenica.ffmpegkit.ReturnCode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

/**
 * Phone-side HLS fanout for Chromecast using Android **hardware H.264** (`h264_mediacodec`).
 * Decode may still be software depending on source; encode targets Cast-friendly AAC + HLS.
 */
object CastHwTranscodeChannel {
    private const val TAG = "CastHwTranscode"
    private const val CHANNEL = "playtorrio/cast_hw_transcode"

    private val sessions = ConcurrentHashMap<String, FFmpegSession>()
    private val failures = ConcurrentHashMap<String, String>()

    fun register(flutterEngine: FlutterEngine, context: Context) {
        val appCtx = context.applicationContext
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val inputUrl = call.argument<String>("inputUrl")
                    if (inputUrl.isNullOrBlank()) {
                        result.error("bad_args", "inputUrl required", null)
                        return@setMethodCallHandler
                    }
                    @Suppress("UNCHECKED_CAST")
                    val headers = call.argument<Map<String, String>>("headers")

                    val sessionId =
                        UUID.randomUUID().toString().replace("-", "").take(16)
                    val dir = File(appCtx.cacheDir, "cast_hw/$sessionId").apply {
                        deleteRecursively()
                        mkdirs()
                    }
                    val playlistFile = File(dir, "index.m3u8")

                    val args = ArrayList<String>()
                    args.add("-hide_banner")
                    args.add("-loglevel")
                    args.add("warning")
                    args.add("-fflags")
                    args.add("+genpts")
                    if (!headers.isNullOrEmpty()) {
                        val hb = StringBuilder()
                        for ((k, v) in headers) {
                            hb.append(k).append(": ").append(v).append("\r\n")
                        }
                        args.add("-headers")
                        args.add(hb.toString())
                    }
                    args.add("-i")
                    args.add(inputUrl)
                    args.add("-map")
                    args.add("0:v:0?")
                    args.add("-map")
                    args.add("0:a:0?")
                    args.add("-sn")
                    args.add("-dn")
                    args.add("-c:v")
                    args.add("h264_mediacodec")
                    args.add("-b:v")
                    args.add("4M")
                    args.add("-maxrate")
                    args.add("5M")
                    args.add("-bufsize")
                    args.add("8M")
                    args.add("-pix_fmt")
                    args.add("yuv420p")
                    args.add("-c:a")
                    args.add("aac")
                    args.add("-b:a")
                    args.add("128k")
                    args.add("-ac")
                    args.add("2")
                    args.add("-ar")
                    args.add("48000")
                    args.add("-f")
                    args.add("hls")
                    args.add("-hls_time")
                    args.add("2")
                    args.add("-hls_list_size")
                    args.add("12")
                    args.add("-hls_flags")
                    args.add("delete_segments+append_list+program_date_time")
                    args.add("-hls_segment_filename")
                    args.add(File(dir, "segment%03d.ts").absolutePath)
                    args.add(playlistFile.absolutePath)

                    failures.remove(sessionId)
                    val ffmpegSession =
                        FFmpegKit.executeWithArgumentsAsync(args.toTypedArray()) { session ->
                                val rc = session.returnCode
                                when {
                                    ReturnCode.isCancel(rc) ->
                                        failures[sessionId] = "cancelled"

                                    !ReturnCode.isSuccess(rc) -> {
                                        val trace =
                                            session.failStackTrace?.trim()?.takeIf { it.isNotEmpty() }
                                        failures[sessionId] =
                                            (trace ?: "ffmpeg_exit_${rc?.value}").take(600)
                                        Log.w(
                                            TAG,
                                            "session=$sessionId FFmpeg rc=$rc trace=${trace?.take(200)}",
                                        )
                                    }

                                    else ->
                                        Log.i(TAG, "session=$sessionId FFmpeg finished (rc success)")
                                }
                                sessions.remove(sessionId)
                            }
                    sessions[sessionId] = ffmpegSession
                    result.success(
                        mapOf(
                            "sessionId" to sessionId,
                            "playlistPath" to playlistFile.absolutePath,
                            "outputDir" to dir.absolutePath,
                        ),
                    )
                }

                "stop" -> {
                    val sid = call.argument<String>("sessionId")
                    if (sid.isNullOrBlank()) {
                        result.error("bad_args", "sessionId required", null)
                        return@setMethodCallHandler
                    }
                    stopSession(sid, appCtx)
                    result.success(null)
                }

                "failureReason" -> {
                    val sid = call.argument<String>("sessionId")
                    result.success(if (sid.isNullOrBlank()) null else failures[sid])
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun stopSession(sessionId: String, context: Context) {
        sessions.remove(sessionId)?.cancel()
        failures.remove(sessionId)
        File(context.cacheDir, "cast_hw/$sessionId").deleteRecursively()
    }
}
