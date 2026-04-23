import 'package:flutter_test/flutter_test.dart';
import 'package:mirror/models/protocol.dart';

/// Exercises the streak state machine on [Protocol.withTodayChecked] across
/// every branch that matters for retention correctness.
///
/// We override the protocol's `startedAt` so we can simulate "today is day
/// N" and "last check-in was day M" without actually waiting. `lastCheckIn`
/// gets set explicitly via a [_copy] helper to drop check-ins into the past.

void main() {
  group('streak math', () {
    test('fresh protocol: first check-in sets streak to 1', () {
      final p = _protocolStartedDaysAgo(0);
      final out = p.withTodayChecked();
      expect(out.currentStreak, 1);
      expect(out.longestStreak, 1);
      expect(out.completedDays, {1});
      expect(out.freezeDays, isEmpty);
    });

    test('same-day double-tap is idempotent', () {
      final p = _protocolStartedDaysAgo(0).withTodayChecked();
      final again = p.withTodayChecked();
      expect(again.currentStreak, p.currentStreak);
      expect(again.completedDays, p.completedDays);
    });

    test('yesterday → today increments the streak', () {
      final p = _protocolStartedDaysAgo(1)._copy(
        currentStreak: 1,
        longestStreak: 1,
        lastCheckIn: _yesterday(),
        completedDays: {1},
      );
      final out = p.withTodayChecked();
      expect(out.currentStreak, 2);
      expect(out.longestStreak, 2);
    });

    test('one missed day in first week resets — no freeze', () {
      // Protocol started 2 days ago, user checked in on day 1, missed day
      // 2, now checking in on day 3. currentDay=3 → first week → no
      // freezes available → reset to 1.
      final p = _protocolStartedDaysAgo(2)._copy(
        currentStreak: 1,
        longestStreak: 1,
        lastCheckIn: _twoDaysAgo(),
        completedDays: {1},
      );
      expect(p.currentDay, 3);
      expect(p.freezesAvailable, 0);
      final out = p.withTodayChecked();
      expect(out.currentStreak, 1);
      expect(out.longestStreak, 1);
      expect(out.freezeDays, isEmpty);
    });

    test('one missed day past day 7 consumes a freeze and keeps streak', () {
      // day 10, user has a 9-day streak, missed day 9, now day 10.
      final p = _protocolStartedDaysAgo(9)._copy(
        currentStreak: 8,
        longestStreak: 8,
        lastCheckIn: _twoDaysAgo(),
        completedDays: {1, 2, 3, 4, 5, 6, 7, 8},
      );
      expect(p.currentDay, 10);
      expect(p.freezesAvailable, 1);
      final out = p.withTodayChecked();
      expect(out.currentStreak, 9);
      expect(out.longestStreak, 9);
      expect(out.freezeDays, {9});
    });

    test('two misses in a week past day 7: second resets (one freeze/week)', () {
      // Protocol day 15. User used a freeze at day 12 already (within the
      // 7-day window). Now they miss day 14 and come back on 15 — freeze
      // is NOT available, so streak resets.
      final p = _protocolStartedDaysAgo(14)._copy(
        currentStreak: 12,
        longestStreak: 12,
        lastCheckIn: _twoDaysAgo(),
        completedDays: {for (var i = 1; i <= 13; i++) i}..remove(12),
        freezeDays: {12},
      );
      expect(p.currentDay, 15);
      expect(p.freezesAvailable, 0, reason: 'freeze at day 12 is within the rolling 7-day window');
      final out = p.withTodayChecked();
      expect(out.currentStreak, 1);
      expect(out.freezeDays, {12}, reason: 'previous freeze not auto-repeated');
    });

    test('two-day gap (3+ days) always resets — one freeze never covers 2', () {
      // day 20, last check-in was day 16 (4-day gap).
      final p = _protocolStartedDaysAgo(19)._copy(
        currentStreak: 16,
        longestStreak: 16,
        lastCheckIn: DateTime.now().subtract(const Duration(days: 4)),
        completedDays: {for (var i = 1; i <= 16; i++) i},
      );
      expect(p.currentDay, 20);
      expect(p.freezesAvailable, 1);
      final out = p.withTodayChecked();
      expect(out.currentStreak, 1,
        reason: 'a 4-day gap exceeds one freeze; must reset');
      expect(out.freezeDays, isEmpty,
        reason: 'no freeze should be consumed when gap is too large');
    });

    test('longestStreak never decreases', () {
      // Build up to a 12-day streak, then break it.
      var p = _protocolStartedDaysAgo(30)._copy(
        currentStreak: 12,
        longestStreak: 12,
        lastCheckIn: DateTime.now().subtract(const Duration(days: 5)),
        completedDays: {for (var i = 1; i <= 12; i++) i},
      );
      p = p.withTodayChecked();
      expect(p.currentStreak, 1, reason: 'broken');
      expect(p.longestStreak, 12, reason: 'longest is preserved');
    });

    test('streakStatus transitions: live → atRisk → broken', () {
      final live = _protocolStartedDaysAgo(5)._copy(
        currentStreak: 5, lastCheckIn: DateTime.now(),
      );
      expect(live.streakStatus, StreakStatus.live);
      expect(live.effectiveStreak, 5);

      final atRisk = live._copy(lastCheckIn: _yesterday());
      expect(atRisk.streakStatus, StreakStatus.atRisk);
      expect(atRisk.effectiveStreak, 5,
        reason: 'yesterday-still-counts — gives the user today to save it');

      final broken = live._copy(lastCheckIn: _twoDaysAgo());
      expect(broken.streakStatus, StreakStatus.broken);
      expect(broken.effectiveStreak, 0);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Harness
// ─────────────────────────────────────────────────────────────────────────────

Protocol _protocolStartedDaysAgo(int daysAgo) => Protocol(
  id: 'test',
  startedAt: DateTime.now().subtract(Duration(days: daysAgo)),
  lengthDays: 60,
  title: 'Test',
  targetAxis: 'Jaw definition',
  summary: 's',
  dailyTasks: const [],
  milestones: const [],
  completedDays: const {},
);

DateTime _yesterday()   => DateTime.now().subtract(const Duration(days: 1));
DateTime _twoDaysAgo()  => DateTime.now().subtract(const Duration(days: 2));

extension _ProtocolCopy on Protocol {
  Protocol _copy({
    Set<int>? completedDays,
    DateTime? lastCheckIn,
    int? currentStreak,
    int? longestStreak,
    Set<int>? freezeDays,
  }) => Protocol(
    id: id, startedAt: startedAt, lengthDays: lengthDays, title: title,
    targetAxis: targetAxis, summary: summary, dailyTasks: dailyTasks,
    milestones: milestones,
    completedDays: completedDays ?? this.completedDays,
    lastCheckIn:   lastCheckIn   ?? this.lastCheckIn,
    currentStreak: currentStreak ?? this.currentStreak,
    longestStreak: longestStreak ?? this.longestStreak,
    freezeDays:    freezeDays    ?? this.freezeDays,
  );
}
