import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/protocol.dart';
import '../../models/scan_record.dart' show ScanRecord;
import '../../services/ascension_service.dart';
import '../../services/daily_mission_service.dart';
import '../../services/share_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/mirrorly_wordmark.dart';
import '../../widgets/progress/face_evolution_card.dart';

/// v281 — ASCENSION home tab.
///
/// Total rebuild. The previous AscendScreen MEASURED progress (three
/// pillar score cards, percentages, deltas). Bro:
///
///   > Your current Progress screen measures.
///   > A retention screen motivates.
///   > Those are completely different jobs.
///
/// New job: answer one question — "Who do I become if I finish?" —
/// and surface the fear of not finishing alongside the status of
/// who they're becoming.
///
/// Seven sections, in order:
///   1. HERO — massive flame ring, DAY N / 60, identity rank inside,
///      days-remaining + tagline below.
///   2. COST OF QUITTING — rotating fear-card. Day-anchored copy so
///      it cycles instead of going stale.
///   3. TODAY'S ASCENSION — 5 daily MISSIONS (not tasks). 4/5 COMPLETE
///      header, each tick visibly feeds the flame.
///   4. RANK PROGRESSION — Observer → Initiate → Contender →
///      Dangerous → Magnetic → Debloat OS. Status ladder, not stats.
///   5. ASCENSION RECORD — timeline of milestones. "This becomes
///      their story."
///   6. STREAK — huge flame number. Users protect streaks, not scores.
///   7. FINAL FORM — Day-60 unlock card, locked + blurred. Anticipation
///      IS the retention.
class AscendScreen extends StatefulWidget {
  /// Switch the bottom-nav to a specific tab. 0=Scan, 1=Debloat,
  /// 2=Mirror, 3=Ascend.
  final ValueChanged<int> onJumpToTab;

  /// Pull-to-refresh hook — re-reads the home-screen state (scores,
  /// streak, mission flags) so Ascend updates without a tab switch.
  /// Same gesture the Looks tab uses.
  final Future<void> Function()? onRefresh;

  /// v371 — EVERY committed protocol, keyed by axis. Drives the
  /// one-row-per-protocol daily mission list.
  final Map<String, Protocol> activeProtocols;

  /// Active 60-day protocol, if any. Drives Day-N, streak,
  /// completedToday, and rank progression.
  final Protocol? protocol;

  /// Latest scan in history (used for the Ascension Record timeline).
  final ScanRecord? latest;

  /// All scans the user has logged (chronological → reverse-chronological
  /// in the timeline). Empty list when fresh-install.
  final List<ScanRecord> allScans;

  /// Current daily streak from StreakService (via home_screen). Used in
  /// the masthead flame + the streak panel.
  final int dayStreak;

  /// Longest daily streak the user has ever reached (StreakService).
  final int longestStreak;

  /// Earned ascension day (total days shown up, 1..60) from
  /// StreakService.progress via home_screen. Drives the DAY N/60 flame
  /// ring, the rank ladder, and the final-form unlock.
  final int ascensionDay;

  /// Rolling 7-day mission-completion consistency (0..100) from
  /// StreakService.progress. The 30% CONSISTENCY component of the
  /// DEBLOAT score.
  final int consistency;

  /// Today's mission set from the quota-aware DailyMissionService —
  /// protocol anchor + rotating slots that only offer what the user's
  /// weekly allowances can actually complete. Empty → legacy fixed five
  /// (first frame / fallback).
  final List<DailyMission> dailyMissions;

  /// Did the user complete their protocol check-in today?
  final bool looksDoneToday;

  /// v289 — latest Looks pillar score, 0-100 raw scale. Feeds the
  /// DEBLOAT-score formula (Looks + Consistency — nothing else).
  final int looksScore100;

  const AscendScreen({
    super.key,
    required this.onJumpToTab,
    this.onRefresh,
    this.longestStreak = 0,
    this.protocol,
    this.activeProtocols = const {},
    this.latest,
    this.allScans = const [],
    this.dayStreak = 0,
    this.ascensionDay = 1,
    this.consistency = 0,
    this.dailyMissions = const [],
    this.looksDoneToday = false,
    this.looksScore100 = 0,
  });

  @override
  State<AscendScreen> createState() => _AscendScreenState();
}

class _AscendScreenState extends State<AscendScreen> {
  /// Cached weekly delta — the diff between the user's current
  /// DEBLOAT score and the prior weekly snapshot. Pre-loaded on first
  /// build so the score hero can render the arrow synchronously.
  int _weeklyDelta = 0;
  bool _deltaLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadDeltaAndSnapshot();
  }

  /// Read whatever prior snapshot the prefs have, compute the
  /// delta, then write today's score back so the next visit has a
  /// fresh reference point. Idempotent per calendar day — multiple
  /// taps on the tab don't move the "prior" slot.
  Future<void> _loadDeltaAndSnapshot() async {
    final score = AscensionService.debloatScoreFromComponents(
      looks:       widget.looksScore100,
      consistency: widget.consistency,
    );
    final delta = await AscensionService.weeklyDeltaFor(score);
    await AscensionService.snapshotTodayScore(score);
    if (!mounted) return;
    setState(() {
      _weeklyDelta = delta;
      _deltaLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final day            = widget.ascensionDay;
    final daysLeft       = AscensionService.daysRemainingFor(day);
    final rank           = AscensionService.rankFor(day);
    final consistency    = widget.consistency;
    final debloatScore     = AscensionService.debloatScoreFromComponents(
      looks:       widget.looksScore100,
      consistency: consistency,
    );
    final missions       = _buildMissions();
    final missionsDone   = missions.where((m) => m.done).length;
    final todayMsg       = AscensionService.todayMessageFor(
      day: day, streak: widget.dayStreak);
    final longestStreak  = widget.longestStreak > widget.dayStreak
        ? widget.longestStreak
        : widget.dayStreak;

    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.red,
          backgroundColor: AppColors.surface1,
          onRefresh: () async {
            await widget.onRefresh?.call();
            await _loadDeltaAndSnapshot();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: Sp.xl),
            children: [
            // v292 — masthead matches Looks / Rizz: wordmark, then
            // the streak flame (gated > 0 like the other tabs so a
            // brand-new user doesn't see a dead "0 day" chip),
            // progress chart, settings cog. Bro: "add the progress
            // and streak icons on rizz and ascend."
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const MirrorlyWordmark(fontSize: 34),
                  const Spacer(),
                  if (widget.dayStreak > 0) ...[
                    _MastheadStreakBadge(days: widget.dayStreak),
                    const SizedBox(width: 8),
                  ],
                  _MastheadProgressChip(
                    onTap: () => context.push('/progress')),
                  const SizedBox(width: 8),
                  _MastheadSettingsCog(
                    onTap: () => context.push('/settings')),
                ],
              ),
            ),

            const SizedBox(height: Sp.lg),

            // ── FACE EVOLUTION — the premium, addictive centrepiece.
            // Replaces the old Ascension Record + Drained Certified
            // sections. Reuses the retained per-scan selfies to let the
            // user scrub + share their face getting leaner over time.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: FaceEvolutionCard(scans: widget.allScans),
            ).animate().fadeIn(duration: 500.ms)
              .slideY(begin: 0.03, end: 0, curve: Curves.easeOut),

            const SizedBox(height: Sp.lg),

            // ── 1 — HERO. Big flame ring, day count, rank inside.
            _FlameHero(
              day:       day,
              total:     AscensionService.totalDays,
              rank:      rank,
              daysLeft:  daysLeft,
            ).animate().fadeIn(duration: 480.ms)
              .scale(begin: const Offset(0.92, 0.92),
                end: const Offset(1, 1), curve: Curves.easeOutBack),

            const SizedBox(height: Sp.lg),

            // ── 2 — DEBLOAT SCORE. One number, one character to
            // level. Built from Looks + Consistency — nothing else.
            _MirrorlyScoreHero(
              score:        debloatScore,
              delta:        _weeklyDelta,
              deltaReady:   _deltaLoaded,
              looks:        widget.looksScore100,
              consistency:  consistency,
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

            const SizedBox(height: Sp.lg),

            // ── 2b — SCAN MILESTONE. v290 — only renders inside the
            // two scan windows (Day 22-35 and Day 56-60). Bro's spec:
            // three scans across the protocol (start / mid / final)
            // give us the before/after evidence the certificate is
            // built from. The card prompts the scan in the right
            // window, then flips to a "captured" pill once the user
            // has logged a scan inside it. Days outside both windows
            // collapse the section to zero height — no clutter.
            if (_scanMilestone(day) != null) ...[
              _ScanMilestoneCard(
                milestone: _scanMilestone(day)!,
                done:      _scanLoggedInWindow(_scanMilestone(day)!.from,
                                               _scanMilestone(day)!.to),
                onTap:     () => context.push('/scan'),
              ).animate().fadeIn(delay: 240.ms, duration: 400.ms),
              const SizedBox(height: Sp.lg),
            ],

            // ── 3 — TODAY'S MESSAGE. Single rotating identity line
            // (v289 replaced Cost of Quitting — fear was a one-shot
            // drug, identity is the loop).
            if (todayMsg.isNotEmpty) ...[
              _TodayMessageCard(line: todayMsg)
                .animate().fadeIn(delay: 280.ms, duration: 400.ms),
              const SizedBox(height: Sp.lg),
            ],

            // ── 4 — TODAY'S ASCENSION. Pillar-mapped missions.
            _MissionsPanel(
              missions: missions,
              done:     missionsDone,
            ).animate().fadeIn(delay: 360.ms, duration: 400.ms),

            const SizedBox(height: Sp.lg),

            // ── 5 — RANK PROGRESSION. The identity ladder.
            _RankProgression(currentDay: day)
              .animate().fadeIn(delay: 440.ms, duration: 400.ms),

            const SizedBox(height: Sp.lg),

            // ── 6 — STREAK. Hero treatment per the consultant.
            _StreakPanel(
              current: widget.dayStreak,
              longest: longestStreak,
            ).animate().fadeIn(delay: 520.ms, duration: 400.ms),

            // ── ASCENSION RECORD + DRAINED CERTIFIED removed — replaced
            //    by the FACE EVOLUTION card at the top of this tab.

            const SizedBox(height: Sp.xl),
          ],
        ),
        ),
      ),
    );
  }

  // ── Mission builder ─────────────────────────────────────────────────────
  //
  // THE ASCENSION IS THE SYSTEM. Row one is always the daily debloat
  // checklist (the core loop); a row per committed protocol follows,
  // each deep-linking into its check-in screen. Every done-flag is
  // per-day. Copy stays in the leveling-up voice.
  List<AscendMission> _buildMissions() {
    final w = widget;

    // Daily checklist row — done/offered from DailyMissionService via
    // home_screen. The mission list mirrors the checklist items, so
    // count them here.
    final clDone  = w.dailyMissions.where((m) => m.done).length;
    final clTotal = w.dailyMissions.length;
    final checklistRow = AscendMission(
      title: clTotal > 0
          ? 'RUN THE DEBLOAT SYSTEM · $clDone/$clTotal'
          : 'RUN THE DEBLOAT SYSTEM',
      hint: clTotal > 0 && clDone >= clTotal
          ? 'fully drained. see it tomorrow morning.'
          : 'the daily checklist. every tick shows in the mirror.',
      done: clTotal > 0 && clDone >= clTotal,
      // Debloat tab (index 2) — where the checklist lives.
      onTap: () => w.onJumpToTab(2),
    );

    final active = w.activeProtocols;
    if (active.isNotEmpty) {
      return [
        checklistRow,
        for (final p in active.values)
          AscendMission(
            title: '${p.targetAxis.toUpperCase()} · LOG DAY ${p.currentDay}',
            hint: p.completedToday
                ? 'banked. another day deeper.'
                : 'today\'s reps. the work that compounds.',
            done: p.completedToday,
            onTap: () => context.push('/protocol', extra: {
              'pulldown': p.targetAxis,
            }),
          ),
      ];
    }

    // No protocol committed yet — checklist + commit.
    return [
      checklistRow,
      AscendMission(
        title: 'COMMIT THE DEBLOAT PROTOCOL',
        hint: 'the 60-day run. tap to start it.',
        done: false,
        // The Mirror tab is gone (now Food) — commit the protocol on
        // the dedicated protocol screen directly.
        onTap: () => context.push('/protocol'),
      ),
    ];
  }

  /// v290 — which scan milestone (if any) is currently in window
  /// for the user. Returns null outside both windows so the Ascend
  /// surface collapses the prompt section cleanly. The Day-1 scan
  /// happens at onboarding so no Day-1 prompt is surfaced here.
  _ScanMilestone? _scanMilestone(int day) {
    if (day >= 22 && day <= 35) {
      return const _ScanMilestone(
        kind:     _ScanMilestoneKind.mid,
        from:     22,
        to:       35,
        eyebrow:  'MID-PROTOCOL SCAN · DAY 28',
        title:    'Capture the delta.',
        subtitle: 'A new scan locks in the week-4 receipt and refreshes '
                  'your DEBLOAT score.',
        doneCopy: 'Mid-protocol scan locked in.',
        cta:      'Take the scan',
      );
    }
    if (day >= 56 && day <= 60) {
      return const _ScanMilestone(
        kind:     _ScanMilestoneKind.finalScan,
        from:     56,
        to:       60,
        eyebrow:  'FINAL SCAN · DAY 60',
        title:    'Your before / after lands now.',
        subtitle: 'The Day-60 scan unlocks the DRAINED · CERTIFIED card. '
                  'This is the receipt people share.',
        doneCopy: 'Final scan logged. Certificate is ready.',
        cta:      'Take the final scan',
      );
    }
    return null;
  }

  /// Returns true if any scan in the user's history landed inside
  /// the given protocol-day window (inclusive). Used to flip the
  /// milestone card from prompt → captured pill.
  bool _scanLoggedInWindow(int from, int to) {
    final p = widget.protocol;
    if (p == null) return false;
    for (final s in widget.allScans) {
      final dayAt = (s.takenAt.difference(p.startedAt).inDays + 1)
          .clamp(1, 999);
      if (dayAt >= from && dayAt <= to) return true;
    }
    return false;
  }

  /// v291 — Generate the DRAINED · CERTIFIED Day-60 share card.
  /// Collects (LOOKS ONLY since v380):
  ///   - BEFORE photo: first scan in history (chronological)
  ///   - AFTER photo:  last scan in history (the Day-60-window scan)
  ///   - DEBLOAT SCORE arc: composite at Day-1 conditions
  ///     (first scan's looks, consistency = 0) vs the current composite
  ///   - LOOKS arc:  first scan score → latest scan score
  ///   - CONSISTENCY arc: 0 → current consistency
  /// All data comes from existing on-device stores so the card can
  /// generate offline. Falls back to safe defaults if any history
  /// is missing so the user can always share something.
  Future<void> _generateCertificate() async {
    if (!mounted) return;
    final scans = [...widget.allScans]
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    final firstScan = scans.isNotEmpty ? scans.first : null;
    final lastScan  = scans.isNotEmpty ? scans.last  : null;

    // Looks (out of 100) — direct off the scan record.
    final int looksStart = firstScan?.score ?? 0;
    final int looksEnd   = lastScan?.score  ?? 0;

    // Consistency arc — 0 on Day 1 always; current today = the live
    // rolling-7-day consistency the tab already shows.
    final int consistencyEnd = widget.consistency;
    const int consistencyStart = 0;

    // DEBLOAT SCORE arc — same formula AscensionService runs in the
    // hero so the certificate reads as continuous with the live tab.
    final int scoreStart = AscensionService.debloatScoreFromComponents(
      looks:       looksStart,
      consistency: consistencyStart,
    );
    final int scoreEnd = AscensionService.debloatScoreFromComponents(
      looks:       looksEnd,
      consistency: consistencyEnd,
    );

    if (!mounted) return;
    await ShareService.shareCertificate(
      context:          context,
      beforePhotoPath:  firstScan?.capturedImagePath,
      afterPhotoPath:   lastScan?.capturedImagePath,
      scoreStart:       scoreStart,
      scoreEnd:         scoreEnd,
      looksStart:       looksStart,
      looksEnd:         looksEnd,
      consistencyStart: consistencyStart,
      consistencyEnd:   consistencyEnd,
    );
  }

  // ── Milestone builder ────────────────────────────────────────────────────
  //
  // Real records, derived from existing data. Bro: "This becomes
  // their story." For v1 we surface:
  //   - Protocol start ("DAY 1 — You committed.")
  //   - Each completed scan ("DAY N — Rescan logged.")
  //   - Streak milestones (3, 7, 14, 30 day flags)
  //   - Today's day count (always last entry, "DAY N — Today.")
  // Sorted reverse-chronological so the latest action is at the top
  // of the visible list.
  List<AscendMilestone> _buildMilestones() {
    final out = <AscendMilestone>[];
    final p   = widget.protocol;
    if (p != null) {
      out.add(AscendMilestone(
        day:    1,
        title:  'You committed',
        detail: 'Day 1 of the ${p.lengthDays}-day ascension.',
      ));
      // Streak flags
      for (final mark in const [3, 7, 14, 21, 30, 45, 60]) {
        if (p.effectiveStreak >= mark) {
          out.add(AscendMilestone(
            day:    mark,
            title:  '$mark-day streak',
            detail: 'You showed up $mark days in a row.',
          ));
        }
      }
    }
    // Scan history — newest at the top of this loop; we'll sort below.
    for (final s in widget.allScans.take(8)) {
      final dayAt = p == null
          ? 1
          : (s.takenAt.difference(p.startedAt).inDays + 1).clamp(1, 999);
      out.add(AscendMilestone(
        day:    dayAt,
        title:  'Scan logged',
        detail: 'Score ${s.score} · ${_humanDate(s.takenAt)}',
      ));
    }
    out.sort((a, b) => b.day.compareTo(a.day));
    return out;
  }

  static String _humanDate(DateTime t) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${t.day} ${months[t.month - 1]}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SECTION 1 — FLAME HERO
// ═══════════════════════════════════════════════════════════════════════════

/// Big flame + ring. Day-N / total-N inside, identity rank label
/// directly under, days-remaining + rank tagline beneath that.
class _FlameHero extends StatefulWidget {
  final int day;
  final int total;
  final AscendRank rank;
  final int daysLeft;
  const _FlameHero({
    required this.day,
    required this.total,
    required this.rank,
    required this.daysLeft,
  });
  @override
  State<_FlameHero> createState() => _FlameHeroState();
}

class _FlameHeroState extends State<_FlameHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }
  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final progress = (widget.day / widget.total).clamp(0.0, 1.0);
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) {
                final t = Curves.easeInOut.transform(_pulse.value);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer pulse ring
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.red.withValues(alpha: 0.30 + 0.20 * t),
                            blurRadius: 60 + 24 * t,
                            spreadRadius: 4 + 4 * t,
                          ),
                        ],
                      ),
                    ),
                    // Progress ring
                    CustomPaint(
                      size: Size.infinite,
                      painter: _ProgressRingPainter(progress: progress),
                    ),
                    // Inner flame disc
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppColors.red,
                              AppColors.red.withValues(alpha: 0.65),
                              const Color(0xFF3A0A0E),
                            ],
                            stops: const [0.0, 0.55, 1.0],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.red.withValues(alpha: 0.55),
                              blurRadius: 40 + 12 * t,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('DAY',
                                style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 14, letterSpacing: 4,
                                  fontWeight: FontWeight.w900,
                                )),
                              const SizedBox(height: 6),
                              Text('${widget.day}',
                                style: GoogleFonts.spaceGrotesk(
                                  color: Colors.white,
                                  fontSize: 96, height: 1,
                                  letterSpacing: -3,
                                  fontWeight: FontWeight.w900,
                                  
                                )),
                              const SizedBox(height: 2),
                              Text('/ ${widget.total}',
                                style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.75),
                                  fontSize: 14, letterSpacing: 2,
                                  fontWeight: FontWeight.w700,
                                )),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: Sp.md),
        Text(widget.rank.label,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: AppColors.red,
            fontSize: 14, letterSpacing: 4,
            fontWeight: FontWeight.w900,
          )),
        const SizedBox(height: 4),
        Text(
          widget.daysLeft == 0
            ? 'You did it. Day 60.'
            : '${widget.daysLeft} day${widget.daysLeft == 1 ? "" : "s"} remaining',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 13, letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Sp.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            widget.rank.tagline,
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              color: AppColors.textPrimary,
              fontSize: 18, height: 1.35,
              letterSpacing: -0.4,
              
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double progress;
  _ProgressRingPainter({required this.progress});
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 4;
    final track = Paint()
      ..color = AppColors.surface3.withValues(alpha: 0.55)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, track);

    final fill = Paint()
      ..shader = const SweepGradient(
        colors: [Color(0xFF22D3EE), Color(0xFF7DF9FF), Color(0xFF22D3EE)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final sweep = (2 * math.pi) * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      fill,
    );
  }
  @override
  bool shouldRepaint(covariant _ProgressRingPainter old) =>
      old.progress != progress;
}

// ═══════════════════════════════════════════════════════════════════════════
//  SECTION 2 — COST OF QUITTING
// ═══════════════════════════════════════════════════════════════════════════

/// v289 — DEBLOAT SCORE hero. The composite that levels the whole
/// app into one character. Hero number in red, weekly delta arrow
/// underneath, three component pillars stacked below as the
/// "built from" credit row. Sits directly under the flame so the
/// user reads day + score as one unit.
class _MirrorlyScoreHero extends StatelessWidget {
  final int score;
  final int delta;
  final bool deltaReady;
  final int looks;
  final int consistency;
  const _MirrorlyScoreHero({
    required this.score,
    required this.delta,
    required this.deltaReady,
    required this.looks,
    required this.consistency,
  });

  @override
  Widget build(BuildContext context) {
    final deltaText = !deltaReady
        ? '—'
        : delta == 0
            ? '+0 this week'
            : delta > 0
                ? '↑ +$delta this week'
                : '↓ $delta this week';
    final deltaColor = !deltaReady || delta == 0
        ? AppColors.textTertiary
        : delta > 0
            ? AppColors.signalGreen
            : AppColors.signalAmber;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(Rd.lg),
          border: Border.all(
            color: AppColors.red.withValues(alpha: 0.22), width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text('DEBLOAT SCORE',
              style: GoogleFonts.inter(
                color: AppColors.red,
                fontSize: 10.5, letterSpacing: 3.2,
                fontWeight: FontWeight.w900,
              )),
            const SizedBox(height: 6),
            Text('$score',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontSize: 72, height: 1,
                letterSpacing: -2.4,
                fontWeight: FontWeight.w900,
                
              )),
            const SizedBox(height: 6),
            Text(deltaText,
              style: GoogleFonts.inter(
                color: deltaColor,
                fontSize: 12.5, letterSpacing: 1.4,
                fontWeight: FontWeight.w800,
              )),
            const SizedBox(height: 16),
            const Divider(height: 1, thickness: 0.5,
              color: AppColors.divider),
            const SizedBox(height: 14),
            Text('BUILT FROM',
              style: GoogleFonts.inter(
                color: AppColors.textTertiary,
                fontSize: 9, letterSpacing: 2.4,
                fontWeight: FontWeight.w800,
              )),
            const SizedBox(height: 10),
            // v371 — GAME retired from the score (looks pivot): the
            // score is built from LOOKS + CONSISTENCY only.
            _MirrorlyComponentRow(label: 'Looks',       value: looks,        accent: AppColors.measure),
            const SizedBox(height: 6),
            _MirrorlyComponentRow(label: 'Consistency', value: consistency,  accent: AppColors.red),
          ],
        ),
      ),
    );
  }
}

class _MirrorlyComponentRow extends StatelessWidget {
  final String label;
  final int value;
  final Color accent;
  const _MirrorlyComponentRow({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final width = (value / 100).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(label,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 12.5, letterSpacing: 0.4,
              fontWeight: FontWeight.w700,
            )),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Stack(
              children: [
                Container(
                  height: 5,
                  color: AppColors.surface3.withValues(alpha: 0.55),
                ),
                FractionallySizedBox(
                  widthFactor: width,
                  child: Container(
                    height: 5,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 32,
          child: Text('$value',
            textAlign: TextAlign.right,
            style: GoogleFonts.spaceGrotesk(
              color: AppColors.textPrimary,
              fontSize: 13, letterSpacing: 0.3,
              fontWeight: FontWeight.w800,
            )),
        ),
      ],
    );
  }
}

/// v290 — Scan milestone window descriptor. Two windows in the
/// protocol — mid (Day 22-35) and final (Day 56-60) — each prompts
/// the user to capture a new scan so the certificate at Day 60 has
/// three honest reference points: start, mid, final. Outside the
/// windows the card collapses entirely so the surface stays clean.
enum _ScanMilestoneKind { mid, finalScan }

class _ScanMilestone {
  final _ScanMilestoneKind kind;
  final int from;
  final int to;
  final String eyebrow;
  final String title;
  final String subtitle;
  final String doneCopy;
  final String cta;
  const _ScanMilestone({
    required this.kind,
    required this.from,
    required this.to,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.doneCopy,
    required this.cta,
  });
}

/// v290 — Scan milestone card. Two visual states: PROMPT when the
/// user is in window but hasn't scanned yet (big red CTA), and
/// CAPTURED when the window already has a scan (low-weight pill).
/// Tied to /scan via the onTap callback the State subclass injects.
class _ScanMilestoneCard extends StatelessWidget {
  final _ScanMilestone milestone;
  final bool done;
  final VoidCallback onTap;
  const _ScanMilestoneCard({
    required this.milestone,
    required this.done,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (done) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.signalGreen.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(Rd.lg),
            border: Border.all(
              color: AppColors.signalGreen.withValues(alpha: 0.40),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: AppColors.signalGreen,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.check_rounded,
                  color: Colors.black, size: 14),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(milestone.doneCopy,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 13.5, height: 1.3,
                    fontWeight: FontWeight.w700,
                  )),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () { HapticFeedback.mediumImpact(); onTap(); },
          borderRadius: BorderRadius.circular(Rd.lg),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end:   Alignment.bottomRight,
                colors: [
                  AppColors.red.withValues(alpha: 0.16),
                  AppColors.surface1,
                ],
              ),
              borderRadius: BorderRadius.circular(Rd.lg),
              border: Border.all(
                color: AppColors.red.withValues(alpha: 0.45), width: 0.8),
              boxShadow: [
                BoxShadow(
                  color: AppColors.red.withValues(alpha: 0.15),
                  blurRadius: 24, spreadRadius: 0),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.center_focus_strong_rounded,
                      color: AppColors.red, size: 16),
                    const SizedBox(width: 8),
                    Text(milestone.eyebrow,
                      style: GoogleFonts.inter(
                        color: AppColors.red,
                        fontSize: 10, letterSpacing: 2.8,
                        fontWeight: FontWeight.w900,
                      )),
                  ],
                ),
                const SizedBox(height: 12),
                Text(milestone.title,
                  style: GoogleFonts.spaceGrotesk(
                    color: AppColors.textPrimary,
                    fontSize: 24, height: 1.15,
                    letterSpacing: -0.8,
                    
                    fontWeight: FontWeight.w800,
                  )),
                const SizedBox(height: 8),
                Text(milestone.subtitle,
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 13, height: 1.5,
                    fontWeight: FontWeight.w500,
                  )),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(milestone.cta.toUpperCase(),
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 11.5, letterSpacing: 2.0,
                          fontWeight: FontWeight.w900,
                        )),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 15),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// v289 — Today's Message. Single rotating identity line that
/// replaces the manufactured fear of the Cost of Quitting card.
/// Day-indexed copy, streak-milestone overrides — see
/// [AscensionService.todayMessageFor].
class _TodayMessageCard extends StatelessWidget {
  final String line;
  const _TodayMessageCard({required this.line});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(Rd.lg),
          border: Border(
            left: BorderSide(color: AppColors.red, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TODAY',
              style: GoogleFonts.inter(
                color: AppColors.red,
                fontSize: 10, letterSpacing: 2.8,
                fontWeight: FontWeight.w900,
              )),
            const SizedBox(height: 8),
            Text(line,
              style: GoogleFonts.spaceGrotesk(
                color: AppColors.textPrimary,
                fontSize: 18, height: 1.35,
                letterSpacing: -0.4,
                
                fontWeight: FontWeight.w600,
              )),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SECTION 3 — TODAY'S ASCENSION (missions)
// ═══════════════════════════════════════════════════════════════════════════

class _MissionsPanel extends StatelessWidget {
  final List<AscendMission> missions;
  final int done;
  const _MissionsPanel({required this.missions, required this.done});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(Rd.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('TODAY\'S ASCENSION',
                  style: GoogleFonts.inter(
                    color: AppColors.red,
                    fontSize: 11, letterSpacing: 2.8,
                    fontWeight: FontWeight.w900,
                  )),
                const Spacer(),
                Text('$done / ${missions.length} COMPLETE',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 11, letterSpacing: 1.8,
                    fontWeight: FontWeight.w800,
                  )),
              ],
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < missions.length; i++) ...[
              _MissionRow(mission: missions[i]),
              if (i != missions.length - 1)
                Divider(
                  height: 1, thickness: 0.6,
                  color: AppColors.surface3.withValues(alpha: 0.55),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MissionRow extends StatelessWidget {
  final AscendMission mission;
  const _MissionRow({required this.mission});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: mission.onTap == null ? null : () {
          HapticFeedback.selectionClick();
          mission.onTap!();
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              _MissionCheck(done: mission.done),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mission.title,
                      style: GoogleFonts.inter(
                        color: mission.done
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                        fontSize: 15, height: 1.2,
                        fontWeight: FontWeight.w700,
                        decoration: mission.done
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      )),
                    if (mission.hint.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(mission.hint,
                        style: GoogleFonts.inter(
                          color: AppColors.textTertiary,
                          fontSize: 12, height: 1.3,
                          fontWeight: FontWeight.w500,
                        )),
                    ],
                  ],
                ),
              ),
              if (mission.onTap != null && !mission.done)
                const Icon(Icons.chevron_right,
                  color: AppColors.textTertiary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissionCheck extends StatelessWidget {
  final bool done;
  const _MissionCheck({required this.done});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24, height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.red : Colors.transparent,
        border: Border.all(
          color: done ? AppColors.red : AppColors.surface3,
          width: 1.5,
        ),
      ),
      child: done
        ? const Icon(Icons.check_rounded, color: Colors.white, size: 15)
        : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SECTION 4 — RANK PROGRESSION
// ═══════════════════════════════════════════════════════════════════════════

class _RankProgression extends StatelessWidget {
  final int currentDay;
  const _RankProgression({required this.currentDay});
  @override
  Widget build(BuildContext context) {
    final ranks = AscensionService.ranks();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(Rd.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('THE MAN YOU ARE BUILDING',
              style: GoogleFonts.inter(
                color: AppColors.red,
                fontSize: 10, letterSpacing: 2.8,
                fontWeight: FontWeight.w900,
              )),
            const SizedBox(height: 14),
            for (var i = 0; i < ranks.length; i++) ...[
              _RankRow(
                rank:     ranks[i],
                isPassed: currentDay > ranks[i].minDay,
                isCurrent: currentDay >= ranks[i].minDay &&
                           (i == ranks.length - 1 ||
                            currentDay < ranks[i + 1].minDay),
              ),
              if (i != ranks.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final AscendRank rank;
  final bool isPassed;
  final bool isCurrent;
  const _RankRow({
    required this.rank,
    required this.isPassed,
    required this.isCurrent,
  });
  @override
  Widget build(BuildContext context) {
    final reached = isPassed || isCurrent;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 56,
          child: Text('DAY ${rank.minDay}',
            style: GoogleFonts.inter(
              color: reached ? AppColors.red : AppColors.textTertiary,
              fontSize: 10, letterSpacing: 1.6,
              fontWeight: FontWeight.w900,
            )),
        ),
        const SizedBox(width: 8),
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isCurrent
              ? AppColors.red
              : (isPassed ? AppColors.red.withValues(alpha: 0.65)
                          : Colors.transparent),
            border: Border.all(
              color: reached ? AppColors.red : AppColors.surface3,
              width: 1.5,
            ),
            boxShadow: isCurrent
              ? [BoxShadow(
                  color: AppColors.red.withValues(alpha: 0.6),
                  blurRadius: 12)]
              : null,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(rank.label,
            style: GoogleFonts.inter(
              color: reached ? AppColors.textPrimary : AppColors.textTertiary,
              fontSize: 16, height: 1.2,
              letterSpacing: 1.4,
              fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w700,
              
            )),
        ),
        if (isCurrent)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.red,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('YOU',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 9, letterSpacing: 1.6,
                fontWeight: FontWeight.w900,
              )),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SECTION 5 — ASCENSION RECORD (timeline)
// ═══════════════════════════════════════════════════════════════════════════

class _RecordTimeline extends StatelessWidget {
  final List<AscendMilestone> milestones;
  const _RecordTimeline({required this.milestones});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(Rd.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ASCENSION RECORD',
              style: GoogleFonts.inter(
                color: AppColors.red,
                fontSize: 10, letterSpacing: 2.8,
                fontWeight: FontWeight.w900,
              )),
            const SizedBox(height: 14),
            if (milestones.isEmpty)
              Text('Your record writes itself the moment you log day one.',
                style: GoogleFonts.inter(
                  color: AppColors.textTertiary,
                  fontSize: 13, height: 1.5,
                  
                  fontWeight: FontWeight.w500,
                )),
            for (var i = 0; i < milestones.length; i++) ...[
              _MilestoneRow(milestone: milestones[i]),
              if (i != milestones.length - 1) const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  final AscendMilestone milestone;
  const _MilestoneRow({required this.milestone});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Text('DAY ${milestone.day}',
            style: GoogleFonts.inter(
              color: AppColors.red,
              fontSize: 10, letterSpacing: 1.6,
              fontWeight: FontWeight.w900,
            )),
        ),
        const SizedBox(width: 8),
        Container(
          width: 8, height: 8,
          margin: const EdgeInsets.only(top: 4),
          decoration: const BoxDecoration(
            color: AppColors.red,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(milestone.title,
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 14, height: 1.3,
                  fontWeight: FontWeight.w700,
                )),
              if (milestone.detail.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(milestone.detail,
                  style: GoogleFonts.inter(
                    color: AppColors.textTertiary,
                    fontSize: 12, height: 1.35,
                    fontWeight: FontWeight.w500,
                  )),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SECTION 6 — STREAK
// ═══════════════════════════════════════════════════════════════════════════

/// v303 — Streak panel rebuilt. Flame icon + numeral are now ONE
/// lockup. Bro: "the streak is dislocated and a dud. fix it
/// production grade only fix perfectly." Old layout had the flame
/// floating up in the label row and the numeral isolated below —
/// they read as two unrelated things. New layout pins the flame
/// directly against the number at matching visual weight so the
/// pair anchors as a single hero element.
class _StreakPanel extends StatelessWidget {
  final int current;
  final int longest;
  const _StreakPanel({required this.current, required this.longest});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        decoration: BoxDecoration(
          // Warm red radial behind the lockup so the flame reads
          // as actually glowing on the surface, not a flat icon.
          gradient: RadialGradient(
            center: const Alignment(-0.5, -0.2),
            radius: 1.2,
            colors: [
              AppColors.red.withValues(alpha: 0.20),
              AppColors.surface1,
            ],
          ),
          borderRadius: BorderRadius.circular(Rd.lg),
          border: Border.all(
            color: AppColors.red.withValues(alpha: 0.42), width: 0.8),
          boxShadow: [
            BoxShadow(
              color: AppColors.red.withValues(alpha: 0.28),
              blurRadius: 32, spreadRadius: 0),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Eyebrow row: label left, LONGEST right.
            Row(
              children: [
                Text('STREAK',
                  style: GoogleFonts.inter(
                    color: AppColors.red,
                    fontSize: 11, letterSpacing: 3.2,
                    fontWeight: FontWeight.w900,
                  )),
                const Spacer(),
                Text('LONGEST $longest',
                  style: GoogleFonts.inter(
                    color: AppColors.textTertiary,
                    fontSize: 10, letterSpacing: 1.8,
                    fontWeight: FontWeight.w800,
                  )),
              ],
            ),
            const SizedBox(height: 10),

            // ── THE LOCKUP — flame, number, "DAY" label, all on
            // the same baseline at matching visual weight. Stack
            // gives the flame a soft outer halo before the icon
            // renders so it reads as glowing, not stamped.
            SizedBox(
              height: 100,
              child: Stack(
                alignment: Alignment.bottomLeft,
                children: [
                  // Halo behind the flame.
                  Positioned(
                    left: -6, bottom: 4,
                    child: Container(
                      width: 110, height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          AppColors.red.withValues(alpha: 0.42),
                          Colors.transparent,
                        ]),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Icon(Icons.local_fire_department_rounded,
                        color: AppColors.red, size: 88),
                      const SizedBox(width: 6),
                      // The numeral. Italic Playfair, white, sized
                      // to match the flame's optical height so the
                      // pair reads as one unit.
                      Text('$current',
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontSize: 92, height: 1,
                          letterSpacing: -3.4,
                          
                          fontWeight: FontWeight.w900,
                          shadows: [
                            Shadow(
                              color: AppColors.red.withValues(alpha: 0.45),
                              blurRadius: 18),
                          ],
                        )),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Text(current == 1 ? 'DAY' : 'DAYS',
                          style: GoogleFonts.inter(
                            color: AppColors.textSecondary,
                            fontSize: 14, letterSpacing: 3.0,
                            fontWeight: FontWeight.w900,
                          )),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
            Text(_streakStatusLine(current, longest),
              style: GoogleFonts.inter(
                color: AppColors.textSecondary,
                fontSize: 13, height: 1.4,
                letterSpacing: 0.3,
                fontWeight: FontWeight.w600,
              )),
          ],
        ),
      ),
    );
  }

  /// Honest one-line status, not fake percentile copy. Reads off
  /// the user's actual numbers.
  static String _streakStatusLine(int current, int longest) {
    if (current == 0)                return 'No streak yet. Log today and ignite.';
    if (current == 1)                return 'Day one. Make it stick.';
    if (current >= longest)          return 'Best run yet. Don\'t break it.';
    return 'Longest: $longest. Catch it.';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  SECTION 7 — FINAL FORM (locked or unlocked at day 60)
// ═══════════════════════════════════════════════════════════════════════════

class _FinalFormCard extends StatelessWidget {
  final bool unlocked;
  final int daysLeft;
  /// v291 — invoked when the user taps GENERATE CERTIFICATE on the
  /// unlocked card. The State subclass owns the data collection
  /// (first/last scan, looks/game arcs, DEBLOAT start/end) and the
  /// ShareService call. Null when locked so the build path can
  /// hide the CTA entirely.
  final Future<void> Function()? onGenerate;
  const _FinalFormCard({
    required this.unlocked,
    required this.daysLeft,
    this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(Rd.lg),
          border: Border.all(
            color: unlocked
              ? AppColors.red
              : AppColors.red.withValues(alpha: 0.35),
            width: unlocked ? 1.6 : 0.8,
          ),
          boxShadow: unlocked
            ? [BoxShadow(
                color: AppColors.red.withValues(alpha: 0.30),
                blurRadius: 42, spreadRadius: 0)]
            : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  unlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                  color: AppColors.red, size: 16),
                const SizedBox(width: 8),
                Text(unlocked ? 'UNLOCKED · DAY 60' : 'LOCKED · DAY 60',
                  style: GoogleFonts.inter(
                    color: AppColors.red,
                    fontSize: 10, letterSpacing: 2.8,
                    fontWeight: FontWeight.w900,
                  )),
              ],
            ),
            const SizedBox(height: 10),
            Text('DRAINED · CERTIFIED',
              style: GoogleFonts.spaceGrotesk(
                color: AppColors.textPrimary,
                fontSize: 28, height: 1.1,
                letterSpacing: -0.8,
                fontWeight: FontWeight.w900,
                
              )),
            const SizedBox(height: 14),
            Text(
              unlocked
                ? 'You finished the protocol. Generate the receipt — '
                  'real before / after photos, the DEBLOAT SCORE arc, '
                  'and the full Looks lift, on one card people will '
                  'screenshot.'
                : 'Reach Day 60 to unlock:',
              style: GoogleFonts.inter(
                color: AppColors.textSecondary,
                fontSize: 13.5, height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            for (final line in const [
              'Before / after face pair',
              'DEBLOAT SCORE arc — start to Day 60',
              'Looks arc — the full delta receipt',
              'Consistency receipt',
              'Shareable certificate card',
            ]) Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.check_rounded,
                    color: unlocked
                      ? AppColors.red
                      : AppColors.red.withValues(alpha: 0.45),
                    size: 14),
                  const SizedBox(width: 8),
                  Text(line,
                    style: GoogleFonts.inter(
                      color: unlocked
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                      fontSize: 13, height: 1.4,
                      fontWeight: FontWeight.w600,
                    )),
                ],
              ),
            ),
            if (!unlocked) ...[
              const SizedBox(height: 8),
              Text('$daysLeft day${daysLeft == 1 ? "" : "s"} to go.',
                style: GoogleFonts.inter(
                  color: AppColors.red,
                  fontSize: 12, letterSpacing: 1.8,
                  fontWeight: FontWeight.w900,
                )),
            ],
            if (unlocked && onGenerate != null) ...[
              const SizedBox(height: 18),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () { HapticFeedback.mediumImpact(); onGenerate!(); },
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 13),
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.red.withValues(alpha: 0.5),
                          blurRadius: 22, spreadRadius: 0),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.workspace_premium_rounded,
                          color: Colors.white, size: 18),
                        const SizedBox(width: 10),
                        Text('GENERATE CERTIFICATE',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 12, letterSpacing: 2.4,
                            fontWeight: FontWeight.w900,
                          )),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  v292 — Ascend masthead chips. Same visual treatment the Looks +
//  Rizz mastheads use; duplicated locally so the Ascend tab stays
//  self-contained (those tabs have their own private chip widgets,
//  and dragging them into a shared file would couple three
//  unrelated screens).
// ═══════════════════════════════════════════════════════════════════════════

/// v303 — Masthead streak chip. Solid red fill (was 14% tinted
/// ghost), white flame + white digit, soft red glow shadow so the
/// chip reads as one of the strongest visual elements on the
/// chrome row instead of disappearing into the background. Same
/// lockup the Looks + Rizz mastheads now use for consistency.
class _MastheadStreakBadge extends StatelessWidget {
  final int days;
  const _MastheadStreakBadge({required this.days});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.red,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
            color: AppColors.red.withValues(alpha: 0.45),
            blurRadius: 14, spreadRadius: 0),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              color: Colors.white, size: 18),
          const SizedBox(width: 5),
          Text('$days',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14, height: 1,
              letterSpacing: 0.2,
              fontWeight: FontWeight.w900,
            )),
        ],
      ),
    );
  }
}

class _MastheadProgressChip extends StatelessWidget {
  final VoidCallback onTap;
  const _MastheadProgressChip({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        customBorder: const CircleBorder(),
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppColors.surface1,
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.signalAmber.withValues(alpha: 0.55),
              width: 0.8),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.show_chart_rounded,
              size: 18, color: AppColors.signalAmber),
        ),
      ),
    );
  }
}

class _MastheadSettingsCog extends StatelessWidget {
  final VoidCallback onTap;
  const _MastheadSettingsCog({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AppColors.surface1,
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.divider, width: 0.8),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.tune,
            size: 18, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
