import AVFoundation
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

    /// Native bridge channel — badge clearing. Must match
    /// `_kBadgeChannel` in lib/services/notification_service.dart.
    static let methodChannelName = "com.debloatos.app/native"

    /// MP4 encoder channel — must match `_ch` in
    /// lib/services/evolution_video_service.dart. Dart streams raw RGBA
    /// frames; we encode H.264 with AVAssetWriter.
    static let videoChannelName = "com.debloatos.app/video"

    private var nativeChannel: FlutterMethodChannel?
    private var videoChannel: FlutterMethodChannel?

    // ── Video encoder state ─────────────────────────────────────
    private var vWriter: AVAssetWriter?
    private var vInput: AVAssetWriterInput?
    private var vAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var vFrameIndex: Int64 = 0
    private var vFPS: Int32 = 24
    private var vWidth = 0
    private var vHeight = 0
    private var vPath = ""
    private let vQueue = DispatchQueue(label: "com.debloatos.app.videoencode")

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        if let controller = window?.rootViewController as? FlutterViewController {
            nativeChannel = FlutterMethodChannel(
                name: AppDelegate.methodChannelName,
                binaryMessenger: controller.binaryMessenger
            )
            nativeChannel?.setMethodCallHandler { [weak self] call, result in
                self?.handleMethodCall(call, result: result)
            }

            videoChannel = FlutterMethodChannel(
                name: AppDelegate.videoChannelName,
                binaryMessenger: controller.binaryMessenger
            )
            videoChannel?.setMethodCallHandler { [weak self] call, result in
                self?.handleVideoCall(call, result: result)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ─────────────────────────────────────────────────────────────
    //  Flutter-callable methods.
    // ─────────────────────────────────────────────────────────────
    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "clearAppBadge":
            // Wipe the iOS app-icon red badge. flutter_local_notifications
            // 17.x has no badge setter, so we reset it directly via
            // UNUserNotificationCenter (iOS 16+) with a fallback to the
            // deprecated applicationIconBadgeNumber API for older devices.
            if #available(iOS 16.0, *) {
                UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
            } else {
                DispatchQueue.main.async {
                    UIApplication.shared.applicationIconBadgeNumber = 0
                }
            }
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ─────────────────────────────────────────────────────────────
    //  MP4 encoder — start / frame / finish / abort.
    //  All heavy work runs on vQueue; results hop back to main. The
    //  Dart side awaits every 'frame' call, so the queue never has
    //  more than one frame in flight (natural backpressure).
    // ─────────────────────────────────────────────────────────────
    private func handleVideoCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            guard let args = call.arguments as? [String: Any],
                  let w = args["width"] as? Int,
                  let h = args["height"] as? Int,
                  let fps = args["fps"] as? Int,
                  let path = args["path"] as? String else {
                result(FlutterError(code: "bad_args", message: "start needs width/height/fps/path", details: nil))
                return
            }
            vQueue.async { [weak self] in
                do {
                    try self?.encoderStart(width: w, height: h, fps: Int32(fps), path: path)
                    DispatchQueue.main.async { result(nil) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "frame":
            guard let data = call.arguments as? FlutterStandardTypedData else {
                result(FlutterError(code: "bad_args", message: "frame needs RGBA bytes", details: nil))
                return
            }
            vQueue.async { [weak self] in
                do {
                    try self?.encoderAppend(rgba: data.data)
                    DispatchQueue.main.async { result(nil) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "frame_failed", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "finish":
            vQueue.async { [weak self] in
                self?.encoderFinish { path, err in
                    DispatchQueue.main.async {
                        if let path = path {
                            result(path)
                        } else {
                            result(FlutterError(code: "finish_failed", message: err ?? "unknown", details: nil))
                        }
                    }
                }
            }

        case "abort":
            vQueue.async { [weak self] in
                self?.encoderAbort()
                DispatchQueue.main.async { result(nil) }
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private enum EncoderError: Error, LocalizedError {
        case notStarted, poolUnavailable, bufferCreate, appendFailed, badFrameSize
        var errorDescription: String? { return "video encoder error: \(self)" }
    }

    private func encoderStart(width: Int, height: Int, fps: Int32, path: String) throws {
        encoderAbort() // clear any stale session

        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? EncoderError.notStarted
        }
        writer.startSession(atSourceTime: .zero)

        vWriter = writer
        vInput = input
        vAdaptor = adaptor
        vFrameIndex = 0
        vFPS = fps
        vWidth = width
        vHeight = height
        vPath = path
    }

    private func encoderAppend(rgba: Data) throws {
        guard let input = vInput, let adaptor = vAdaptor, vWriter != nil else {
            throw EncoderError.notStarted
        }
        guard rgba.count >= vWidth * vHeight * 4 else {
            throw EncoderError.badFrameSize
        }
        var pbOut: CVPixelBuffer?
        if let pool = adaptor.pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pbOut)
        }
        if pbOut == nil {
            // Pool can lag behind startSession on some OS versions —
            // fall back to a directly-allocated buffer.
            CVPixelBufferCreate(
                kCFAllocatorDefault, vWidth, vHeight,
                kCVPixelFormatType_32BGRA,
                [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary,
                &pbOut)
        }
        guard let pb = pbOut else { throw EncoderError.bufferCreate }

        CVPixelBufferLockBaseAddress(pb, [])
        let dstBase = CVPixelBufferGetBaseAddress(pb)!
        let dstStride = CVPixelBufferGetBytesPerRow(pb)
        let w = vWidth, h = vHeight

        rgba.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            let s = src.bindMemory(to: UInt8.self).baseAddress!
            for row in 0..<h {
                let srcRow = s + row * w * 4
                let dstRow = dstBase.advanced(by: row * dstStride)
                    .assumingMemoryBound(to: UInt8.self)
                var i = 0
                while i < w * 4 {
                    // RGBA → BGRA swizzle.
                    dstRow[i]     = srcRow[i + 2]
                    dstRow[i + 1] = srcRow[i + 1]
                    dstRow[i + 2] = srcRow[i]
                    dstRow[i + 3] = srcRow[i + 3]
                    i += 4
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])

        // Backpressure — the writer occasionally needs a beat.
        var spins = 0
        while !input.isReadyForMoreMediaData && spins < 2000 {
            usleep(2000)
            spins += 1
        }
        let time = CMTime(value: vFrameIndex, timescale: vFPS)
        guard adaptor.append(pb, withPresentationTime: time) else {
            throw vWriter?.error ?? EncoderError.appendFailed
        }
        vFrameIndex += 1
    }

    private func encoderFinish(_ done: @escaping (String?, String?) -> Void) {
        guard let writer = vWriter, let input = vInput else {
            done(nil, "encoder not started")
            return
        }
        input.markAsFinished()
        let path = vPath
        writer.finishWriting { [weak self] in
            let ok = writer.status == .completed
            let err = writer.error?.localizedDescription
            self?.vWriter = nil
            self?.vInput = nil
            self?.vAdaptor = nil
            done(ok ? path : nil, ok ? nil : (err ?? "writer status \(writer.status.rawValue)"))
        }
    }

    private func encoderAbort() {
        if let writer = vWriter, writer.status == .writing {
            writer.cancelWriting()
        }
        if !vPath.isEmpty, vWriter != nil {
            try? FileManager.default.removeItem(atPath: vPath)
        }
        vWriter = nil
        vInput = nil
        vAdaptor = nil
        vFrameIndex = 0
    }
}
