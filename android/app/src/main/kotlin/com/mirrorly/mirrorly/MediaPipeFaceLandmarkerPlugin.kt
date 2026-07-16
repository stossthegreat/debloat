package com.mirrorly.mirrorly

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult

/// Native MediaPipe FaceLandmarker (iris) plugin.
///
/// Method channel `auralay/mediapipe_face` — the exact contract the Dart
/// [MediaPipeGazeDetector] speaks:
///
///   init()   → Bool   — build the landmarker from the bundled model.
///   detect() → Map    — { face, yaw, pitch, roll, leftIris, rightIris,
///                          leftEyeCenter, rightEyeCenter, leftEyeOpen,
///                          rightEyeOpen, smile, bboxCenter, bboxWidth }
///   dispose()         — free the landmarker.
///
/// The model (`assets/models/face_landmarker.task`) is a Flutter asset, so
/// we resolve its AssetManager lookup key via FlutterLoader and hand that
/// to BaseOptions — no copy-to-disk needed.
class MediaPipeFaceLandmarkerPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "auralay/mediapipe_face"
        // MediaPipe 478-landmark iris indices.
        private const val RIGHT_IRIS = 468 // subject's right eye
        private const val LEFT_IRIS  = 473 // subject's left eye
        private const val RIGHT_EYE_OUTER = 33
        private const val RIGHT_EYE_INNER = 133
        private const val LEFT_EYE_INNER  = 362
        private const val LEFT_EYE_OUTER  = 263
        private const val NOSE_TIP = 1
        // Eye contour rings (upper + lower lid) so the Flutter overlay can
        // draw the tracking arc on each eye.
        private val RIGHT_EYE_RING = intArrayOf(
            33, 246, 161, 160, 159, 158, 157, 173, 133, 155, 154, 153, 145, 144, 163, 7)
        private val LEFT_EYE_RING = intArrayOf(
            362, 398, 384, 385, 386, 387, 388, 466, 263, 249, 390, 373, 374, 380, 381, 382)
    }

    private var landmarker: FaceLandmarker? = null
    private var lastTs: Long = 0

    override fun onMethodCall(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result
    ) {
        when (call.method) {
            "init" -> result.success(initLandmarker())
            "detect" -> {
                try {
                    result.success(detect(call))
                } catch (e: Exception) {
                    // Never throw across the channel — a null result tells
                    // Dart "no face this frame" and keeps the stream alive.
                    result.success(null)
                }
            }
            "dispose" -> {
                landmarker?.close()
                landmarker = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun initLandmarker(): Boolean {
        if (landmarker != null) return true
        return try {
            val assetKey = FlutterInjector.instance().flutterLoader()
                .getLookupKeyForAsset("assets/models/face_landmarker.task")
            val base = BaseOptions.builder()
                .setModelAssetPath(assetKey)
                .build()
            val options = FaceLandmarker.FaceLandmarkerOptions.builder()
                .setBaseOptions(base)
                .setRunningMode(RunningMode.VIDEO)
                .setNumFaces(1)
                .setOutputFaceBlendshapes(true)
                .setOutputFacialTransformationMatrixes(false)
                .setMinFaceDetectionConfidence(0.4f)
                .setMinTrackingConfidence(0.4f)
                .setMinFacePresenceConfidence(0.4f)
                .build()
            landmarker = FaceLandmarker.createFromOptions(context, options)
            true
        } catch (e: Throwable) {
            false
        }
    }

    private fun detect(call: io.flutter.plugin.common.MethodCall): Map<String, Any?>? {
        val lm = landmarker ?: return null
        val bytes = call.argument<ByteArray>("bytes") ?: return null
        val width = call.argument<Int>("width") ?: return null
        val height = call.argument<Int>("height") ?: return null
        val rotation = call.argument<Int>("rotation") ?: 0
        val format = call.argument<String>("format") ?: "nv21"
        var ts = (call.argument<Number>("timestampMs")?.toLong()) ?: (lastTs + 1)
        if (ts <= lastTs) ts = lastTs + 1
        lastTs = ts

        val bitmap = toBitmap(bytes, width, height, format, rotation) ?: return null

        val mpImage = BitmapImageBuilder(bitmap).build()
        val res: FaceLandmarkerResult = lm.detectForVideo(mpImage, ts)

        if (res.faceLandmarks().isEmpty()) {
            return mapOf("face" to false)
        }
        val marks = res.faceLandmarks()[0]
        if (marks.size < 478) {
            // Iris landmarks require the refined 478-point model.
            return mapOf("face" to false)
        }

        fun px(i: Int) = doubleArrayOf(
            marks[i].x().toDouble(), marks[i].y().toDouble()
        )

        fun ring(idx: IntArray): List<Double> {
            val out = ArrayList<Double>(idx.size * 2)
            for (i in idx) {
                out.add(marks[i].x().toDouble())
                out.add(marks[i].y().toDouble())
            }
            return out
        }

        val rIris = px(RIGHT_IRIS)
        val lIris = px(LEFT_IRIS)
        val rOuter = px(RIGHT_EYE_OUTER)
        val rInner = px(RIGHT_EYE_INNER)
        val lInner = px(LEFT_EYE_INNER)
        val lOuter = px(LEFT_EYE_OUTER)
        val nose = px(NOSE_TIP)

        val rEyeCenter = doubleArrayOf((rOuter[0] + rInner[0]) / 2, (rOuter[1] + rInner[1]) / 2)
        val lEyeCenter = doubleArrayOf((lOuter[0] + lInner[0]) / 2, (lOuter[1] + lInner[1]) / 2)

        // ── Head pose from landmark geometry (rough — iris carries the
        //    real gaze signal; the Dart scorer weights yaw at only 20%).
        val eyeMidX = (lEyeCenter[0] + rEyeCenter[0]) / 2
        val eyeMidY = (lEyeCenter[1] + rEyeCenter[1]) / 2
        val interEye = max(1e-4, hypot(lEyeCenter[0] - rEyeCenter[0], lEyeCenter[1] - rEyeCenter[1]))
        val roll = Math.toDegrees(atan2(lEyeCenter[1] - rEyeCenter[1], lEyeCenter[0] - rEyeCenter[0]))
        val yaw = (((nose[0] - eyeMidX) / interEye) * 60.0).coerceIn(-60.0, 60.0)
        val pitch = ((((nose[1] - eyeMidY) / interEye) - 0.6) * 60.0).coerceIn(-60.0, 60.0)

        // ── Blendshapes: eye-open + smile.
        var leftOpen = 1.0
        var rightOpen = 1.0
        var smile = 0.0
        val blends = res.faceBlendshapes()
        if (blends.isPresent && blends.get().isNotEmpty()) {
            var smileL = 0.0; var smileR = 0.0
            for (cat in blends.get()[0]) {
                when (cat.categoryName()) {
                    "eyeBlinkLeft"  -> leftOpen  = (1.0 - cat.score()).coerceIn(0.0, 1.0)
                    "eyeBlinkRight" -> rightOpen = (1.0 - cat.score()).coerceIn(0.0, 1.0)
                    "mouthSmileLeft"  -> smileL = cat.score().toDouble()
                    "mouthSmileRight" -> smileR = cat.score().toDouble()
                }
            }
            smile = ((smileL + smileR) / 2.0).coerceIn(0.0, 1.0)
        }

        // ── Bbox from landmark extents.
        var minX = 1.0; var minY = 1.0; var maxX = 0.0; var maxY = 0.0
        for (m in marks) {
            minX = min(minX, m.x().toDouble()); maxX = max(maxX, m.x().toDouble())
            minY = min(minY, m.y().toDouble()); maxY = max(maxY, m.y().toDouble())
        }

        return mapOf(
            "face" to true,
            "yaw" to yaw,
            "pitch" to pitch,
            "roll" to roll,
            "leftIris" to listOf(lIris[0], lIris[1]),
            "rightIris" to listOf(rIris[0], rIris[1]),
            "leftEyeCenter" to listOf(lEyeCenter[0], lEyeCenter[1]),
            "rightEyeCenter" to listOf(rEyeCenter[0], rEyeCenter[1]),
            "leftEyeOpen" to leftOpen,
            "rightEyeOpen" to rightOpen,
            "smile" to smile,
            "bboxCenter" to listOf((minX + maxX) / 2, (minY + maxY) / 2),
            "bboxWidth" to (maxX - minX),
            "leftEyePoly" to ring(LEFT_EYE_RING),
            "rightEyePoly" to ring(RIGHT_EYE_RING)
        )
    }

    /// NV21 (Android) or BGRA8888 (unused on Android) → upright Bitmap.
    private fun toBitmap(
        bytes: ByteArray, width: Int, height: Int, format: String, rotation: Int
    ): Bitmap? {
        val base: Bitmap = if (format == "nv21") {
            val yuv = YuvImage(bytes, ImageFormat.NV21, width, height, null)
            val out = ByteArrayOutputStream()
            yuv.compressToJpeg(Rect(0, 0, width, height), 85, out)
            val jpeg = out.toByteArray()
            BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size) ?: return null
        } else {
            // bgra8888 fallback (iOS uses its own plugin; kept defensive).
            val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bmp.copyPixelsFromBuffer(java.nio.ByteBuffer.wrap(bytes))
            bmp
        }
        if (rotation == 0) return base
        val m = Matrix().apply { postRotate(rotation.toFloat()) }
        return Bitmap.createBitmap(base, 0, 0, base.width, base.height, m, true)
    }
}
