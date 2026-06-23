import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

    // ─────────────────────────────────────────────────────────────
    //  Share intake bridge.
    //  Keep these in sync with ShareViewController.swift and
    //  lib/services/share_intake_service.dart — they're the three
    //  surfaces that have to agree.
    // ─────────────────────────────────────────────────────────────
    static let appGroupID  = "group.com.mirrorly.app.shared"
    static let payloadName = "shared_screenshot.jpg"
    static let payloadStampKey = "share.screenshot.timestamp"
    static let methodChannelName = "com.mirrorly.app/share_intake"

    private var shareChannel: FlutterMethodChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // Wire the MethodChannel up front so Flutter can pull pending
        // share payloads at any point during a session (cold-start,
        // foreground after share, etc).
        if let controller = window?.rootViewController as? FlutterViewController {
            shareChannel = FlutterMethodChannel(
                name: AppDelegate.methodChannelName,
                binaryMessenger: controller.binaryMessenger
            )
            shareChannel?.setMethodCallHandler { [weak self] call, result in
                self?.handleMethodCall(call, result: result)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // ─────────────────────────────────────────────────────────────
    //  URL handler.
    //  Fires when a Share Extension (or anything else) opens the
    //  app via "imhim://...". On a share, we ping Flutter so it can
    //  pull the screenshot synchronously off the App Group.
    // ─────────────────────────────────────────────────────────────
    override func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        if url.scheme == "imhim" {
            // Tell Flutter there's a fresh shared screenshot waiting.
            // Flutter pulls it via the "pullPendingShare" method below.
            shareChannel?.invokeMethod(
                "onSharedScreenshot",
                arguments: ["host": url.host ?? "", "query": url.query ?? ""]
            )
            return true
        }
        return super.application(app, open: url, options: options)
    }

    // ─────────────────────────────────────────────────────────────
    //  Flutter-callable methods.
    // ─────────────────────────────────────────────────────────────
    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pullPendingShare":
            // Reads the screenshot bytes + timestamp out of the App
            // Group and returns them to Flutter. After a successful
            // read, the timestamp key is cleared so the same
            // screenshot isn't replayed on the next cold start.
            result(pullPendingShare())

        case "clearAppBadge":
            // v298 — wipe the iOS app-icon red badge. The
            // flutter_local_notifications 17.x plugin doesn't expose
            // a badge setter, so cancelling delivered notifications
            // (which the Dart side already does) left the icon
            // showing "1" forever. This sets it back to 0 directly
            // via UNUserNotificationCenter (iOS 16+) with a fallback
            // to the deprecated applicationIconBadgeNumber API for
            // older devices.
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

    private func pullPendingShare() -> [String: Any]? {
        let defaults = UserDefaults(suiteName: AppDelegate.appGroupID)
        let stamp = defaults?.double(forKey: AppDelegate.payloadStampKey) ?? 0
        guard stamp > 0 else { return nil }

        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppDelegate.appGroupID
        ) else { return nil }

        let fileURL = container.appendingPathComponent(AppDelegate.payloadName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        // Clear the stamp so the next pull is a no-op until the user
        // shares again. Leave the file on disk — overwriting is cheap.
        defaults?.removeObject(forKey: AppDelegate.payloadStampKey)
        defaults?.synchronize()

        return [
            "bytes":     FlutterStandardTypedData(bytes: data),
            "timestamp": stamp,
        ]
    }
}
