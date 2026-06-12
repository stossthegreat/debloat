import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // MethodChannel for the ImHim Keyboard onboarding flow. Flutter
    // calls "openSettings" → we open the ImHim row in iOS Settings
    // so the user can tap into Keyboards → Add New Keyboard and
    // toggle Allow Full Access without leaving the app's gravity.
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.mirrorly.app/keyboard",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { (call, result) in
        switch call.method {
        case "openSettings":
          if let url = URL(string: UIApplication.openSettingsURLString),
             UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:]) { ok in
              result(ok)
            }
          } else {
            result(false)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
