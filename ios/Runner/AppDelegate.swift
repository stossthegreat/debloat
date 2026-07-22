import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

    /// Native bridge channel — badge clearing. Must match
    /// `_kBadgeChannel` in lib/services/notification_service.dart.
    static let methodChannelName = "com.debloatos.app/native"

    private var nativeChannel: FlutterMethodChannel?

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
}
