import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Persists the user's scan image(s) to the app's documents directory so
/// they survive app restarts and can be loaded instantly for tryon requests,
/// chat context, progress-gallery previews, etc.
///
/// Images are stored as JPEG in `<docs>/mirrorly/scans/<id>.jpg`.
class FaceAssetService {
  static Future<String> saveScanImage({
    required String scanId,
    required Uint8List bytes,
  }) async {
    final dir = await _scansDir();
    final file = File('${dir.path}/$scanId.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<Uint8List?> loadScanImageBytes(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> exists(String? path) async {
    if (path == null || path.isEmpty) return false;
    return File(path).exists();
  }

  static Future<void> deleteScanImage(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Wipe every saved scan JPEG. Used by Settings → Delete all data.
  /// Safe to call even if the directory never existed.
  static Future<void> purgeAll() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final d = Directory('${base.path}/mirrorly/scans');
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  static Future<Directory> _scansDir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/mirrorly/scans');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }
}
