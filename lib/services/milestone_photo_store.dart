import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v294 — User-captured milestone photos for the Progress tab.
///
/// The three milestone slots on the Progress tab (DAY 1 / DAY 30 /
/// DAY 60) previously rendered "TAKE" buttons that routed straight
/// to the full /scan flow. Bro pushed back: the user shouldn't have
/// to run a face-mesh + AI-render pass to drop a photo into a
/// milestone slot — they should just point the camera and shoot.
///
/// This service is the lightweight save / load for that quick
/// capture flow. ImagePicker hands us a temp file; we copy it into
/// the app's documents directory under `mirrorly/milestones/` with
/// a slot-tagged name, then stamp the absolute path into
/// SharedPreferences so the Progress strip can render it next
/// build. No scan record is created. No score is computed. Just a
/// photo on disk and a path in prefs.
class MilestonePhotoStore {
  MilestonePhotoStore._();

  /// SharedPreferences key for a specific milestone day. Days are
  /// the canonical slot numbers — 1 / 30 / 60. Any other value is
  /// rejected by [_keyFor] so a typo can't write a phantom slot.
  static String _keyFor(int day) {
    assert(day == 1 || day == 30 || day == 60,
      'milestone slot must be one of {1, 30, 60}');
    return 'milestone_photo_day_$day';
  }

  /// Folder under the app's documents directory where saved
  /// milestone photos live. Created on first save.
  static Future<Directory> _milestoneDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/mirrorly/milestones');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copy the user's freshly-captured photo into our durable
  /// documents directory and stamp the path in prefs. ImagePicker's
  /// returned file lives in a temp location iOS reclaims, so we
  /// re-host before recording. Returns the durable absolute path
  /// the caller should hand into Image.file widgets.
  static Future<String?> saveCapturedFile(int day, File tempFile) async {
    try {
      final dir = await _milestoneDir();
      // Stable name keyed to the slot so a re-capture overwrites
      // (the user is replacing the milestone photo, not stacking
      // a history of mid-day attempts).
      final dest = File('${dir.path}/day_$day.jpg');
      await tempFile.copy(dest.path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyFor(day), dest.path);
      return dest.path;
    } catch (_) {
      return null;
    }
  }

  /// Read the saved path for a milestone day. Returns null when
  /// nothing has been captured yet OR when the file on disk has
  /// been pruned (iOS occasionally evicts documents under storage
  /// pressure). Caller decides whether to fall back to the scan
  /// history's capturedImagePath.
  static Future<String?> loadPath(int day) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path  = prefs.getString(_keyFor(day));
      if (path == null || path.isEmpty) return null;
      if (!await File(path).exists()) {
        // File evicted — clear the stale pointer so next call
        // reads as "empty" instead of a broken path.
        await prefs.remove(_keyFor(day));
        return null;
      }
      return path;
    } catch (_) {
      return null;
    }
  }

  /// Eager loader for the Progress strip — reads all three slots
  /// in one pass. Map keys are the canonical slot days so the
  /// caller can do `paths[1]`, `paths[30]`, `paths[60]`.
  static Future<Map<int, String?>> loadAll() async {
    final p1  = await loadPath(1);
    final p30 = await loadPath(30);
    final p60 = await loadPath(60);
    return { 1: p1, 30: p30, 60: p60 };
  }

  /// Wipe a single slot. Useful for a future "retake" affordance —
  /// not wired into the UI yet but the file path is stable so
  /// re-capture already overwrites cleanly.
  static Future<void> clear(int day) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path  = prefs.getString(_keyFor(day));
      if (path != null) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
      await prefs.remove(_keyFor(day));
    } catch (_) {/* best-effort */}
  }
}
