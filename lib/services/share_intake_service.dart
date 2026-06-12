import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge between the iOS Share Extension and the Flutter app.
///
/// On the iOS side, `ShareViewController` writes the shared screenshot
/// to the App Group container and deep-links Runner via `imhim://rizz`.
/// AppDelegate notices the URL, posts an `onSharedScreenshot` event
/// over the `com.mirrorly.app/share_intake` MethodChannel, and exposes
/// a `pullPendingShare` method that returns the bytes + timestamp.
///
/// This service:
///   - Listens for the `onSharedScreenshot` event from native.
///   - Lets the Flutter side ask for the pending payload at any
///     time (cold-start, hot resume, manual refresh).
///   - Exposes a broadcast stream of [SharedScreenshot] so the app's
///     root widget can navigate to the Rizz screen as soon as a new
///     share lands.
class ShareIntakeService {
  ShareIntakeService._();
  static final ShareIntakeService instance = ShareIntakeService._();

  static const _channel = MethodChannel('com.mirrorly.app/share_intake');

  final StreamController<SharedScreenshot> _controller =
      StreamController<SharedScreenshot>.broadcast();

  /// Fires every time the Share Extension hands us a fresh screenshot.
  Stream<SharedScreenshot> get stream => _controller.stream;

  bool _wired = false;

  /// Hook up the platform listener. Safe to call multiple times — the
  /// MethodChannel handler is replaced, never duplicated. Call once
  /// during app boot (see main.dart).
  void wire() {
    if (_wired) return;
    _wired = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedScreenshot') {
        // The native side has just written a new payload — pull it
        // synchronously and emit on the stream.
        final shot = await pullPending();
        if (shot != null) _controller.add(shot);
      }
      return null;
    });
  }

  /// Reads any pending share payload off the App Group. Returns null
  /// if none is waiting. Used both by the MethodChannel listener
  /// above AND by the splash/boot sequence so a cold-start launched
  /// via the Share Extension picks up the screenshot too.
  Future<SharedScreenshot?> pullPending() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'pullPendingShare',
      );
      if (raw == null) return null;
      final bytes = raw['bytes'] as Uint8List?;
      final ts    = (raw['timestamp'] as num?)?.toDouble() ?? 0;
      if (bytes == null || bytes.isEmpty) return null;
      return SharedScreenshot(bytes: bytes, timestampEpochSeconds: ts);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ShareIntake] pullPending failed: $e');
      }
      return null;
    }
  }
}

/// One screenshot handed across from the Share Extension.
class SharedScreenshot {
  final Uint8List bytes;
  final double timestampEpochSeconds;
  const SharedScreenshot({
    required this.bytes,
    required this.timestampEpochSeconds,
  });
}

/// Wrapper class used as the GoRouter `extra` payload when navigating
/// to /rizz with a pre-loaded screenshot from the iOS Share Extension.
/// Kept as a distinct type so the route can disambiguate it from the
/// existing RizzCardAction `extra` shape used by in-app navigation.
class SharedScreenshotPayload {
  final Uint8List bytes;
  const SharedScreenshotPayload({required this.bytes});
}
