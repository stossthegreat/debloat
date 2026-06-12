import 'package:flutter/services.dart';

/// MethodChannel bridge to the native iOS settings deep-link AND a tiny
/// SharedPreferences-backed flag for "did the user finish the onboarding
/// once". The Flutter side never needs to know whether the keyboard is
/// actually installed — that's an iOS-only state and the OS doesn't
/// expose it. Best we can do is record that they SAW the onboarding so
/// the entry tile can stop nagging them.
class KeyboardInstallService {
  static const _channel = MethodChannel('com.mirrorly.app/keyboard');

  /// Opens iOS Settings → ImHim → Keyboards on iOS, or the system
  /// app settings on Android. AppDelegate handles iOS; Android falls
  /// through to a no-op (until/unless we ship an IME on Android).
  static Future<void> openSystemKeyboardSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } catch (_) {
      // Best-effort — if the method channel isn't wired (debug builds
      // without AppDelegate update, simulator quirks) we silently
      // no-op rather than throw.
    }
  }
}
