import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../models/technique.dart';
import '../../services/aura_verdict_service.dart';
import '../../services/share_service.dart';
import '../../theme/auralay_app_colors.dart';
import '../../theme/auralay_app_theme.dart';
import '../../theme/auralay_app_typography.dart';

class PostSessionScreen extends StatelessWidget {
  final Map<String, dynamic> results;
  const PostSessionScreen({super.key, required this.results});

  // ── Parse results ──────────────────────────────────────────────────────────
  int    get _auraGain     => results['auraGain']    as int?    ?? 0;
  int    get _seconds      => results['seconds']     as int?    ?? 0;
  String get _techniqueName=> results['technique']   as String? ?? 'SESSION';
  String get _techniqueId  => results['techniqueId'] as String? ?? '';
  double get _eyeContact   => results['eyeContact']  as double? ?? 0.0;
  double get _stability    => results['stability']   as double? ?? 0.0;
  double get _smile        => results['smile']       as double? ?? 0.0;
  double get _blinkRate    => results['blinkRate']   as double? ?? 0.0;
  // New 4-dimension scoring — available when the training screen ran with
  // the upgraded detector; fall back to 0 for legacy sessions.
  double get _presencePct  => results['presence']    as double? ?? 0.0;
  double get _warmthPct    => results['warmth']      as double? ?? 0.0;
  double get _composurePct => results['composure']   as double? ?? 0.0;
  double get _rangePct     => results['range']       as double? ?? 0.0;
  Uint8List? get _photoBytes => results['photoBytes'] as Uint8List?;
  double? get _eyeY        => results['eyeYNormalized'] as double?;

  Map<String, double> get _dimensions => {
    'Presence':  _presencePct,
    'Composure': _composurePct,
    'Warmth':    _warmthPct,
    'Range':     _rangePct,
  };

  String get _durationLabel {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    if (m == 0) return '${s}s';
    return '${m}m ${s}s';
  }

  // ── Dynamic callout generation from real metrics ────────────────────────────
  List<_Callout> get _weaknesses {
    final list = <_Callout>[];

    if (_eyeContact < 55) {
      list.add(_Callout(
        metric: 'Eye contact — ${_eyeContact.toStringAsFixed(0)}%',
        detail: _eyeContact < 30
            ? 'You broke under pressure. The gaze needs to become default, not effort.'
            : 'Holding most of the time but flinching at the threshold. Train the 4-second hold specifically.',
        isPositive: false,
      ));
    }

    if (_blinkRate > 22) {
      list.add(_Callout(
        metric: 'Blink rate — ${_blinkRate.toStringAsFixed(0)}/min',
        detail: 'Your nervous system is running hot. ${_blinkRate.toStringAsFixed(0)} blinks per minute reads as anxious. Target is under 15.',
        isPositive: false,
      ));
    }

    if (_stability < 60) {
      list.add(_Callout(
        metric: 'Head movement — ${_stability.toStringAsFixed(0)}%',
        detail: 'Too much movement. The micro-adjustments are broadcasting discomfort. Lock the head first, let the eyes do the work.',
        isPositive: false,
      ));
    }

    if (_smile < 20 && _techniqueId == 'delayed_smile') {
      list.add(_Callout(
        metric: 'Smile onset — insufficient',
        detail: 'The smile is not building from neutral. Start with a completely flat face. The contrast is the whole technique.',
        isPositive: false,
      ));
    }

    if (list.isEmpty) {
      list.add(_Callout(
        metric: 'Nothing major broke',
        detail: 'Clean session. Now push the duration.',
        isPositive: false,
      ));
    }

    return list.take(3).toList();
  }

  List<_Callout> get _strengths {
    final list = <_Callout>[];

    if (_eyeContact >= 65) {
      list.add(_Callout(
        metric: 'Eye contact — ${_eyeContact.toStringAsFixed(0)}%',
        detail: _eyeContact >= 80
            ? 'Dominant range. Most people never reach this. Keep it here.'
            : 'Solid. You are in the confident range. Now make it effortless.',
        isPositive: true,
      ));
    }

    if (_stability >= 72) {
      list.add(_Callout(
        metric: 'Head stability — ${_stability.toStringAsFixed(0)}%',
        detail: 'The stillness is there. That compression is landing.',
        isPositive: true,
      ));
    }

    if (_blinkRate >= 8 && _blinkRate <= 18) {
      list.add(_Callout(
        metric: 'Blink rate — ${_blinkRate.toStringAsFixed(0)}/min',
        detail: 'Your system is calm. That reads as composure to everyone watching.',
        isPositive: true,
      ));
    }

    if (_smile >= 45 && (_techniqueId == 'delayed_smile' || _techniqueId == 'smize')) {
      list.add(_Callout(
        metric: 'Smile authenticity — ${_smile.toStringAsFixed(0)}%',
        detail: 'The eyes are in it. That is the Duchenne marker. That is what makes it real.',
        isPositive: true,
      ));
    }

    if (list.isEmpty && _auraGain > 0) {
      list.add(_Callout(
        metric: 'Aura gain — +$_auraGain',
        detail: 'Something landed today. Build on it.',
        isPositive: true,
      ));
    }

    return list.take(2).toList();
  }

  // ── Share — build verdict + fire off-screen card render ────────────────────
  Future<void> _shareCard(BuildContext context) async {
    HapticFeedback.mediumImpact();
    // Prefer the 4-dimension verdict when the session recorded them.
    final hasDimensions = (_presencePct + _composurePct + _warmthPct + _rangePct) > 0;
    final verdict = hasDimensions
        ? AuraVerdictService.fromSession(
            score:        _auraGain,
            presencePct:  _presencePct,
            composurePct: _composurePct,
            warmthPct:    _warmthPct,
            rangePct:     _rangePct,
            eyeContactPct: _eyeContact,
            stabilityPct:  _stability,
            smilePct:      _smile,
            blinkRate:     _blinkRate,
          )
        : AuraVerdictService.fromSessionAverages(
            score:         _auraGain,
            eyeContactPct: _eyeContact,
            stabilityPct:  _stability,
            smilePct:      _smile,
            blinkRate:     _blinkRate,
          );
    await ShareService.shareAuraResult(
      context:        context,
      photoBytes:     _photoBytes,
      eyeYNormalized: _eyeY,
      score:          verdict.score,
      tier:           verdict.tier,
      roast:          verdict.roast,
      dimensions:     hasDimensions ? _dimensions : verdict.dimensionPcts,
      techniqueName:  _techniqueName,
      text: 'My AURA score is ${verdict.score} — ${verdict.tier}. Test yours on Mirrorly: mirrorly.app',
    );
  }

  // ── Verdict copy ────────────────────────────────────────────────────────────
  String get _verdictText {
    // Technique-specific completion line if it's a clean session
    if (_eyeContact >= 65 && _stability >= 65) {
      try {
        final t = Technique.all.firstWhere((t) => t.id == _techniqueId);
        return t.completionLine;
      } catch (_) {}
    }

    // Dynamic verdicts based on what happened
    if (_eyeContact < 40 && _stability < 50) {
      return "You're reacting to the room instead of owning it.\nFix the stillness first. Then the gaze.";
    }
    if (_eyeContact < 40) {
      return "The gaze is the whole foundation. Everything else is decoration until this is solid.";
    }
    if (_blinkRate > 25) {
      return "Your body is broadcasting anxiety before you say a word.\nSlow the blink down. Let the system settle.";
    }
    if (_stability < 45) {
      return "Every movement you make is costing you presence.\nStill head. Deliberate movement. Nothing else.";
    }
    if (_eyeContact >= 75 && _stability >= 75) {
      return "That is what presence looks like.\nKeep training at this level.";
    }
    if (_eyeContact >= 65) {
      return "The gaze is there. Now integrate the stillness and you become someone different.";
    }
    return "One session is a data point. Keep showing up.";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _Header(
                techniqueName: _techniqueName,
                auraGain: _auraGain,
                duration: _durationLabel,
              ),

              const SizedBox(height: Sp.xl),

              // Score strip
              _ScoreStrip(
                eyeContact: _eyeContact,
                stability: _stability,
                smile: _smile,
                blinkRate: _blinkRate,
              ),

              const SizedBox(height: Sp.xl),

              // What gave you away
              _SectionLabel(
                label: 'WHAT GAVE YOU AWAY',
                color: AppColors.signalRed,
              ),
              const SizedBox(height: Sp.sm),
              ..._weaknesses.asMap().entries.map((e) =>
                _CalloutCard(callout: e.value)
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 80 * e.key + 100),
                      duration: 350.ms)
                  .slideX(begin: -0.04, end: 0,
                      delay: Duration(milliseconds: 80 * e.key + 100),
                      duration: 350.ms, curve: Curves.easeOut)),

              const SizedBox(height: Sp.lg),

              // What landed
              _SectionLabel(
                label: 'WHAT LANDED',
                color: AppColors.signalGreen,
              ),
              const SizedBox(height: Sp.sm),
              ..._strengths.asMap().entries.map((e) =>
                _CalloutCard(callout: e.value)
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 80 * e.key + 300),
                      duration: 350.ms)
                  .slideX(begin: -0.04, end: 0,
                      delay: Duration(milliseconds: 80 * e.key + 300),
                      duration: 350.ms, curve: Curves.easeOut)),

              const SizedBox(height: Sp.xl),

              // Verdict
              _VerdictCard(text: _verdictText),

              const SizedBox(height: Sp.xl),

              // ── Primary action: SHARE the result (the viral engine) ──
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => _shareCard(context),
                  child: const Text('SHARE YOUR AURA',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14, letterSpacing: 2.6,
                    )),
                ),
              ),
              const SizedBox(height: Sp.sm),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppColors.accent.withValues(alpha: 0.55), width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => context.go('/train'),
                  child: const Text('Train again'),
                ),
              ),
              const SizedBox(height: Sp.sm),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => context.go('/you'),
                  child: const Text('See progress'),
                ),
              ),
              const SizedBox(height: Sp.md),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final String techniqueName;
  final int auraGain;
  final String duration;

  const _Header({
    required this.techniqueName,
    required this.auraGain,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(techniqueName.toUpperCase(),
          style: AppTypography.techniqueName)
          .animate().fadeIn(duration: 400.ms),

        const SizedBox(height: Sp.xs),

        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('Breakdown',
              style: AppTypography.h1)
              .animate().fadeIn(delay: 60.ms, duration: 400.ms),

            const Spacer(),

            if (auraGain > 0)
              Text('+$auraGain AURA',
                style: AppTypography.label.copyWith(
                  color: AppColors.accent, letterSpacing: 1.5, fontSize: 12))
                .animate().fadeIn(delay: 200.ms, duration: 400.ms),
          ],
        ),

        const SizedBox(height: Sp.xs),

        Text(duration,
          style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary))
          .animate().fadeIn(delay: 120.ms, duration: 400.ms),
      ],
    );
  }
}

// ── Score strip ───────────────────────────────────────────────────────────────
class _ScoreStrip extends StatelessWidget {
  final double eyeContact;
  final double stability;
  final double smile;
  final double blinkRate;

  const _ScoreStrip({
    required this.eyeContact,
    required this.stability,
    required this.smile,
    required this.blinkRate,
  });

  @override
  Widget build(BuildContext context) {
    final blinkOk = blinkRate >= 8 && blinkRate <= 20;
    return Row(
      children: [
        _ScorePill(label: 'EYES',  value: eyeContact,    isPercent: true),
        const SizedBox(width: Sp.sm),
        _ScorePill(label: 'STILL', value: stability,     isPercent: true),
        const SizedBox(width: Sp.sm),
        _ScorePill(label: 'SMILE', value: smile,         isPercent: true),
        const SizedBox(width: Sp.sm),
        _ScorePill(label: 'BLINK',
          value: blinkRate, isPercent: false,
          suffix: '/m', good: blinkOk ? 1.0 : 0.3),
      ],
    ).animate().fadeIn(delay: 50.ms, duration: 400.ms);
  }
}

class _ScorePill extends StatelessWidget {
  final String label;
  final double value;
  final bool isPercent;
  final String suffix;
  final double? good;

  const _ScorePill({
    required this.label,
    required this.value,
    required this.isPercent,
    this.suffix = '%',
    this.good,
  });

  Color get _color {
    final g = good ?? (value / 100);
    if (g >= 0.65) return AppColors.signalGreen;
    if (g >= 0.35) return AppColors.signalAmber;
    return AppColors.signalRed;
  }

  @override
  Widget build(BuildContext context) {
    final displayVal = isPercent
        ? '${value.toStringAsFixed(0)}%'
        : '${value.toStringAsFixed(0)}$suffix';

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Sp.sm),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(Rd.md),
          border: Border.all(color: _color.withValues(alpha: 0.22)),
        ),
        child: Column(
          children: [
            Text(displayVal,
              style: AppTypography.h3.copyWith(
                color: _color, fontSize: 16, letterSpacing: -0.3)),
            const SizedBox(height: 3),
            Text(label,
              style: AppTypography.label.copyWith(
                fontSize: 8, letterSpacing: 1.5,
                color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(label,
      style: AppTypography.label.copyWith(
          color: color, letterSpacing: 1.8));
  }
}

// ── Callout card ──────────────────────────────────────────────────────────────
class _Callout {
  final String metric;
  final String detail;
  final bool isPositive;
  const _Callout({required this.metric, required this.detail,
      required this.isPositive});
}

class _CalloutCard extends StatelessWidget {
  final _Callout callout;
  const _CalloutCard({required this.callout});

  @override
  Widget build(BuildContext context) {
    final accent = callout.isPositive ? AppColors.signalGreen : AppColors.signalRed;
    return Container(
      margin: const EdgeInsets.only(bottom: Sp.sm),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 2, height: 36,
            margin: const EdgeInsets.only(top: 2, right: Sp.sm),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(callout.metric,
                  style: AppTypography.h3.copyWith(
                    fontSize: 13, letterSpacing: -0.1)),
                const SizedBox(height: 4),
                Text(callout.detail,
                  style: AppTypography.bodySmall.copyWith(
                    height: 1.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Verdict card ──────────────────────────────────────────────────────────────
class _VerdictCard extends StatelessWidget {
  final String text;
  const _VerdictCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.accentBorder),
        boxShadow: [BoxShadow(
          color: AppColors.accent.withValues(alpha: 0.05),
          blurRadius: 24, spreadRadius: 0,
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VERDICT', style: AppTypography.techniqueName),
          const SizedBox(height: Sp.md),
          Text(text,
            style: AppTypography.body.copyWith(
              height: 1.75,
              color: AppColors.textPrimary,
            )),
        ],
      ),
    )
    .animate()
    .fadeIn(delay: 450.ms, duration: 500.ms)
    .slideY(begin: 0.05, end: 0,
        delay: 450.ms, duration: 500.ms, curve: Curves.easeOut);
  }
}
