import Foundation
import Flutter
import UIKit
import MediaPipeTasksVision

/// Native MediaPipe FaceLandmarker (iris) plugin for iOS.
///
/// Speaks the same `auralay/mediapipe_face` contract as the Android
/// plugin + the Dart MediaPipeGazeDetector:
///   init()   -> Bool
///   detect() -> [String: Any]?   (face, yaw, pitch, roll, iris/eye
///                                  centers, eye-open, smile, bbox)
///   dispose()
///
/// The camera plugin hands us BGRA8888 bytes (rotation = 0 on iOS). We
/// rebuild a CGImage and wrap it in an MPImage with the front-camera
/// portrait orientation.
@objc class MediaPipeFaceLandmarkerPlugin: NSObject {

    static let channelName = "auralay/mediapipe_face"

    // MediaPipe 478-landmark iris indices.
    private let rightIris = 468   // subject's right eye
    private let leftIris  = 473   // subject's left eye
    private let rightEyeOuter = 33
    private let rightEyeInner = 133
    private let leftEyeInner  = 362
    private let leftEyeOuter  = 263
    private let noseTip = 1
    // Eye contour rings (upper + lower lid) for the Flutter overlay arcs.
    private let rightEyeRing = [33, 246, 161, 160, 159, 158, 157, 173, 133, 155, 154, 153, 145, 144, 163, 7]
    private let leftEyeRing  = [362, 398, 384, 385, 386, 387, 388, 466, 263, 249, 390, 373, 374, 380, 381, 382]

    // Front-camera portrait orientation for the incoming BGRA buffer.
    // MUST be un-mirrored (.right, not .leftMirrored): the shared Flutter
    // overlay painter already applies the front-cam horizontal flip, so a
    // mirrored frame here double-flips and the mesh tracks the wrong way.
    // If a device test shows the mesh rotated, this is the single knob to
    // turn (.right / .up / .down / .left).
    private let frameOrientation: UIImage.Orientation = .right

    private var landmarker: FaceLandmarker?
    private var lastTs: Int = 0

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            result(initLandmarker())
        case "detect":
            result(detect(call))
        case "dispose":
            landmarker = nil
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func modelPath() -> String? {
        let key = FlutterDartProject.lookupKey(forAsset: "assets/models/face_landmarker.task")
        // Standalone Flutter iOS apps place flutter_assets in the main
        // bundle; some build shapes place them inside App.framework. Try
        // both so the model resolves either way.
        if let p = Bundle.main.path(forResource: key, ofType: nil) { return p }
        let appFwkPath = Bundle.main.bundlePath + "/Frameworks/App.framework"
        if let appFwk = Bundle(path: appFwkPath),
           let p = appFwk.path(forResource: key, ofType: nil) { return p }
        return nil
    }

    private func initLandmarker() -> Bool {
        if landmarker != nil { return true }
        guard let path = modelPath() else {
            return false
        }
        do {
            let options = FaceLandmarkerOptions()
            options.baseOptions.modelAssetPath = path
            options.runningMode = .video
            options.numFaces = 1
            options.outputFaceBlendshapes = true
            options.minFaceDetectionConfidence = 0.4
            options.minTrackingConfidence = 0.4
            options.minFacePresenceConfidence = 0.4
            landmarker = try FaceLandmarker(options: options)
            return true
        } catch {
            return false
        }
    }

    private func detect(_ call: FlutterMethodCall) -> [String: Any]? {
        guard let lm = landmarker,
              let args = call.arguments as? [String: Any],
              let data = (args["bytes"] as? FlutterStandardTypedData)?.data,
              let width = args["width"] as? Int,
              let height = args["height"] as? Int
        else { return nil }
        let bytesPerRow = (args["bytesPerRow"] as? Int) ?? (width * 4)
        var ts = (args["timestampMs"] as? Int) ?? (lastTs + 1)
        if ts <= lastTs { ts = lastTs + 1 }
        lastTs = ts

        guard let image = mpImage(from: data, width: width, height: height, bytesPerRow: bytesPerRow)
        else { return nil }

        let res: FaceLandmarkerResult
        do {
            res = try lm.detect(videoFrame: image, timestampInMilliseconds: ts)
        } catch {
            return nil
        }

        guard let marks = res.faceLandmarks.first, marks.count >= 478 else {
            return ["face": false]
        }

        func p(_ i: Int) -> [Double] { [Double(marks[i].x), Double(marks[i].y)] }
        func ring(_ idx: [Int]) -> [Double] {
            var out = [Double](); out.reserveCapacity(idx.count * 2)
            for i in idx { out.append(Double(marks[i].x)); out.append(Double(marks[i].y)) }
            return out
        }

        let rI = p(rightIris), lI = p(leftIris)
        let rO = p(rightEyeOuter), rN = p(rightEyeInner)
        let lN = p(leftEyeInner), lO = p(leftEyeOuter)
        let nose = p(noseTip)

        let rEyeC = [(rO[0] + rN[0]) / 2, (rO[1] + rN[1]) / 2]
        let lEyeC = [(lO[0] + lN[0]) / 2, (lO[1] + lN[1]) / 2]

        let eyeMidX = (lEyeC[0] + rEyeC[0]) / 2
        let eyeMidY = (lEyeC[1] + rEyeC[1]) / 2
        let interEye = max(1e-4, hypot(lEyeC[0] - rEyeC[0], lEyeC[1] - rEyeC[1]))
        let roll = atan2(lEyeC[1] - rEyeC[1], lEyeC[0] - rEyeC[0]) * 180.0 / Double.pi
        let yaw = min(60.0, max(-60.0, ((nose[0] - eyeMidX) / interEye) * 60.0))
        let pitch = min(60.0, max(-60.0, (((nose[1] - eyeMidY) / interEye) - 0.6) * 60.0))

        var leftOpen = 1.0, rightOpen = 1.0, smile = 0.0
        if let blends = res.faceBlendshapes.first {
            var sL = 0.0, sR = 0.0
            for cat in blends.categories {
                switch cat.categoryName {
                case "eyeBlinkLeft":   leftOpen  = min(1.0, max(0.0, 1.0 - Double(cat.score)))
                case "eyeBlinkRight":  rightOpen = min(1.0, max(0.0, 1.0 - Double(cat.score)))
                case "mouthSmileLeft":  sL = Double(cat.score)
                case "mouthSmileRight": sR = Double(cat.score)
                default: break
                }
            }
            smile = min(1.0, max(0.0, (sL + sR) / 2.0))
        }

        var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0
        for m in marks {
            minX = min(minX, Double(m.x)); maxX = max(maxX, Double(m.x))
            minY = min(minY, Double(m.y)); maxY = max(maxY, Double(m.y))
        }

        return [
            "face": true,
            "yaw": yaw, "pitch": pitch, "roll": roll,
            "leftIris": lI, "rightIris": rI,
            "leftEyeCenter": lEyeC, "rightEyeCenter": rEyeC,
            "leftEyeOpen": leftOpen, "rightEyeOpen": rightOpen,
            "smile": smile,
            "bboxCenter": [(minX + maxX) / 2, (minY + maxY) / 2],
            "bboxWidth": (maxX - minX),
            "leftEyePoly": ring(leftEyeRing),
            "rightEyePoly": ring(rightEyeRing)
        ]
    }

    private func mpImage(from data: Data, width: Int, height: Int, bytesPerRow: Int) -> MPImage? {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: data as CFData),
              let cg = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: bytesPerRow, space: cs,
                bitmapInfo: bitmapInfo, provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let ui = UIImage(cgImage: cg, scale: 1.0, orientation: frameOrientation)
        return try? MPImage(uiImage: ui)
    }
}
