import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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
/// Flow: pick a mission preset (SHRED / BUILD / ATHLETIC) → full-body
/// photo (camera or gallery) → Nano Banana renders "you if you commit"
/// → before/after reveal + the mission's training protocol.
///
/// Plumbing reuse, zero new backend:
///   · render        → MirrorApiService.maximizeOnly with a body brief
///   · gating        → Pro-only (PaywallGate), shares the 3/week
///                     render budget (markMirrorRenderUsed)
///   · consent       → AiConsentDialog.ensure before any photo leaves
///                     the device (App Store 5.1.1(i)/5.1.2(i))
///   · persistence   → SharedPreferences (goal + before path + after
///                     url) so the tab restores the last transformation
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
  /// The render brief handed to the Nano Banana edit on the backend.
  final List<String> brief;
  /// The mission protocol — title + rows of (move, why).
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
      'dramatic but realistic healthy fat loss',
      'lean defined physique, visible jawline and neck definition',
      'same person, same face, same identity',
      'natural lighting, photorealistic',
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
      'add significant lean muscle mass',
      'broader shoulders, fuller chest and arms, athletic V-taper',
      'same person, same face, same identity',
      'natural realistic physique, photorealistic',
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
      'athletic body recomposition, lean muscular definition',
      'upright confident posture, athletic proportions',
      'same person, same face, same identity',
      'natural lighting, photorealistic',
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

class _BodyTabScreenState extends State<BodyTabScreen> {
  static const _kGoal   = 'body.goal.v1';
  static const _kBefore = 'body.before.path.v1';
  static const _kAfter  = 'body.after.url.v1';

  _BodyGoal? _selected;
  String? _beforePath;
  String? _afterUrl;
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
    if (!mounted) return;
    _BodyGoal? goal;
    for (final g in _goals) {
      if (g.id == goalId) goal = g;
    }
    setState(() {
      _selected = goal;
      _beforePath = (before != null && File(before).existsSync()) ? before : null;
      _afterUrl   = after;
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selected != null) await prefs.setString(_kGoal, _selected!.id);
    if (_beforePath != null) await prefs.setString(_kBefore, _beforePath!);
    if (_afterUrl != null) await prefs.setString(_kAfter, _afterUrl!);
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

    // Pro gate — body renders are Pro, same as face renders.
    final pro = await PaywallGate.isPro();
    if (!mounted) return;
    if (!pro) {
      await context.push('/paywall', extra: {'source': 'body_locked'});
      return;
    }
    // Shared weekly render budget.
    if (await LocalStoreService.mirrorRendersThisWeek() >=
        LocalStoreService.kRendersPerWeek) {
      _notice('All ${LocalStoreService.kRendersPerWeek} weekly renders used. '
          'They renew at the start of your next billing week.');
      return;
    }
    // AI consent before any photo leaves the device.
    if (!mounted || !await AiConsentDialog.ensure(context)) return;

    final source = await _pickSource();
    if (source == null || !mounted) return;

    XFile? shot;
    try {
      shot = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1440,
        imageQuality: 88,
      );
    } catch (_) {}
    if (shot == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final bytes = await shot.readAsBytes();
      final url = await MirrorApiService.maximizeOnly(
        imageBytes: bytes,
        improve: goal.brief,
      );
      await LocalStoreService.markMirrorRenderUsed();
      if (!mounted) return;
      setState(() {
        _beforePath = shot!.path;
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
                  // ── Mission picker.
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
                  // ── THE AFTER — before/after reveal.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                    child: _BeforeAfter(
                      beforePath: _beforePath!,
                      afterUrl:   _afterUrl!,
                      goalName:   _selected?.name ?? 'MISSION',
                    ),
                  ).animate().fadeIn(duration: 400.ms),

                  const SizedBox(height: Sp.lg),

                  // ── The mission protocol.
                  if (_selected != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                      child: _PlanCard(goal: _selected!),
                    ).animate().fadeIn(delay: 140.ms, duration: 400.ms),

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
              color: selected
                  ? AppColors.red
                  : AppColors.surface3,
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
                  color: selected
                      ? AppColors.red
                      : AppColors.surface2,
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

// ─── Before / after reveal ──────────────────────────────────────────
class _BeforeAfter extends StatelessWidget {
  final String beforePath;
  final String afterUrl;
  final String goalName;
  const _BeforeAfter({
    required this.beforePath,
    required this.afterUrl,
    required this.goalName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(
            color: AppColors.signalGreen.withValues(alpha: 0.5), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.signalGreen.withValues(alpha: 0.18),
            blurRadius: 24, spreadRadius: -4),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
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
              ],
            ),
          ),
          SizedBox(
            height: 340,
            child: Row(
              children: [
                Expanded(
                  child: _pane(
                    child: Image.file(File(beforePath), fit: BoxFit.cover),
                    label: 'NOW',
                    labelColor: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                Container(width: 1.5, color: Colors.white),
                Expanded(
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

// ─── Mission plan card ──────────────────────────────────────────────
class _PlanCard extends StatelessWidget {
  final _BodyGoal goal;
  const _PlanCard({required this.goal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(
            color: AppColors.red.withValues(alpha: 0.32), width: 0.9),
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
