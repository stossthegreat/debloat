import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

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

  /// Release the native recognizer. Safe to skip — ML Kit reuses
  /// instances. Provided for explicit teardown if needed.
  static Future<void> dispose() async {
    await _recognizer.close();
  }
}
