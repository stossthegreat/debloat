import 'debloat_checklist_service.dart';

/// THE DAILY MISSION ENGINE — a thin adapter over the debloat
/// checklist.
///
/// Debloat OS has ONE daily job: run the debloat system. The mission
/// set for any day IS the checklist — one mission per item, done-state
/// read straight from DebloatChecklistService. StreakService feeds its
/// consistency math from this (done ÷ offered over the rolling week),
/// so the Ascend tab's CONSISTENCY bar measures exactly how fully the
/// user executes the daily system.
class DailyMissionService {
  /// Today's mission set with completion state — one entry per
  /// checklist item, same order the Debloat tab renders.
  static Future<List<DailyMission>> loadToday() async {
    final done = await DebloatChecklistService.loadToday();
    return [
      for (final item in DebloatChecklistService.items)
        DailyMission(id: item.id, done: done.contains(item.id)),
    ];
  }
}

/// One mission in today's set — the stable item id plus whether the
/// user has completed it today. UI copy lives in the Ascend screen.
class DailyMission {
  final String id;
  final bool done;
  const DailyMission({required this.id, required this.done});
}
