import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/local_store_service.dart';
import '../../services/mirror_api_service.dart';
import '../../services/paywall_gate.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/ai_consent_dialog.dart';
import '../../widgets/common/mirrorly_wordmark.dart';
import '../../widgets/common/mirrorly_components.dart';

/// BODY — tab index 2. The face pipeline, applied to the frame.
///
/// The full psychology loop:
///   1. MISSION    — pick who you're becoming (SHRED / BUILD / ATHLETIC).
///   2. STATS      — height + weight (one sheet, remembered forever).
///   3. THE AFTER  — full-bleed before/after render, tap to inspect
///                   fullscreen with pinch-zoom.
///   4. THE VERDICT — body score NOW → POTENTIAL, frame type, est.
///                   body-fat band, weight now → target, what to gain/
///                   drop, the timeline, and the first visible change
///                   (the hope hook — "neck and jawline, ~2 weeks").
///   5. THE ROAD   — the mission's 7-move protocol.
///
/// Engineering notes:
///   · EXIF FIX — the picked photo's orientation is BAKED into the
///     pixels before upload (img.bakeOrientation). Replicate strips
///     EXIF, which returned sideways renders on device.
///   · Verdict math is deterministic on-device (BMI → Deurenberg BF%
///     estimate → mission-specific targets). Instant, free, offline.
///   · Render is Pro-gated, shares the 3/week budget, AI-consent
///     gated before any photo leaves the device.
class BodyTabScreen extends StatefulWidget {
  const BodyTabScreen({super.key});

  @override
  State<BodyTabScreen> createState() => _BodyTabScreenState();
}

// ─── Mission presets ─────────────────────────────────────────────────

class _BodyGoal {
  final String id;
  final String name;
  final String oneLine;
  final IconData icon;
  final List<String> brief;
  final List<(String, String)> plan;
  const _BodyGoal({
    required this.id,
    required this.name,
    required this.oneLine,
    required this.icon,
    required this.brief,
    required this.plan,
  });
}

const _goals = <_BodyGoal>[
  _BodyGoal(
    id: 'shred',
    name: 'SHRED',
    oneLine: 'Drop the fat. Unbury the frame.',
    icon: Icons.local_fire_department_rounded,
    brief: [
      'REPLACE HIS PHYSIQUE ENTIRELY — do NOT make a subtle edit. '
          'Show this exact man after ONE FULL YEAR of a disciplined '
          'cut and daily training',
      'shredded at 10% body fat: razor-sharp six-pack, deep muscle '
          'separation across the chest and obliques, vascular arms and '
          'forearms, a dramatically smaller waist, tight defined '
          'jawline and neck — every trace of belly fat gone',
      'the change must look unbelievable next to the before photo',
      'KEEP IDENTICAL: his exact face, identity, beard, hair, tattoos, '
          'skin tone, pose, clothing, background and camera framing',
      'photorealistic, natural lighting — a real one-year '
          'transformation photo of the same man',
    ],
    plan: [
      ('WALK 10K STEPS', 'Every day. Non-negotiable. Fat leaves on foot.'),
      ('LIFT 3× / WEEK', 'Full body, heavy basics. Muscle guards the burn.'),
      ('PROTEIN FIRST', 'Every meal starts with it. It kills the cravings.'),
      ('ZERO LIQUID CALORIES', 'Water, black coffee, tea. Nothing else pours in.'),
      ('EAT IN A WINDOW', '12–8. The kitchen closes. Discipline loves a deadline.'),
      ('SLEEP 7+', 'Tired men eat. Sharp men sleep.'),
      ('WEEKLY PHOTO', 'Same light, same pose. Watch the frame surface.'),
    ],
  ),
  _BodyGoal(
    id: 'build',
    name: 'BUILD',
    oneLine: 'Add the muscle. Fill the shirt.',
    icon: Icons.fitness_center_rounded,
    brief: [
      'REPLACE HIS PHYSIQUE ENTIRELY — do NOT make a subtle edit. '
          'Show this exact man after ONE FULL YEAR of serious '
          'weightlifting and proper eating',
      'give him the body of a men\'s physique athlete: dramatically '
          'broader, rounder 3D shoulders; a thick armour-plate chest; '
          'arms nearly twice as thick as now; wide flaring lats forming '
          'a strong V-taper; developed traps; a thicker neck; visible abs',
      'he should look 12-15 kg of lean muscle heavier — a '
          'transformation nobody would believe without the before photo',
      'KEEP IDENTICAL: his exact face, identity, beard, hair, tattoos, '
          'skin tone, pose, clothing, background and camera framing',
      'photorealistic, natural lighting — a real one-year '
          'transformation photo of the same man',
    ],
    plan: [
      ('LIFT 4× / WEEK', 'Push, pull, legs, repeat. Progressive overload or nothing.'),
      ('EAT IN A SURPLUS', '+300 clean calories. You can\'t build a house without bricks.'),
      ('PROTEIN AT EVERY MEAL', 'Four feeds a day. The raw material.'),
      ('PROGRESS EVERY WEEK', 'One more rep or one more kilo. Log it.'),
      ('SLEEP 8', 'Muscle is built in bed, not the gym.'),
      ('WALK ANYWAY', '8k steps. Stay lean while you grow.'),
      ('WEEKLY PHOTO', 'Shoulders fill first. Catch it on camera.'),
    ],
  ),
  _BodyGoal(
    id: 'athletic',
    name: 'ATHLETIC',
    oneLine: 'Lean. Sharp. Ready for any room.',
    icon: Icons.bolt_rounded,
    brief: [
      'REPLACE HIS PHYSIQUE ENTIRELY — do NOT make a subtle edit. '
          'Show this exact man rebuilt after ONE FULL YEAR of athletic '
          'training and proper eating',
      'a lean athlete at ~11% body fat: visible six-pack, sculpted '
          'shoulders and chest with clear muscle separation, a narrow '
          'waist under a wide shoulder-to-waist ratio, upright powerful '
          'posture — chest up, shoulders back',
      'a transformation people notice from across the room',
      'KEEP IDENTICAL: his exact face, identity, beard, hair, tattoos, '
          'skin tone, pose, clothing, background and camera framing',
      'photorealistic, natural lighting — a real one-year '
          'transformation photo of the same man',
    ],
    plan: [
      ('LIFT 3× / WEEK', 'Compound lifts. Strength is the base of sharp.'),
      ('SPRINT 2× / WEEK', 'Hills or intervals. The fastest recomp there is.'),
      ('PROTEIN EVERY MEAL', 'Maintenance calories, high protein. Recomp fuel.'),
      ('POSTURE RESET DAILY', 'Chin back, chest up, dead hangs. Presence is posture.'),
      ('MOBILITY 10 MIN', 'Hips and shoulders. Move like an athlete, read as one.'),
      ('SLEEP 7–8', 'Recovery is the program.'),
      ('WEEKLY PHOTO', 'Lean shows in the neck first. Track it.'),
    ],
  ),
];

// ─── The verdict — deterministic body read ──────────────────────────
//
// BMI → Deurenberg body-fat estimate (assumed adult age band) →
// mission-specific targets. Honest bands, not fake precision: body fat
// is shown as a range, weights rounded, timelines in week spans.

class _Verdict {
  final int scoreNow;
  final int scorePotential;
  final String frameName;
  final String frameRead;
  final String bfBand;          // "22–26%"
  final double weightNow;       // kg
  final double weightTarget;    // kg
  final String changeLine;      // "Drop ~9 kg of fat" / "Add ~6 kg of muscle"
  final String timeline;        // "14–18 weeks"
  final String firstChange;     // the hope hook
  const _Verdict({
    required this.scoreNow,
    required this.scorePotential,
    required this.frameName,
    required this.frameRead,
    required this.bfBand,
    required this.weightNow,
    required this.weightTarget,
    required this.changeLine,
    required this.timeline,
    required this.firstChange,
  });
}

_Verdict _computeVerdict(_BodyGoal goal, double hCm, double wKg) {
  final h = hCm / 100.0;
  final bmi = wKg / (h * h);
  // Deurenberg (male, assumed age 27): BF% ≈ 1.20·BMI + 0.23·age − 16.2
  final bf = (1.20 * bmi + 0.23 * 27 - 16.2).clamp(6.0, 45.0);
  final lean = wKg * (1 - bf / 100.0);

  // Frame read.
  final String frameName;
  final String frameRead;
  if (bmi < 21.0) {
    frameName = 'LEAN FRAME';
    frameRead = 'Fast metabolism, long runway. Every kilo of muscle you '
        'add shows twice as loud on a frame like this.';
  } else if (bmi <= 26.5) {
    frameName = 'SOLID FRAME';
    frameRead = 'The best starting position there is — enough mass to '
        'sculpt, close enough to lean to see change fast.';
  } else {
    frameName = 'POWER FRAME';
    frameRead = 'There\'s a strength base under there most men train '
        'years for. The cut doesn\'t shrink you — it reveals you.';
  }

  // Score NOW — distance from the athletic band, softened. Typical
  // range lands 40-75 so the potential delta always has room to sell.
  final scoreNow = (78 - (bmi - 22.5).abs() * 4.5 - math.max(0, bf - 15) * 1.1)
      .clamp(35.0, 82.0)
      .round();

  double targetW;
  String changeLine;
  String timeline;
  String firstChange;
  int gain;
  switch (goal.id) {
    case 'shred':
      final targetBf = math.max(12.0, bf - 14.0).clamp(12.0, 16.0);
      targetW = lean / (1 - targetBf / 100.0);
      final drop = math.max(2.0, wKg - targetW);
      final wksLo = (drop / 0.75).ceil();
      final wksHi = (drop / 0.5).ceil();
      changeLine = 'Drop ~${drop.round()} kg of fat, keep the muscle';
      timeline = '$wksLo–$wksHi weeks';
      firstChange = 'Neck and jawline — around week 2.';
      gain = (6 + (bf - 14).clamp(0, 16)).round();
      break;
    case 'build':
      final leanGain = bmi < 22 ? 7.0 : 5.0;
      targetW = wKg + leanGain;
      changeLine = 'Add ~${leanGain.round()} kg of lean muscle';
      final wksLo = (leanGain / 0.45).ceil();
      final wksHi = (leanGain / 0.3).ceil();
      timeline = '$wksLo–$wksHi weeks';
      firstChange = 'Shoulders and chest — around week 3.';
      gain = 18;
      break;
    default: // athletic
      final drop = (bf > 18 ? 4.0 : 2.5);
      targetW = wKg - drop + 2.5;
      changeLine = 'Drop ~${drop.round()} kg of fat, add ~2–3 kg of muscle';
      timeline = '12–16 weeks';
      firstChange = 'Posture and waistline — around week 2.';
      gain = 16;
  }

  final scorePotential =
      math.min(93, math.max(scoreNow + 8, scoreNow + gain));

  String band(double v) => '${(v - 2).round()}–${(v + 2).round()}%';
  return _Verdict(
    scoreNow: scoreNow,
    scorePotential: scorePotential,
    frameName: frameName,
    frameRead: frameRead,
    bfBand: band(bf),
    weightNow: wKg,
    weightTarget: targetW,
    changeLine: changeLine,
    timeline: timeline,
    firstChange: firstChange,
  );
}

class _BodyTabScreenState extends State<BodyTabScreen> {
  static const _kGoal   = 'body.goal.v1';
  static const _kBefore = 'body.before.path.v1';
  static const _kAfter  = 'body.after.url.v1';
  static const _kHeight = 'body.height.cm.v1';
  static const _kWeight = 'body.weight.kg.v1';

  _BodyGoal? _selected;
  String? _beforePath;
  String? _afterUrl;
  double? _heightCm;
  double? _weightKg;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final goalId = prefs.getString(_kGoal);
    final before = prefs.getString(_kBefore);
    final after  = prefs.getString(_kAfter);
    final height = prefs.getDouble(_kHeight);
    final weight = prefs.getDouble(_kWeight);
    if (!mounted) return;
    _BodyGoal? goal;
    for (final g in _goals) {
      if (g.id == goalId) goal = g;
    }
    setState(() {
      _selected = goal;
      _beforePath = (before != null && File(before).existsSync()) ? before : null;
      _afterUrl   = after;
      _heightCm   = height;
      _weightKg   = weight;
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selected != null) await prefs.setString(_kGoal, _selected!.id);
    if (_beforePath != null) await prefs.setString(_kBefore, _beforePath!);
    if (_afterUrl != null) await prefs.setString(_kAfter, _afterUrl!);
    if (_heightCm != null) await prefs.setDouble(_kHeight, _heightCm!);
    if (_weightKg != null) await prefs.setDouble(_kWeight, _weightKg!);
  }

  Future<void> _reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBefore);
    await prefs.remove(_kAfter);
    if (!mounted) return;
    setState(() {
      _beforePath = null;
      _afterUrl = null;
    });
  }

  bool get _hasResult => _beforePath != null && _afterUrl != null;

  // ─── The scan flow ────────────────────────────────────────────────

  Future<void> _begin() async {
    final goal = _selected;
    if (goal == null) {
      _notice('Pick your mission first — Shred, Build or Athletic.');
      return;
    }
    HapticFeedback.mediumImpact();

    final pro = await PaywallGate.isPro();
    if (!mounted) return;
    if (!pro) {
      await context.push('/paywall', extra: {'source': 'body_locked'});
      return;
    }
    if (await LocalStoreService.mirrorRendersThisWeek() >=
        LocalStoreService.kRendersPerWeek) {
      _notice('All ${LocalStoreService.kRendersPerWeek} weekly renders used. '
          'They renew at the start of your next billing week.');
      return;
    }
    if (!mounted || !await AiConsentDialog.ensure(context)) return;

    // Height + weight — the verdict engine's fuel. Asked once,
    // remembered, editable on every run.
    if (!mounted || !await _collectStats()) return;

    final source = await _pickSource();
    if (source == null || !mounted) return;

    XFile? shot;
    try {
      shot = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1440,
        imageQuality: 90,
      );
    } catch (_) {}
    if (shot == null || !mounted) return;

    setState(() => _busy = true);
    try {
      var bytes = await shot.readAsBytes();
      // ── EXIF FIX — bake the camera orientation into the pixels.
      // Replicate strips EXIF, so without this the render comes back
      // sideways (exactly what happened on device).
      try {
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          final baked = img.bakeOrientation(decoded);
          bytes = img.encodeJpg(baked, quality: 90);
        }
      } catch (_) {/* if decode fails, upload the original bytes */}

      final url = await MirrorApiService.maximizeOnly(
        imageBytes: bytes,
        improve: goal.brief,
      );
      await LocalStoreService.markMirrorRenderUsed();

      // Persist the BAKED bytes as the before-image so the NOW pane and
      // the render share identical orientation.
      final dir = File(shot.path).parent;
      final beforeFile = File(
          '${dir.path}/body_before_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await beforeFile.writeAsBytes(bytes);

      if (!mounted) return;
      setState(() {
        _beforePath = beforeFile.path;
        _afterUrl = url;
        _busy = false;
      });
      await _persist();
      HapticFeedback.heavyImpact();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _notice('Render didn\'t land — check your connection and run it again.');
    }
  }

  /// Height + weight sheet. Metric-first with an imperial toggle.
  /// Returns true when valid stats are in hand.
  Future<bool> _collectStats() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _StatsSheet(
        initialHeightCm: _heightCm,
        initialWeightKg: _weightKg,
        onDone: (h, w) {
          _heightCm = h;
          _weightKg = w;
        },
      ),
    );
    if (ok == true) await _persist();
    return ok == true && _heightCm != null && _weightKg != null;
  }

  Future<ImageSource?> _pickSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text('FULL-BODY SHOT',
                style: AppTypography.label.copyWith(
                  color: AppColors.red,
                  fontSize: 11, letterSpacing: 3,
                  fontWeight: FontWeight.w900,
                )),
            const SizedBox(height: 4),
            Text('Head to feet in frame. Neutral stance.',
                style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary, fontSize: 12.5)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.textPrimary),
              title: Text('Take a photo',
                  style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary, fontSize: 15)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.textPrimary),
              title: Text('Choose from library',
                  style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary, fontSize: 15)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _openViewer(ImageProvider provider, String label) {
    HapticFeedback.selectionClick();
    Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, anim, __) => FadeTransition(
        opacity: anim,
        child: _FullscreenViewer(provider: provider, label: label),
      ),
    ));
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
    final verdict = (_hasResult && _selected != null &&
            _heightCm != null && _weightKg != null)
        ? _computeVerdict(_selected!, _heightCm!, _weightKg!)
        : null;

    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.only(bottom: Sp.xxl),
              children: [
                // ── Masthead.
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                  child: Row(
                    children: [
                      const MirrorlyWordmark(fontSize: 34),
                      const Spacer(),
                      _SettingsCog(onTap: () => context.push('/settings')),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Text(
                    _hasResult
                        ? 'The after is rendered. Now earn it.'
                        : 'Your body. Rebuilt.',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 15, height: 1.35,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(height: Sp.lg),

                if (!_hasResult) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                    child: Text('PICK THE MISSION',
                        style: AppTypography.label.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 10.5, letterSpacing: 2.8,
                          fontWeight: FontWeight.w800,
                        )),
                  ),
                  const SizedBox(height: 10),
                  for (final g in _goals) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Sp.lg, vertical: 4),
                      child: _GoalCard(
                        goal: g,
                        selected: _selected?.id == g.id,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selected = g);
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: Sp.md),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                    child: PrimaryCta(
                      label: 'Scan Your Body',
                      icon: Icons.accessibility_new_rounded,
                      meta: 'Full-body photo · AI glow-up render',
                      onTap: _begin,
                    ),
                  ).animate().fadeIn(delay: 120.ms, duration: 400.ms),
                ] else ...[
                  // ── 1. THE AFTER — FULL-BLEED before/after. Tap a
                  //    pane to inspect it fullscreen.
                  _BeforeAfter(
                    beforePath: _beforePath!,
                    afterUrl:   _afterUrl!,
                    goalName:   _selected?.name ?? 'MISSION',
                    onTapBefore: () => _openViewer(
                        FileImage(File(_beforePath!)), 'NOW'),
                    onTapAfter: () => _openViewer(
                        NetworkImage(_afterUrl!), 'COMMITTED'),
                  ).animate().fadeIn(duration: 400.ms),

                  const SizedBox(height: Sp.md),

                  // ── 2. THE VERDICT — the rating + breakdown.
                  if (verdict != null)
                    _VerdictCard(verdict: verdict, goal: _selected!)
                        .animate()
                        .fadeIn(delay: 120.ms, duration: 400.ms),

                  const SizedBox(height: Sp.md),

                  // ── 3. THE ROAD — the mission protocol.
                  if (_selected != null)
                    _PlanCard(goal: _selected!)
                        .animate()
                        .fadeIn(delay: 200.ms, duration: 400.ms),

                  const SizedBox(height: Sp.md),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                    child: Row(
                      children: [
                        Expanded(
                          child: _GhostButton(
                            label: 'NEW SCAN',
                            onTap: () async {
                              HapticFeedback.selectionClick();
                              await _reset();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _GhostButton(
                            label: 'CHANGE MISSION',
                            onTap: () async {
                              HapticFeedback.selectionClick();
                              await _reset();
                              if (mounted) setState(() => _selected = null);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),

            // ── Rendering overlay.
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.82),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 34, height: 34,
                          child: CircularProgressIndicator(
                            color: AppColors.red, strokeWidth: 2.4),
                        ),
                        const SizedBox(height: 22),
                        Text('RENDERING THE AFTER',
                            style: AppTypography.label.copyWith(
                              color: AppColors.red,
                              fontSize: 12, letterSpacing: 3.2,
                              fontWeight: FontWeight.w900,
                            )),
                        const SizedBox(height: 8),
                        Text('Same face. New frame.\nThis takes up to a minute.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 13, height: 1.45,
                            )),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Stats sheet — height + weight, metric / imperial ───────────────
class _StatsSheet extends StatefulWidget {
  final double? initialHeightCm;
  final double? initialWeightKg;
  final void Function(double heightCm, double weightKg) onDone;
  const _StatsSheet({
    required this.initialHeightCm,
    required this.initialWeightKg,
    required this.onDone,
  });

  @override
  State<_StatsSheet> createState() => _StatsSheetState();
}

class _StatsSheetState extends State<_StatsSheet> {
  bool _metric = true;
  late final TextEditingController _cm;
  late final TextEditingController _kg;
  late final TextEditingController _ft;
  late final TextEditingController _inch;
  late final TextEditingController _lb;

  @override
  void initState() {
    super.initState();
    final h = widget.initialHeightCm;
    final w = widget.initialWeightKg;
    _cm = TextEditingController(text: h?.round().toString() ?? '');
    _kg = TextEditingController(text: w?.round().toString() ?? '');
    final totalIn = h != null ? h / 2.54 : null;
    _ft   = TextEditingController(
        text: totalIn != null ? (totalIn ~/ 12).toString() : '');
    _inch = TextEditingController(
        text: totalIn != null ? (totalIn % 12).round().toString() : '');
    _lb   = TextEditingController(
        text: w != null ? (w * 2.20462).round().toString() : '');
  }

  @override
  void dispose() {
    _cm.dispose(); _kg.dispose(); _ft.dispose(); _inch.dispose(); _lb.dispose();
    super.dispose();
  }

  (double, double)? _read() {
    double? h, w;
    if (_metric) {
      h = double.tryParse(_cm.text.trim());
      w = double.tryParse(_kg.text.trim());
    } else {
      final ft = double.tryParse(_ft.text.trim());
      final inch = double.tryParse(
          _inch.text.trim().isEmpty ? '0' : _inch.text.trim());
      final lb = double.tryParse(_lb.text.trim());
      if (ft != null && inch != null) h = (ft * 12 + inch) * 2.54;
      if (lb != null) w = lb / 2.20462;
    }
    if (h == null || w == null) return null;
    if (h < 120 || h > 230 || w < 35 || w > 250) return null;
    return (h, w);
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 18, 22, 18 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR NUMBERS',
              style: AppTypography.label.copyWith(
                color: AppColors.red,
                fontSize: 11, letterSpacing: 3,
                fontWeight: FontWeight.w900,
              )),
          const SizedBox(height: 4),
          Text('Height and weight power the verdict — your score, your '
              'targets, your timeline. Asked once, remembered.',
              style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 14),
          Row(
            children: [
              _unitChip('CM / KG', _metric, () => setState(() => _metric = true)),
              const SizedBox(width: 8),
              _unitChip('FT / LB', !_metric, () => setState(() => _metric = false)),
            ],
          ),
          const SizedBox(height: 14),
          if (_metric)
            Row(
              children: [
                Expanded(child: _field(_cm, 'Height', 'cm')),
                const SizedBox(width: 10),
                Expanded(child: _field(_kg, 'Weight', 'kg')),
              ],
            )
          else
            Row(
              children: [
                Expanded(child: _field(_ft, 'Height', 'ft')),
                const SizedBox(width: 8),
                Expanded(child: _field(_inch, '', 'in')),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: _field(_lb, 'Weight', 'lb')),
              ],
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: AppColors.red,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  final v = _read();
                  if (v == null) {
                    HapticFeedback.heavyImpact();
                    return;
                  }
                  widget.onDone(v.$1, v.$2);
                  Navigator.pop(context, true);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text('LOCK IT IN',
                      textAlign: TextAlign.center,
                      style: AppTypography.label.copyWith(
                        color: Colors.white,
                        fontSize: 12.5, letterSpacing: 2.8,
                        fontWeight: FontWeight.w900,
                      )),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unitChip(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.red : AppColors.surface2,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(label,
            style: AppTypography.label.copyWith(
              color: active ? Colors.white : AppColors.textSecondary,
              fontSize: 10.5, letterSpacing: 1.8,
              fontWeight: FontWeight.w800,
            )),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String unit) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: AppTypography.bodySmall.copyWith(
          color: AppColors.textPrimary, fontSize: 16),
      decoration: InputDecoration(
        labelText: label.isEmpty ? null : label,
        suffixText: unit,
        labelStyle: AppTypography.bodySmall.copyWith(
            color: AppColors.textTertiary, fontSize: 13),
        suffixStyle: AppTypography.bodySmall.copyWith(
            color: AppColors.textTertiary, fontSize: 13),
        filled: true,
        fillColor: AppColors.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

// ─── Full-bleed before / after with fullscreen inspect ──────────────
class _BeforeAfter extends StatelessWidget {
  final String beforePath;
  final String afterUrl;
  final String goalName;
  final VoidCallback onTapBefore;
  final VoidCallback onTapAfter;
  const _BeforeAfter({
    required this.beforePath,
    required this.afterUrl,
    required this.goalName,
    required this.onTapBefore,
    required this.onTapAfter,
  });

  @override
  Widget build(BuildContext context) {
    // FULL-BLEED — edge to edge, bordered top and bottom only.
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border(
          top: BorderSide(
              color: AppColors.signalGreen.withValues(alpha: 0.5), width: 1),
          bottom: BorderSide(
              color: AppColors.signalGreen.withValues(alpha: 0.5), width: 1),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
            child: Row(
              children: [
                Container(
                  width: 5, height: 5,
                  decoration: const BoxDecoration(
                      color: AppColors.red, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('THE AFTER · $goalName',
                    style: AppTypography.label.copyWith(
                      color: AppColors.red,
                      fontSize: 10.5, letterSpacing: 3.0,
                      fontWeight: FontWeight.w900,
                    )),
                const Spacer(),
                Icon(Icons.zoom_out_map_rounded,
                    size: 13,
                    color: AppColors.textTertiary),
                const SizedBox(width: 4),
                Text('TAP TO INSPECT',
                    style: AppTypography.label.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 8.5, letterSpacing: 1.8,
                      fontWeight: FontWeight.w800,
                    )),
              ],
            ),
          ),
          SizedBox(
            height: 430,
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onTapBefore,
                    child: _pane(
                      child: Image.file(File(beforePath), fit: BoxFit.cover),
                      label: 'NOW',
                      labelColor: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                Container(width: 1.5, color: Colors.white),
                Expanded(
                  child: GestureDetector(
                    onTap: onTapAfter,
                    child: _pane(
                      child: Image.network(
                        afterUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, p) => p == null
                            ? child
                            : Container(
                                color: AppColors.surface2,
                                alignment: Alignment.center,
                                child: const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                      color: AppColors.red, strokeWidth: 2),
                                ),
                              ),
                        errorBuilder: (_, __, ___) => Container(
                          color: AppColors.surface2,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_rounded,
                              color: AppColors.surface3, size: 32),
                        ),
                      ),
                      label: 'COMMITTED',
                      labelColor: AppColors.signalGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pane({
    required Widget child,
    required String label,
    required Color labelColor,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: 0, right: 0, bottom: 0, height: 44,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.65),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(label,
                style: GoogleFonts.inter(
                  color: labelColor,
                  fontSize: 10, letterSpacing: 2.6,
                  fontWeight: FontWeight.w900,
                )),
          ),
        ),
      ],
    );
  }
}

// ─── Fullscreen pinch-zoom viewer ───────────────────────────────────
class _FullscreenViewer extends StatelessWidget {
  final ImageProvider provider;
  final String label;
  const _FullscreenViewer({required this.provider, required this.label});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Image(image: provider, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 8, right: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.5),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).pop(),
                  child: const SizedBox(
                    width: 44, height: 44,
                    child: Icon(Icons.close_rounded,
                        color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16, bottom: 12,
              child: Text(label,
                  style: AppTypography.label.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11, letterSpacing: 2.6,
                    fontWeight: FontWeight.w900,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── THE VERDICT — the rating + breakdown ───────────────────────────
class _VerdictCard extends StatelessWidget {
  final _Verdict verdict;
  final _BodyGoal goal;
  const _VerdictCard({required this.verdict, required this.goal});

  @override
  Widget build(BuildContext context) {
    final v = verdict;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border(
          top: BorderSide(
              color: AppColors.red.withValues(alpha: 0.35), width: 1),
          bottom: BorderSide(
              color: AppColors.red.withValues(alpha: 0.35), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 5, height: 5,
                decoration: const BoxDecoration(
                    color: AppColors.red, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text('THE VERDICT · ${v.frameName}',
                  style: AppTypography.label.copyWith(
                    color: AppColors.red,
                    fontSize: 10.5, letterSpacing: 3.0,
                    fontWeight: FontWeight.w900,
                  )),
            ],
          ),

          const SizedBox(height: 14),

          // Score row — NOW vs POTENTIAL, the face-card language.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _scoreCol('NOW', v.scoreNow, AppColors.textPrimary,
                  CrossAxisAlignment.start),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.signalGreen.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                      color: AppColors.signalGreen.withValues(alpha: 0.55),
                      width: 0.9),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.trending_up_rounded,
                        color: AppColors.signalGreen, size: 13),
                    const SizedBox(width: 4),
                    Text('+${v.scorePotential - v.scoreNow}',
                        style: AppTypography.label.copyWith(
                          color: AppColors.signalGreen,
                          fontSize: 13, letterSpacing: 0.4,
                          fontWeight: FontWeight.w900,
                        )),
                  ],
                ),
              ),
              _scoreCol('POTENTIAL', v.scorePotential,
                  AppColors.signalGreen, CrossAxisAlignment.end),
            ],
          ),

          const SizedBox(height: 12),

          // Frame read — the line that makes it personal.
          Text(v.frameRead,
              style: GoogleFonts.playfairDisplay(
                color: AppColors.textPrimary,
                fontSize: 15, height: 1.4,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w700,
              )),

          const SizedBox(height: 14),
          Container(height: 0.6, color: AppColors.divider),
          const SizedBox(height: 12),

          // The breakdown grid.
          _row('EST. BODY FAT', v.bfBand),
          _row('WEIGHT',
              '${v.weightNow.round()} kg  →  ${v.weightTarget.round()} kg'),
          _row('THE CHANGE', v.changeLine),
          _row('TIMELINE', v.timeline),
          _row('FIRST VISIBLE WIN', v.firstChange),

          const SizedBox(height: 6),
          Text('Estimates from your height and weight. The mirror is the '
              'judge — the weekly photo settles it.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
              )),
        ],
      ),
    );
  }

  Widget _scoreCol(
      String label, int value, Color color, CrossAxisAlignment align) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: AppTypography.label.copyWith(
              color: label == 'NOW'
                  ? AppColors.textTertiary
                  : AppColors.signalGreen.withValues(alpha: 0.85),
              fontSize: 9.5, letterSpacing: 2.4,
              fontWeight: FontWeight.w900,
            )),
        const SizedBox(height: 2),
        Text('$value',
            style: GoogleFonts.playfairDisplay(
              color: color,
              fontSize: 46, height: 0.95,
              letterSpacing: -2.0,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w900,
              shadows: label == 'NOW'
                  ? null
                  : [
                      Shadow(
                          color: AppColors.signalGreen.withValues(alpha: 0.4),
                          blurRadius: 18),
                    ],
            )),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(label,
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 10, letterSpacing: 1.8,
                  fontWeight: FontWeight.w800,
                )),
          ),
          Expanded(
            child: Text(value,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 13.5, height: 1.35,
                  fontWeight: FontWeight.w600,
                )),
          ),
        ],
      ),
    );
  }
}

// ─── Goal card ──────────────────────────────────────────────────────
class _GoalCard extends StatelessWidget {
  final _BodyGoal goal;
  final bool selected;
  final VoidCallback onTap;
  const _GoalCard({
    required this.goal,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.surface2 : AppColors.surface1,
            borderRadius: BorderRadius.circular(Rd.lg),
            border: Border.all(
              color: selected ? AppColors.red : AppColors.surface3,
              width: selected ? 1.2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.red.withValues(alpha: 0.22),
                      blurRadius: 18, spreadRadius: 0),
                  ]
                : const [],
          ),
          child: Row(
            children: [
              Container(
                width: 42, height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.red : AppColors.surface2,
                  shape: BoxShape.circle,
                ),
                child: Icon(goal.icon,
                    size: 22,
                    color: selected ? Colors.black : AppColors.textSecondary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(goal.name,
                        style: AppTypography.label.copyWith(
                          color: AppColors.textPrimary,
                          fontSize: 14, letterSpacing: 2.6,
                          fontWeight: FontWeight.w900,
                        )),
                    const SizedBox(height: 3),
                    Text(goal.oneLine,
                        style: GoogleFonts.inter(
                          color: selected
                              ? AppColors.red
                              : AppColors.textSecondary,
                          fontSize: 12.5, height: 1.3,
                          fontStyle: FontStyle.italic,
                        )),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 20,
                color: selected ? AppColors.red : AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Mission plan card — full-bleed ─────────────────────────────────
class _PlanCard extends StatelessWidget {
  final _BodyGoal goal;
  const _PlanCard({required this.goal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 14),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border(
          top: BorderSide(
              color: AppColors.red.withValues(alpha: 0.32), width: 0.9),
          bottom: BorderSide(
              color: AppColors.red.withValues(alpha: 0.32), width: 0.9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('THE ${goal.name} PROTOCOL',
              style: AppTypography.label.copyWith(
                color: AppColors.red,
                fontSize: 11, letterSpacing: 3.0,
                fontWeight: FontWeight.w900,
              )),
          const SizedBox(height: 4),
          Text('The render is the destination. This is the road.',
              style: GoogleFonts.inter(
                color: AppColors.textSecondary,
                fontSize: 12.5, height: 1.35,
                fontStyle: FontStyle.italic,
              )),
          const SizedBox(height: 14),
          for (final (move, why) in goal.plan) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    width: 6, height: 6,
                    decoration: const BoxDecoration(
                        color: AppColors.red, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(move,
                            style: AppTypography.label.copyWith(
                              color: AppColors.textPrimary,
                              fontSize: 12, letterSpacing: 1.8,
                              fontWeight: FontWeight.w800,
                            )),
                        const SizedBox(height: 2),
                        Text(why,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 12.5, height: 1.35,
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 2),
          Text('Coaching, not medical advice. Train within your limits.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
              )),
        ],
      ),
    );
  }
}

// ─── Small chrome ───────────────────────────────────────────────────
class _SettingsCog extends StatelessWidget {
  final VoidCallback onTap;
  const _SettingsCog({required this.onTap});
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
            border: Border.all(color: AppColors.surface3, width: 0.6),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.tune,
              size: 18, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.red.withValues(alpha: 0.5), width: 1),
          ),
          child: Text(label,
              style: AppTypography.label.copyWith(
                color: AppColors.red,
                fontSize: 11.5, letterSpacing: 2.2,
                fontWeight: FontWeight.w900,
              )),
        ),
      ),
    );
  }
}
