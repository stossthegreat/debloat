package com.mirrorly.mirrorly

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Wire the MediaPipe FaceLandmarker (iris) plugin onto its channel.
        val plugin = MediaPipeFaceLandmarkerPlugin(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MediaPipeFaceLandmarkerPlugin.CHANNEL
        ).setMethodCallHandler(plugin)
    }
}
