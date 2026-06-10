import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// Free, on-device OCR over Google ML Kit. Used by the RIZZ tab to
/// extract her message from a Hinge / Tinder / iMessage screenshot
/// without burning GPT vision tokens.
///
/// Returns the LAST 4-5 message bubbles' worth of text, joined with
/// newline. The model writes sharper replies when it sees just the
/// recent cadence — feeding it the whole convo dilutes the prompt.
class ScreenshotOcrService {
  static final _recognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  /// Extract the last bubbles of text from a screenshot path. The
  /// recognizer returns blocks bottom-to-top in screen space; we keep
  /// the last [keepBlocks] (5 by default) so the prompt focuses on
  /// her most recent message, not the whole conversation history.
  static Future<String> extractRecent(String imagePath,
      {int keepBlocks = 5}) async {
    final input = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(input);

    // Sort blocks top→bottom by Y, take the LAST keepBlocks (= the
    // most recent messages on screen). Bubble-by-bubble ordering is
    // platform-stable enough for chat UIs.
    final blocks = [...result.blocks]
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final recent = blocks.length <= keepBlocks
        ? blocks
        : blocks.sublist(blocks.length - keepBlocks);
    return recent
        .map((b) => b.text.trim())
        .where((t) => t.isNotEmpty)
        .join('\n')
        .trim();
  }

  /// Single OCR entry point that both the screenshot rizz screen AND
  /// the chat-with-Mirrorly screen call. Eliminates code drift between
  /// the two helpers — if OCR works on one it works on the other.
  ///
  /// Writes the bytes to an app-sandbox temp file via path_provider
  /// (NOT Directory.systemTemp — that resolves outside the iOS app
  /// sandbox and silently fails). Runs ML Kit with a 12s timeout so
  /// the UI never hangs forever. Returns '' on any failure path so
  /// callers can fall back to "ask me to paste what she said".
  static Future<String> extractFromBytes(Uint8List bytes,
      {int keepBlocks = 5}) async {
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/ocr_'
          '${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      try {
        final text = await extractRecent(path, keepBlocks: keepBlocks)
            .timeout(
              const Duration(seconds: 12),
              onTimeout: () => '',
            );
        return text;
      } finally {
        try { await file.delete(); } catch (_) {}
      }
    } catch (_) {
      return '';
    }
  }

  /// Release the native recognizer. Safe to skip — ML Kit reuses
  /// instances. Provided for explicit teardown if needed.
  static Future<void> dispose() async {
    await _recognizer.close();
  }
}
