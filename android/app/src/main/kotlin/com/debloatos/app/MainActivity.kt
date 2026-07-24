package com.debloatos.app

import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Hosts the MP4 encoder channel (com.debloatos.app/video) used by the
 * Face Evolution share clip. Dart renders branded RGBA frames and
 * streams them here; we encode H.264 with MediaCodec and mux to MP4
 * with MediaMuxer. All work runs on a single background executor; the
 * Dart side awaits every call, so at most one frame is in flight.
 */
class MainActivity : FlutterActivity() {

    private val videoExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var encoder: Mp4Encoder? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.debloatos.app/video"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> videoExecutor.execute {
                    try {
                        encoder?.abort()
                        val w = call.argument<Int>("width")!!
                        val h = call.argument<Int>("height")!!
                        val fps = call.argument<Int>("fps")!!
                        val path = call.argument<String>("path")!!
                        encoder = Mp4Encoder(w, h, fps, path)
                        mainHandler.post { result.success(null) }
                    } catch (e: Exception) {
                        encoder = null
                        mainHandler.post { result.error("start_failed", e.message, null) }
                    }
                }
                "frame" -> videoExecutor.execute {
                    try {
                        val bytes = call.arguments as ByteArray
                        encoder?.encodeFrame(bytes)
                            ?: throw IllegalStateException("encoder not started")
                        mainHandler.post { result.success(null) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("frame_failed", e.message, null) }
                    }
                }
                "finish" -> videoExecutor.execute {
                    try {
                        val path = encoder?.finish()
                            ?: throw IllegalStateException("encoder not started")
                        encoder = null
                        mainHandler.post { result.success(path) }
                    } catch (e: Exception) {
                        encoder = null
                        mainHandler.post { result.error("finish_failed", e.message, null) }
                    }
                }
                "abort" -> videoExecutor.execute {
                    try { encoder?.abort() } catch (_: Exception) {}
                    encoder = null
                    mainHandler.post { result.success(null) }
                }
                else -> result.notImplemented()
            }
        }
    }
}

/** RGBA-frames → H.264 MP4, via MediaCodec (flexible YUV input) + MediaMuxer. */
private class Mp4Encoder(
    private val width: Int,
    private val height: Int,
    private val fps: Int,
    private val outPath: String,
) {
    private val codec: MediaCodec = MediaCodec.createEncoderByType("video/avc")
    private var muxer: MediaMuxer
    private var trackIndex = -1
    private var muxerStarted = false
    private var frameIndex = 0L
    private val bufferInfo = MediaCodec.BufferInfo()
    private var released = false

    init {
        File(outPath).delete()
        val fmt = MediaFormat.createVideoFormat("video/avc", width, height).apply {
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible
            )
            setInteger(MediaFormat.KEY_BIT_RATE, 6_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        codec.configure(fmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
        muxer = MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    }

    fun encodeFrame(rgba: ByteArray) {
        check(!released) { "encoder released" }
        require(rgba.size >= width * height * 4) { "bad frame size ${rgba.size}" }
        val inIdx = codec.dequeueInputBuffer(5_000_000)
        if (inIdx < 0) throw RuntimeException("encoder input stalled")
        val image = codec.getInputImage(inIdx)
            ?: throw RuntimeException("no flexible input image")
        fillYuv(image, rgba)
        val pts = frameIndex * 1_000_000L / fps
        codec.queueInputBuffer(inIdx, 0, width * height * 3 / 2, pts, 0)
        frameIndex++
        drain(false)
    }

    fun finish(): String {
        check(!released) { "encoder released" }
        // Signal EOS with an empty input buffer, then drain everything.
        val inIdx = codec.dequeueInputBuffer(5_000_000)
        if (inIdx >= 0) {
            codec.queueInputBuffer(
                inIdx, 0, 0,
                frameIndex * 1_000_000L / fps,
                MediaCodec.BUFFER_FLAG_END_OF_STREAM
            )
        }
        drain(true)
        release(stopMuxer = true)
        return outPath
    }

    fun abort() {
        if (released) return
        release(stopMuxer = false)
        File(outPath).delete()
    }

    private fun release(stopMuxer: Boolean) {
        released = true
        try { codec.stop() } catch (_: Exception) {}
        try { codec.release() } catch (_: Exception) {}
        try {
            if (stopMuxer && muxerStarted) muxer.stop()
        } catch (_: Exception) {}
        try { muxer.release() } catch (_: Exception) {}
    }

    private fun drain(endOfStream: Boolean) {
        val timeout = if (endOfStream) 10_000L else 0L
        while (true) {
            val outIdx = codec.dequeueOutputBuffer(bufferInfo, timeout)
            when {
                outIdx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream) return
                    // keep spinning until EOS flag arrives
                }
                outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    check(!muxerStarted) { "format changed twice" }
                    trackIndex = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                    muxerStarted = true
                }
                outIdx >= 0 -> {
                    val buf = codec.getOutputBuffer(outIdx)!!
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                        bufferInfo.size = 0 // config data lives in the track format
                    }
                    if (bufferInfo.size > 0 && muxerStarted) {
                        buf.position(bufferInfo.offset)
                        buf.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(trackIndex, buf, bufferInfo)
                    }
                    codec.releaseOutputBuffer(outIdx, false)
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    /** BT.601 RGBA → flexible YUV420 plane fill. */
    private fun fillYuv(image: Image, rgba: ByteArray) {
        val yP = image.planes[0]
        val uP = image.planes[1]
        val vP = image.planes[2]
        val yBuf = yP.buffer
        val uBuf = uP.buffer
        val vBuf = vP.buffer
        val yStride = yP.rowStride
        val yPix = yP.pixelStride
        val uStride = uP.rowStride
        val uPix = uP.pixelStride
        val vStride = vP.rowStride
        val vPix = vP.pixelStride

        var idx = 0
        for (row in 0 until height) {
            val even = row % 2 == 0
            for (col in 0 until width) {
                val r = rgba[idx].toInt() and 0xFF
                val g = rgba[idx + 1].toInt() and 0xFF
                val b = rgba[idx + 2].toInt() and 0xFF
                idx += 4
                val y = (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16)
                    .coerceIn(0, 255)
                yBuf.put(row * yStride + col * yPix, y.toByte())
                if (even && col % 2 == 0) {
                    val u = (((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128)
                        .coerceIn(0, 255)
                    val v = (((112 * r - 94 * g - 18 * b + 128) shr 8) + 128)
                        .coerceIn(0, 255)
                    uBuf.put((row / 2) * uStride + (col / 2) * uPix, u.toByte())
                    vBuf.put((row / 2) * vStride + (col / 2) * vPix, v.toByte())
                }
            }
        }
    }
}
