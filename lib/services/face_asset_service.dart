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
      // Fast path — the stored path resolves directly. The common case.
      final file = File(path);
      if (await file.exists()) return await file.readAsBytes();

      // v274 — iOS container-UUID rescue. The path written at scan
      // time is absolute, including a `/var/mobile/Containers/Data/
      // Application/<UUID>/...` prefix unique to the install. iOS
      // can reassign that UUID across installs / iCloud restores /
      // device migrations even when the on-disk JPEG (and the
      // SharedPreferences scan record that names it) both survive.
      // When that happens the stored path points at a dead UUID
      // but the file is sitting in the CURRENT container's
      // documents/mirrorly/scans/ directory under the same
      // filename. Pull the basename off the dead path and look
      // for the file in the live docs dir before giving up.
      //
      // No other change anywhere — TryOnService, ChatScreen,
      // the Mirror tab all keep their existing call shape. They
      // just stop returning null for the UUID-drift case.
      final filename = path.split('/').last;
      if (filename.isNotEmpty && filename != path) {
        final dir = await getApplicationDocumentsDirectory();
        final rescued = File('${dir.path}/mirrorly/scans/$filename');
        if (await rescued.exists()) return await rescued.readAsBytes();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> exists(String? path) async {
    if (path == null || path.isEmpty) return false;
    if (await File(path).exists()) return true;
    // v274 — mirror the UUID rescue from loadScanImageBytes so
    // every "do we still have this scan?" call gets the same
    // recovery behaviour as the read path.
    try {
      final filename = path.split('/').last;
      if (filename.isNotEmpty && filename != path) {
        final dir = await getApplicationDocumentsDirectory();
        return File('${dir.path}/mirrorly/scans/$filename').exists();
      }
    } catch (_) {}
    return false;
  }

  /// Resolve a stored scan-image path to one that EXISTS on disk right
  /// now, applying the same iOS container-UUID rescue as
  /// [loadScanImageBytes]. Returns null if neither the stored absolute
  /// path nor the basename-in-current-docs fallback resolves, so callers
  /// can render a placeholder. Use this before any direct
  /// `Image.file(...)` of a scan photo: the raw stored path goes stale
  /// after an app update / restore when the container UUID changes —
  /// which is exactly why before/now photos "vanish" after updating.
  static Future<String?> resolvePath(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      if (await File(path).exists()) return path;
      final filename = path.split('/').last;
      if (filename.isNotEmpty && filename != path) {
        final dir = await getApplicationDocumentsDirectory();
        final rescued = '${dir.path}/mirrorly/scans/$filename';
        if (await File(rescued).exists()) return rescued;
      }
    } catch (_) {}
    return null;
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
