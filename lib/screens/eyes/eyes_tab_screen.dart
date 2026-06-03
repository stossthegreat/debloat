import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/dev_flags.dart';
import '../../models/gaze/gaze_lesson.dart';
import '../../models/gaze/gaze_syllabus.dart';
import '../../models/presence/presence_lesson.dart';
import '../../models/presence/presence_syllabus.dart';
import '../../services/gaze/gaze_progress_store.dart';
import '../../services/local_store_service.dart';
import '../../services/presence/presence_progress_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/mirrorly_components.dart';
import 'eyes_session_screen.dart';
import 'voice/eyes_voice_session_screen.dart';

/// EYES — two parts.
///
///   1. EYE CONTACT          — Pure gaze training. The face mesh,
///                             MediaPipe scoring, blink count, Lucien
///                             narrating the move. Existing eyes
///                             session screen.
///
///   2. EYE CONTACT + VOICE  — The hard one. You deliver a line WHILE
///                             holding the gaze. Camera + mic at the
///                             same time. Lucien narrates each line;
///                             you say it; the engine scores both
///                             your gaze and that you spoke.
class EyesTabScreen extends StatefulWidget {
  const EyesTabScreen({super.key});

  @override
  State<EyesTabScreen> createState() => _EyesTabScreenState();
}

class _EyesTabScreenState extends State<EyesTabScreen> {
  late Future<GazeLesson>     _nextGaze;
  late Future<PresenceLesson> _nextPresence;
  late Future<int>            _completedTotal;

  // Paywall entitlement state. `_pro` true ⇒ everything unlocked,
  // unlimited. Free users get one eye-contact lesson (Part One);
  // Part Two (Eye Contact + Voice) is pro-only. `_loaded` gates the
  // locked visual so a paying user never sees a lock flash on launch.
  bool _pro       = false;
  bool _eyesUsed  = false;
  bool _loaded    = false;

  @override
  void initState() {
    super.initState();
    _nextGaze       = _pickNextGaze();
    _nextPresence   = _pickNextPresence();
    _completedTotal = _countCompletedTotal();
    _loadEntitlements();
  }

  Future<int> _countCompletedTotal() async {
    final g = await GazeProgressStore.completedCount();
    final p = await PresenceProgressStore.completedCount();
    return g + p;
  }

  Future<void> _loadEntitlements() async {
    final pro      = kBypassPaywall ? true : await LocalStoreService.isSubscribed();
    final eyesUsed = await LocalStoreService.eyesFreeUsed();
    if (!mounted) return;
    setState(() {
      _pro      = pro;
      _eyesUsed = eyesUsed;
      _loaded   = true;
    });
  }

  Future<GazeLesson> _pickNextGaze() async {
    for (final l in GazeSyllabus.all) {
      final best = await GazeProgressStore.bestFor(l.id);
      if (best == null || best == 0) return l;
    }
    return GazeSyllabus.all.first;
  }

  Future<PresenceLesson> _pickNextPresence() async {
    for (final l in PresenceSyllabus.all) {
      final best = await PresenceProgressStore.bestFor(l.id);
      if (best == null || best == 0) return l;
    }
    return PresenceSyllabus.all.first;
  }

  Future<void> _reload() async {
    setState(() {
      _nextGaze       = _pickNextGaze();
      _nextPresence   = _pickNextPresence();
      _completedTotal = _countCompletedTotal();
    });
    _loadEntitlements();
  }

  // ── Paywall gating ────────────────────────────────────────────────
  // Part One (Eye Contact): pro = unlimited; free = exactly one lesson
  // (consumed on open), then paywall. Browsing the full library is
  // pro-only. Part Two (Eye Contact + Voice) is pro-only outright.
  bool get _eyeContactLocked => _loaded && !_pro && _eyesUsed;
  bool get _voiceLocked      => _loaded && !_pro;

  Future<void> _toPaywall() async {
    await context.push('/paywall');
    if (!mounted) return;
    _loadEntitlements();
  }

  Future<void> _onEyeContactBegin(GazeLesson l) async {
    if (_pro) { _openGaze(l); return; }
    if (!_eyesUsed) {
      await LocalStoreService.markEyesFreeUsed();
      if (!mounted) return;
      setState(() => _eyesUsed = true);
      _openGaze(l);
      return;
    }
    _toPaywall();
  }

  void _onVoiceBegin(PresenceLesson l) {
    if (_pro) { _openVoice(l); return; }
    _toPaywall();
  }

  Future<void> _openGaze(GazeLesson l) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => EyesSessionScreen(lesson: l)),
    );
    _reload();
  }

  Future<void> _openVoice(PresenceLesson l) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => EyesVoiceSessionScreen(lesson: l)),
    );
    _reload();
  }

  // ─── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: Sp.xxl),
          children: [
            // ── Masthead — AURA. Only the Ascend tab uses the "Mirrorly"
            //    wordmark; every other tab carries its own name only.
            MirrorlyMasthead(
              title: 'Aura',
              actions: [
                MastheadAction(
                  icon: Icons.tune,
                  onTap: () => context.push('/settings'),
                ),
              ],
            ),

            const SizedBox(height: Sp.lg),

            // ── Progress strip — "00 / 10 LESSONS · 0%" with a thin red bar.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: FutureBuilder<int>(
                future: _completedTotal,
                builder: (_, snap) {
                  final done  = snap.data ?? 0;
                  final total = GazeSyllabus.all.length +
                                PresenceSyllabus.all.length;
                  return _ProgressStrip(done: done, total: total);
                },
              ),
            ).animate().fadeIn(duration: 400.ms),

            const SizedBox(height: Sp.lg),

            // ── Hook line — the close, just above the cards.
            const HookLine(
              'The man who breaks first loses. Train the eyes she actually meets.',
              emphasised: true,
            ).animate().fadeIn(delay: 80.ms, duration: 400.ms),

            const SizedBox(height: Sp.lg),

            // ── SELENE — live AI lesson entry. Tap launches THE LOCK
            //    as a live realtime session.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: _SeleneLiveCard(
                onTap: () => context.push('/eyes/live/the_lock'),
              ),
            ).animate().fadeIn(delay: 120.ms, duration: 400.ms),

            const SizedBox(height: Sp.lg),

            // ── PART ONE — Eye Contact (gaze training).
            // Card is intentionally NOT shown as locked even after the
            // free use is consumed: tapping always works — the handler
            // either runs the lesson (first time, free) or routes to
            // the paywall (after). A locked badge would just kill the
            // tap intent and the conversion.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: FutureBuilder<GazeLesson>(
                future: _nextGaze,
                builder: (_, snap) {
                  final l = snap.data ?? GazeSyllabus.all.first;
                  final upcoming = GazeSyllabus.all
                      .where((g) => g.id != l.id)
                      .toList();
                  return CharacterCard(
                    eyebrow: 'Part one',
                    title: 'Eye Contact',
                    body:
                        'Pure gaze training. Hold her eyes. Don\'t break first.',
                    assetPath: MirrorlyAssets.gazeNeutral,
                    locked: false,
                    inlinePanel: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CompactLessonRow(
                          number: l.number,
                          name: l.name,
                          oneLine: l.oneLine,
                          onStart: () => _onEyeContactBegin(l),
                        ),
                        if (upcoming.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _NextLessonsStrip(lessons: upcoming),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ).animate().fadeIn(delay: 160.ms, duration: 400.ms),

            const SizedBox(height: Sp.lg),

            // ── PART TWO — Eye Contact + Voice (Lucien's room).
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: FutureBuilder<PresenceLesson>(
                future: _nextPresence,
                builder: (_, snap) {
                  final l = snap.data ?? PresenceSyllabus.all.first;
                  return CharacterCard(
                    eyebrow: 'Part two',
                    title: 'Eye Contact + Voice',
                    body:
                        'Lock her gaze. Deliver the line. Don\'t blink, '
                        'don\'t shrink, don\'t apologise. Lucien reads it '
                        'once — then it\'s on you.',
                    assetPath: MirrorlyAssets.lucienSpeaking,
                    locked: _voiceLocked,
                    footer: PrimaryCta(
                      label: _voiceLocked ? 'Unlock With Pro' : 'Start Lesson',
                      icon: _voiceLocked
                          ? null
                          : Icons.play_arrow_rounded,
                      locked: _voiceLocked,
                      onTap: () => _onVoiceBegin(l),
                    ),
                  );
                },
              ),
            ).animate().fadeIn(delay: 240.ms, duration: 400.ms),

            const SizedBox(height: Sp.lg),
          ],
        ),
      ),
    );
  }

}

// ─── Progress strip ─────────────────────────────────────────────────
// "00 / NN LESSONS  ────────  0%". Same visual as the mockup top band.

class _ProgressStrip extends StatelessWidget {
  final int done;
  final int total;
  const _ProgressStrip({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? done / total : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: AppColors.surface3, width: 1),
      ),
      child: Row(
        children: [
          Text(
            '${done.toString().padLeft(2, '0')} / $total LESSONS',
            style: AppTypography.label.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 3,
                backgroundColor: AppColors.surface3,
                valueColor: const AlwaysStoppedAnimation(AppColors.red),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(ratio * 100).round()}%',
            style: AppTypography.label.copyWith(
              color: AppColors.red,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Next-lessons strip ─────────────────────────────────────────────
// Horizontal scroll of every remaining lesson as small locked chips.
// Lets the user see WHAT'S COMING without inflating card height the
// way a full vertical list does. Chips aren't tappable — they're
// previews, not entry points; tapping the main play button always
// runs the current lesson and the rest follow naturally.

class _NextLessonsStrip extends StatelessWidget {
  final List<GazeLesson> lessons;
  const _NextLessonsStrip({required this.lessons});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: lessons.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final l = lessons[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.surface3, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${l.number.toString().padLeft(2, '0')} · ${l.name}',
                  style: AppTypography.label.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.lock_rounded,
                    size: 11, color: AppColors.textMuted),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Compact lesson row ─────────────────────────────────────────────
// Single-row replacement for the long lesson list. Sits inside the
// Part 1 card. Title + one-line description on the left, round red
// play button on the right — frees up the horizontal space the old
// "START LESSON" text button was eating, so the title never truncates.

class _CompactLessonRow extends StatelessWidget {
  final int number;
  final String name;
  final String oneLine;
  final VoidCallback onStart;
  const _CompactLessonRow({
    required this.number,
    required this.name,
    required this.oneLine,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: AppColors.red.withOpacity(0.30), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Lesson ${number.toString().padLeft(2, '0')}  ·  ${name.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  oneLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.red,
                    fontSize: 12.5,
                    height: 1.35,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          InkResponse(
            onTap: onStart,
            radius: 28,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.red.withOpacity(0.40),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.black,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// SELENE entry card — the APEX card on the Aura tab. Hero-treated
/// (no horizontal padding, taller than CharacterCard, full-width
/// asset crop) so it reads as the headline event vs the scripted
/// CharacterCards below — those are episodes, this is the film. The
/// cinematic eyes asset (same one used during the live drill itself)
/// is the visual core so the card and the lesson share a face.
class _SeleneLiveCard extends StatelessWidget {
  final VoidCallback onTap;
  const _SeleneLiveCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () { HapticFeedback.mediumImpact(); onTap(); },
        borderRadius: BorderRadius.circular(Rd.xl),
        child: Container(
          height: 220,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(Rd.xl),
            border: Border.all(
              color: AppColors.red.withValues(alpha: 0.55), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: AppColors.red.withValues(alpha: 0.28),
                blurRadius: 28, offset: const Offset(0, 8)),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Selene\'s face on the card — the ice-queen character
              // portrait, not the cinematic eyes-only asset. Bro:
              // "instead of the eyes on the Selene card put image of
              // ice queen." Same alignment + fit so the gradient
              // overlay still works.
              Positioned.fill(
                child: Image.asset(
                  'assets/characters/women/ice_queen.png',
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.15),
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.black,
                  ),
                ),
              ),
              // Bottom-up dark gradient so the title + body always
              // sit on a legible surface no matter what the eyes asset
              // looks like.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end:   Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.95),
                        Colors.black.withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
              // Top-left chrome — LIVE pulse + NEW.
              Positioned(
                top: 14, left: 14,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text('LIVE',
                        style: AppTypography.label.copyWith(
                          color: Colors.black, fontSize: 10,
                          letterSpacing: 2.2,
                          fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 8),
                    Text('with Selene',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 11,
                        letterSpacing: 1.4,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(
                          color: Colors.black.withValues(alpha: 0.85),
                          blurRadius: 6)],
                      )),
                  ],
                ),
              ),
              // Top-right — pulsing mic circle. Same affordance as
              // before but pulled to the corner so the eyes own the
              // centre frame.
              Positioned(
                top: 12, right: 12,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.red.withValues(alpha: 0.65),
                        blurRadius: 16,
                        offset: const Offset(0, 4)),
                    ],
                  ),
                  child: const Icon(Icons.mic_rounded,
                      color: Colors.black, size: 22),
                ),
              ),
              // Bottom-left — title block + body + CTA hint.
              Positioned(
                left: 18, right: 18, bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Selene',
                      style: GoogleFonts.playfairDisplay(
                        color: Colors.white,
                        fontSize: 36,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        height: 1.0,
                        shadows: [Shadow(
                          color: Colors.black.withValues(alpha: 0.85),
                          blurRadius: 12)],
                      )),
                    const SizedBox(height: 6),
                    Text('THE LOCK — masterclass, in her voice.',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 13,
                        height: 1.4,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(
                          color: Colors.black.withValues(alpha: 0.85),
                          blurRadius: 8)],
                      )),
                    const SizedBox(height: 4),
                    Text(
                      'She frames it, teaches the science, calls the '
                      'drill, then coaches you live against your face.',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 11.5,
                        height: 1.45,
                        shadows: [Shadow(
                          color: Colors.black.withValues(alpha: 0.85),
                          blurRadius: 6)],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
