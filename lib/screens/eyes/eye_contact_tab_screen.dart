import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/dev_flags.dart';
import '../../models/face_metrics.dart';
import '../../models/gaze/gaze_lesson.dart';
import '../../models/gaze/gaze_syllabus.dart';
import '../../services/face_detector_service.dart';
import '../../services/gaze/gaze_progress_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/eyes/auralay_face_overlay_painter.dart';
import 'eyes_session_screen.dart';

/// AURA tab — the tab that replaced RIZZ.
///
/// Bro's spec: "a small drop down at the top, just a full camera screen
/// open until they choose one — then the lesson starts. Without that
/// it's just a camera screen with MediaPipe on the eyes."
///
/// So on entry the front camera fills the screen and the live face-mesh
/// overlay (ice-blue arcs on the eyes + lips) tracks the apprentice's
/// face — the same overlay the lesson drill uses. A compact dropdown
/// sits at the top; picking a lesson launches the full drill in
/// [EyesSessionScreen].
///
/// Lessons unlock one at a time (a scored best > 0 on lesson N opens
/// N+1). Gating (v350): eye contact is a Pro feature — 3 lessons/week
/// for subscribers (folded into the ascension plan). Free users get one
/// free lesson, then the paywall. A capped Pro user gets a white-text
/// "renews next week" notice, never the paywall.
///
/// [active] is driven by the parent IndexedStack: the camera + detector
/// run only while this is the visible tab AND the app is foreground, so
/// they never fight the scan / roleplay cameras or drain battery.
class EyeContactTabScreen extends StatefulWidget {
  final bool active;
  const EyeContactTabScreen({super.key, required this.active});

  @override
  State<EyeContactTabScreen> createState() => _EyeContactTabScreenState();
}

class _EyeContactTabScreenState extends State<EyeContactTabScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // ─── Camera + live face mesh ──────────────────────────────────────
  CameraController? _cam;
  bool    _camReady = false;
  String? _camError;
  bool    _starting = false;
  bool    _streaming = false;
  final FaceDetectorService _detector = FaceDetectorService();
  bool _processing = false;
  FaceMetrics _metrics = FaceMetrics.empty;
  late final AnimationController _pulse;

  // ─── Progress state ───────────────────────────────────────────────
  /// Lesson ids the apprentice has scored above zero on — drives the
  /// sequential unlock (lesson N opens once N-1 is in this set).
  Set<String> _completed = const {};

  // ─── Dropdown ─────────────────────────────────────────────────────
  bool _menuOpen = false;

  List<GazeLesson> get _lessons => GazeSyllabus.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _detector.init();
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
      if (mounted) setState(() => _menuOpen = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (widget.active) _startCamera();
    } else {
      // Paused / inactive / hidden / detached — release the camera.
      _stopCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    _stopCamera();
    _detector.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final done = <String>{};
    for (final l in _lessons) {
      final best = await GazeProgressStore.bestFor(l.id);
      if (best != null && best > 0) done.add(l.id);
    }
    if (!mounted) return;
    setState(() => _completed = done);
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
      // ResolutionPreset.low — the frames feed the face detector, so we
      // match the lesson drill's resolution (cheap to process).
      final ctrl = CameraController(
        front,
        ResolutionPreset.low,
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
      // Start the frame stream for the live mesh overlay.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _cam == null || _streaming) return;
        try {
          await _cam!.startImageStream(_onFrame);
          _streaming = true;
        } catch (_) {/* preview still shows without the mesh */}
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

  Future<void> _onFrame(CameraImage image) async {
    if (_processing || !mounted) return;
    _processing = true;
    try {
      final m = await _detector.process(
        image,
        _cam?.description.sensorOrientation ?? 0,
        isFrontCam: true,
      );
      if (!mounted || m == null) {
        _processing = false;
        return;
      }
      setState(() => _metrics = m);
    } catch (_) {} finally {
      _processing = false;
    }
  }

  Future<void> _stopCamera() async {
    final c = _cam;
    _cam = null;
    _streaming = false;
    if (mounted) {
      setState(() {
        _camReady = false;
        _metrics = FaceMetrics.empty;
      });
    } else {
      _camReady = false;
    }
    if (c != null) {
      await c.stopImageStream().catchError((_) {});
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
    setState(() => _menuOpen = false);

    if (!_isUnlocked(index)) {
      final prev = _lessons[index - 1];
      _notice('Finish Lesson '
          '${prev.number.toString().padLeft(2, '0')} first — '
          'unlock them one at a time.');
      return;
    }

    // v354 — paywall removed from eye contact for now: every unlocked
    // lesson just opens, no Pro gate, no weekly cap.
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
          // ── Live front camera + face-mesh overlay (or black while
          //    starting / errored). This IS the screen until a lesson
          //    is picked.
          if (_camReady && _cam != null)
            _CameraLayer(
              controller: _cam!,
              overlay: AnimatedBuilder(
                animation: _pulse,
                builder: (_, __) => LayoutBuilder(
                  builder: (_, c) => CustomPaint(
                    size: Size(c.maxWidth, c.maxHeight),
                    painter: AuralayFaceOverlayPainter(
                      metrics:  _metrics,
                      pulse:    _pulse.value,
                      isLocked: _metrics.isGoodEyeContact,
                    ),
                  ),
                ),
              ),
            )
          else
            const ColoredBox(color: Colors.black),

          // ── Subtle top scrim so the dropdown reads over the face.
          const Positioned.fill(child: _TopScrim()),

          // ── Camera-unavailable hint (permission denied / in use).
          if (_camError != null && !_camReady)
            const Align(
              alignment: Alignment(0, -0.15),
              child: _CameraHint(),
            ),

          // ── Top bar — the small dropdown + settings. Kept minimal so
          //    the camera owns the screen.
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _LessonDropdownButton(
                      doneCount: doneCount,
                      total: _lessons.length,
                      open: _menuOpen,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _menuOpen = !_menuOpen);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  _CircleIcon(
                    icon: Icons.tune,
                    onTap: () => context.push('/settings'),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom coaching hint when idle (no lesson running).
          if (_camReady)
            Align(
              alignment: const Alignment(0, 0.86),
              child: _IdleHint(locked: _metrics.isGoodEyeContact),
            ),

          // ── Tiny build tag (bottom-left) so we can confirm the
          //    installed build isn't a stale TestFlight one.
          Positioned(
            left: 10, bottom: 6,
            child: IgnorePointer(
              child: Text(
                kBuildTag,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.30),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),

          // ── Dropdown overlay — tap-scrim + the lesson list panel.
          if (_menuOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _menuOpen = false),
                child: const ColoredBox(color: Color(0x66000000)),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 58, 16, 0),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _LessonMenu(
                    lessons:    _lessons,
                    done:       _completed,
                    isUnlocked: _isUnlocked,
                    onTap:      _tapLesson,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Camera preview (cover-fit, mirrored front cam) ─────────────────
class _CameraLayer extends StatelessWidget {
  final CameraController controller;
  final Widget overlay;
  const _CameraLayer({required this.controller, required this.overlay});
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return ClipRect(
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: Center(child: CameraPreview(controller, child: overlay)),
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
              Colors.black.withValues(alpha: 0.55),
              Colors.transparent,
            ],
            stops: const [0.0, 0.22],
          ),
        ),
      ),
    );
  }
}

/// The "small dropdown at the top" — a compact pill that opens the
/// lesson menu. Shows AURA + the completed count.
class _LessonDropdownButton extends StatelessWidget {
  final int doneCount;
  final int total;
  final bool open;
  final VoidCallback onTap;
  const _LessonDropdownButton({
    required this.doneCount,
    required this.total,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.base.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: AppColors.red.withValues(alpha: 0.55), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('AURA',
                  style: AppTypography.label.copyWith(
                    color: AppColors.red,
                    fontSize: 12,
                    letterSpacing: 3.0,
                    fontWeight: FontWeight.w900,
                  )),
              const SizedBox(width: 8),
              Text('· test your aura',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.86),
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(width: 8),
              Text('$doneCount/$total',
                  style: AppTypography.label.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dropdown list of lessons. Sequential unlock, scored ticks.
class _LessonMenu extends StatelessWidget {
  final List<GazeLesson>            lessons;
  final Set<String>                 done;
  final bool Function(int)          isUnlocked;
  final void Function(GazeLesson, int) onTap;
  const _LessonMenu({
    required this.lessons,
    required this.done,
    required this.isUnlocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.62,
      ),
      decoration: BoxDecoration(
        color: AppColors.base.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppColors.red.withValues(alpha: 0.30), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 28, offset: const Offset(0, 12)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        padding: const EdgeInsets.all(10),
        shrinkWrap: true,
        itemCount: lessons.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final l = lessons[i];
          return _LessonRow(
            lesson:   l,
            unlocked: isUnlocked(i),
            complete: done.contains(l.id),
            onTap:    () => onTap(l, i),
          );
        },
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
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: unlocked
                ? AppColors.surface1
                : AppColors.surface1.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
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
                    color: unlocked
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
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
                        fontSize: 11.5,
                        height: 1.3,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
        width: 30, height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.signalGreen.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded,
            color: AppColors.signalGreen, size: 17),
      );
    }
    if (!unlocked) {
      return const SizedBox(
        width: 30, height: 30,
        child: Icon(Icons.lock_rounded, color: AppColors.textTertiary, size: 15),
      );
    }
    return Container(
      width: 30, height: 30,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.red,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 18),
    );
  }
}

class _IdleHint extends StatelessWidget {
  final bool locked;
  const _IdleHint({required this.locked});
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Text(
        locked ? 'HOLD THE GAZE' : 'FIND YOUR EYES',
        style: GoogleFonts.playfairDisplay(
          color: locked
              ? Colors.white
              : Colors.white.withValues(alpha: 0.55),
          fontSize: 15,
          letterSpacing: 4.0,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w800,
          shadows: const [Shadow(color: Colors.black, blurRadius: 10)],
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

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIcon({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        customBorder: const CircleBorder(),
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.base.withValues(alpha: 0.78),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.surface3, width: 0.8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}
