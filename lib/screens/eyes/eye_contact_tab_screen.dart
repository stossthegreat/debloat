import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/dev_flags.dart';
import '../../models/gaze/gaze_lesson.dart';
import '../../models/gaze/gaze_syllabus.dart';
import '../../services/gaze/gaze_progress_store.dart';
import '../../services/local_store_service.dart';
import '../../services/streak_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/imhim_wordmark.dart';
import 'eyes_session_screen.dart';

/// EYE CONTACT tab — the tab that replaced RIZZ.
///
/// Bro's spec: "the screen that currently says Rizz [is] eye contact…
/// the camera's just open as soon as they click it, and you have the
/// ten lessons drop down, they have to unlock one at a time."
///
/// So on entry the front camera goes LIVE behind a translucent lesson
/// panel. The 12 gaze lessons list in order; each is locked until the
/// one before it has been passed (a scored best > 0). Tapping an
/// unlocked lesson launches the full [EyesSessionScreen] drill.
///
/// Gating (v350): eye contact is a Pro feature — 3 lessons/week for
/// subscribers (folded into the ascension plan). Free users get one
/// free lesson, then the paywall. A capped Pro user gets a white-text
/// "renews next week" notice, never the paywall (which would auto-
/// unlock and bypass the cap).
///
/// [active] is driven by the parent IndexedStack: the camera is only
/// initialised while this tab is the visible tab AND the app is in the
/// foreground, so it never fights the scan / roleplay cameras or drains
/// battery in the background.
class EyeContactTabScreen extends StatefulWidget {
  final bool active;
  const EyeContactTabScreen({super.key, required this.active});

  @override
  State<EyeContactTabScreen> createState() => _EyeContactTabScreenState();
}

class _EyeContactTabScreenState extends State<EyeContactTabScreen>
    with WidgetsBindingObserver {
  // ─── Camera ───────────────────────────────────────────────────────
  CameraController? _cam;
  bool    _camReady = false;
  String? _camError;
  bool    _starting = false;

  // ─── Entitlement + progress state ─────────────────────────────────
  bool _pro        = false;
  bool _eyesUsed   = false;
  bool _capReached = false;
  bool _loaded     = false;
  int  _dayStreak  = 0;
  /// Lesson ids the apprentice has scored above zero on — drives the
  /// sequential unlock (lesson N opens once N-1 is in this set).
  Set<String> _completed = const {};

  List<GazeLesson> get _lessons => GazeSyllabus.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadState();
    if (widget.active) _startCamera();
  }

  @override
  void didUpdateWidget(covariant EyeContactTabScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _loadState();
      _startCamera();
    } else if (!widget.active && old.active) {
      _stopCamera();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (widget.active) _startCamera();
    } else {
      // Paused / inactive / hidden / detached — release the camera so
      // it's free for other surfaces and stops drawing power.
      _stopCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    super.dispose();
  }

  Future<void> _loadState() async {
    final pro     = kBypassPaywall ? true : await LocalStoreService.isSubscribed();
    final used    = await LocalStoreService.eyesFreeUsed();
    final capped  = await LocalStoreService.eyeLessonsCapReached();
    final streak  = await StreakService.current();
    final done = <String>{};
    for (final l in _lessons) {
      final best = await GazeProgressStore.bestFor(l.id);
      if (best != null && best > 0) done.add(l.id);
    }
    if (!mounted) return;
    setState(() {
      _pro        = pro;
      _eyesUsed   = used;
      _capReached = capped;
      _dayStreak  = streak;
      _completed  = done;
      _loaded     = true;
    });
  }

  // ─── Camera lifecycle ─────────────────────────────────────────────
  Future<void> _startCamera() async {
    if (_starting || _cam != null) return;
    _starting = true;
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw Exception('No cameras');
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await ctrl.initialize();
      if (!mounted || !widget.active) {
        await ctrl.dispose();
        _starting = false;
        return;
      }
      setState(() {
        _cam      = ctrl;
        _camReady = true;
        _camError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _camError = e.toString();
          _camReady = false;
        });
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _stopCamera() async {
    final c = _cam;
    _cam = null;
    if (mounted) {
      setState(() => _camReady = false);
    } else {
      _camReady = false;
    }
    if (c != null) {
      await c.dispose().catchError((_) {});
    }
  }

  // ─── Unlock + gating ──────────────────────────────────────────────
  bool _isUnlocked(int index) {
    if (index <= 0) return true;
    return _completed.contains(_lessons[index - 1].id);
  }

  Future<void> _tapLesson(GazeLesson l, int index) async {
    HapticFeedback.selectionClick();
    if (!_isUnlocked(index)) {
      final prev = _lessons[index - 1];
      _notice('Finish Lesson '
          '${prev.number.toString().padLeft(2, '0')} first — '
          'unlock them one at a time.');
      return;
    }

    if (!_pro) {
      // Free tier: one free lesson, then the paywall.
      if (_eyesUsed) {
        await context.push('/paywall', extra: {'source': 'eyes_capped'});
        if (mounted) _loadState();
        return;
      }
      await LocalStoreService.markEyesFreeUsed();
      if (mounted) setState(() => _eyesUsed = true);
    } else {
      // Pro: 3 lessons/week. Capped → white-text notice, NOT paywall.
      if (_capReached) {
        _notice('All 3 eye-contact lessons used this week. '
            'They renew at the start of your next billing week.');
        return;
      }
    }

    await _openLesson(l);
  }

  Future<void> _openLesson(GazeLesson l) async {
    // Hand the camera to the session screen — one controller at a time.
    await _stopCamera();
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => EyesSessionScreen(lesson: l)),
    );
    if (!mounted) return;
    await _loadState();
    if (widget.active) _startCamera();
  }

  void _notice(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.surface2,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final doneCount = _completed.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Live camera preview (or black while starting / errored).
          if (_camReady && _cam != null)
            _CameraLayer(controller: _cam!)
          else
            const ColoredBox(color: Colors.black),

          // ── Top-down scrim so the masthead reads over the face.
          const Positioned.fill(child: _TopScrim()),

          // ── Masthead — ImHim wordmark + streak + settings, matching
          //    the other tabs.
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const ImHimWordmark(fontSize: 34),
                  const Spacer(),
                  if (_dayStreak > 0) ...[
                    _StreakBadge(days: _dayStreak),
                    const SizedBox(width: 8),
                  ],
                  _CircleIcon(
                    icon: Icons.show_chart_rounded,
                    border: AppColors.signalAmber.withValues(alpha: 0.55),
                    color: AppColors.signalAmber,
                    onTap: () => context.push('/progress'),
                  ),
                  const SizedBox(width: 8),
                  _CircleIcon(
                    icon: Icons.tune,
                    border: AppColors.surface3,
                    color: AppColors.textSecondary,
                    onTap: () => context.push('/settings'),
                  ),
                ],
              ),
            ),
          ),

          // ── Camera-unavailable hint (permission denied / in use).
          if (_camError != null && !_camReady)
            const Align(
              alignment: Alignment(0, -0.35),
              child: _CameraHint(),
            ),

          // ── Lesson panel — the "dropdown" of all lessons, unlocked
          //    one at a time. Bottom sheet over the live camera.
          Align(
            alignment: Alignment.bottomCenter,
            child: _LessonPanel(
              lessons:   _lessons,
              done:      _completed,
              doneCount: doneCount,
              loaded:    _loaded,
              isUnlocked: _isUnlocked,
              onTap:     _tapLesson,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Camera preview (cover-fit, mirrored front cam) ─────────────────
class _CameraLayer extends StatelessWidget {
  final CameraController controller;
  const _CameraLayer({required this.controller});
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return ClipRect(
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: Center(child: CameraPreview(controller)),
      ),
    );
  }
}

class _TopScrim extends StatelessWidget {
  const _TopScrim();
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.72),
              Colors.transparent,
            ],
            stops: const [0.0, 0.30],
          ),
        ),
      ),
    );
  }
}

class _CameraHint extends StatelessWidget {
  const _CameraHint();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off_rounded,
              color: AppColors.textTertiary, size: 34),
          const SizedBox(height: 12),
          Text(
            'Camera needed for eye-contact training. Allow camera '
            'access in Settings, then reopen this tab.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Lesson panel ───────────────────────────────────────────────────
class _LessonPanel extends StatelessWidget {
  final List<GazeLesson>            lessons;
  final Set<String>                 done;
  final int                         doneCount;
  final bool                        loaded;
  final bool Function(int)          isUnlocked;
  final void Function(GazeLesson, int) onTap;
  const _LessonPanel({
    required this.lessons,
    required this.done,
    required this.doneCount,
    required this.loaded,
    required this.isUnlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = lessons.length;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.56,
      ),
      decoration: BoxDecoration(
        color: AppColors.base.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(
            color: AppColors.red.withValues(alpha: 0.30), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grab handle + header.
          const SizedBox(height: 10),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('EYE CONTACT',
                    style: AppTypography.label.copyWith(
                      color: AppColors.red,
                      fontSize: 12,
                      letterSpacing: 3.0,
                      fontWeight: FontWeight.w900,
                    )),
                const Spacer(),
                Text('$doneCount / $total',
                    style: AppTypography.label.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w800,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Hold her eyes. Don\'t break first. Unlock them one at a time.',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 12.5, height: 1.35,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
              shrinkWrap: true,
              itemCount: lessons.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final l = lessons[i];
                final unlocked = isUnlocked(i);
                final complete = done.contains(l.id);
                return _LessonRow(
                  lesson:    l,
                  unlocked:  unlocked,
                  complete:  complete,
                  onTap:     () => onTap(l, i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  final GazeLesson lesson;
  final bool unlocked;
  final bool complete;
  final VoidCallback onTap;
  const _LessonRow({
    required this.lesson,
    required this.unlocked,
    required this.complete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = complete
        ? AppColors.signalGreen.withValues(alpha: 0.50)
        : unlocked
            ? AppColors.red.withValues(alpha: 0.40)
            : AppColors.surface3;
    final titleColor = unlocked ? AppColors.textPrimary : AppColors.textTertiary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: unlocked ? AppColors.surface1 : AppColors.surface1.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            children: [
              // Number chip.
              Container(
                width: 34, height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: complete
                      ? AppColors.signalGreen.withValues(alpha: 0.16)
                      : AppColors.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 0.8),
                ),
                child: Text(
                  lesson.number.toString().padLeft(2, '0'),
                  style: AppTypography.label.copyWith(
                    color: unlocked ? AppColors.textPrimary : AppColors.textTertiary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Name + one-line.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      lesson.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.label.copyWith(
                        color: titleColor,
                        fontSize: 12.5,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      lesson.oneLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: unlocked
                            ? AppColors.red.withValues(alpha: 0.90)
                            : AppColors.textTertiary,
                        fontSize: 12,
                        height: 1.3,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Trailing affordance.
              _Trailing(unlocked: unlocked, complete: complete),
            ],
          ),
        ),
      ),
    );
  }
}

class _Trailing extends StatelessWidget {
  final bool unlocked;
  final bool complete;
  const _Trailing({required this.unlocked, required this.complete});
  @override
  Widget build(BuildContext context) {
    if (complete) {
      return Container(
        width: 34, height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.signalGreen.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded,
            color: AppColors.signalGreen, size: 18),
      );
    }
    if (!unlocked) {
      return const SizedBox(
        width: 34, height: 34,
        child: Icon(Icons.lock_rounded, color: AppColors.textTertiary, size: 16),
      );
    }
    return Container(
      width: 34, height: 34,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.red,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
    );
  }
}

// ─── Masthead pieces (mirror the Looks / Rizz tab chrome) ───────────
class _StreakBadge extends StatelessWidget {
  final int days;
  const _StreakBadge({required this.days});
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

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final Color border;
  final Color color;
  final VoidCallback onTap;
  const _CircleIcon({
    required this.icon,
    required this.border,
    required this.color,
    required this.onTap,
  });
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
            border: Border.all(color: border, width: 0.8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
