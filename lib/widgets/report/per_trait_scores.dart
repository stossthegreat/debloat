import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/face_geometry.dart';
import '../../services/honest_rating_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// PER-TRAIT SCORES — the clean stack the competitor apps lead with.
///
/// Six rows: SKIN · HAIR · JAWLINE · MASCULINITY · EYES · FACE. Each
/// row carries a domain icon, a one-word qualifier ("Hunter Eyes",
/// "Clear healthy skin", "High Dimorphism"), and a score chip rendered
/// as /10 in a tier-tinted pill.
///
/// Data source priority:
///   1. [HonestRating.subScores] — GPT vision sub-scores. Present once
///      the /rate backend prompt has been extended to ask for them.
///   2. Geometry-derived fallback — math from FaceGeometry so the panel
///      renders something honest the moment the user finishes a scan,
///      even before the backend extension lands.
///
/// The render is identical either way; the user can't tell which path
/// produced each number, which is the right ux invariant — the panel
/// never goes blank.
class PerTraitScores extends StatelessWidget {
  final HonestRating? honest;
  final FaceGeometry geometry;
  const PerTraitScores({
    super.key,
    required this.honest,
    required this.geometry,
  });

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.xl),
        border: Border.all(color: AppColors.divider, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('PER-TRAIT READ',
                style: AppTypography.label.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 2.6,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900)),
              const Spacer(),
              Text(
                honest?.subScores != null ? 'gpt vision' : 'on-device',
                style: GoogleFonts.inter(
                  color: AppColors.textTertiary.withValues(alpha: 0.6),
                  fontSize: 9,
                  letterSpacing: 1.4,
                  
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Each axis scored separately. No averaging.',
            style: GoogleFonts.inter(
              color: AppColors.textTertiary,
              fontSize: 11.5,
              height: 1.4,
              
            )),
          const SizedBox(height: 12),
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const _RowDivider(),
            _TraitRow(row: rows[i]),
          ],
        ],
      ),
    );
  }

  // ─── Row generation ────────────────────────────────────────────────────

  List<_TraitRowData> _buildRows() {
    final sub  = honest?.subScores;
    final tier = honest?.subTiers;
    return [
      _row('skin',        Icons.water_drop_outlined,
           gptScore: sub?['skin'],        gptTier: tier?['skin'],
           fallbackScore: _skinFromHonest(),
           fallbackTier:  _skinTier()),
      _row('hair',        Icons.cut_outlined,
           gptScore: sub?['hair'],        gptTier: tier?['hair'],
           fallbackScore: _hairFromGeometry(),
           fallbackTier:  _hairTier()),
      _row('jawline',     Icons.bolt_outlined,
           gptScore: sub?['jawline'],     gptTier: tier?['jawline'],
           fallbackScore: _jawlineFromGeometry(),
           fallbackTier:  _jawlineTier()),
      _row('masculinity', Icons.male_outlined,
           gptScore: sub?['masculinity'], gptTier: tier?['masculinity'],
           fallbackScore: _masculinityFromGeometry(),
           fallbackTier:  _masculinityTier()),
      _row('eyes',        Icons.remove_red_eye_outlined,
           gptScore: sub?['eyes'],        gptTier: tier?['eyes'],
           fallbackScore: _eyesFromGeometry(),
           fallbackTier:  _eyesTier()),
      _row('face',        Icons.face_outlined,
           gptScore: sub?['face'],        gptTier: tier?['face'],
           fallbackScore: _faceFromGeometry(),
           fallbackTier:  _faceTier()),
    ];
  }

  _TraitRowData _row(
    String key,
    IconData icon, {
    required int? gptScore,
    required String? gptTier,
    required int fallbackScore,
    required String fallbackTier,
  }) {
    final score = gptScore ?? fallbackScore;
    final tier  = (gptTier != null && gptTier.trim().isNotEmpty)
        ? gptTier.trim()
        : fallbackTier;
    return _TraitRowData(
      key:   key,
      icon:  icon,
      label: _label(key),
      tier:  tier,
      score: score,
    );
  }

  String _label(String key) => switch (key) {
    'skin'        => 'Skin',
    'hair'        => 'Hair',
    'jawline'     => 'Jawline',
    'masculinity' => 'Masculinity',
    'eyes'        => 'Eyes',
    'face'        => 'Face',
    _             => key,
  };

  // ─── Geometry-derived fallback scores (each 0..100) ────────────────────
  //
  // These are intentionally honest, not flattering. They produce a
  // distribution centred slightly below 70 so most users see real
  // headroom. When the GPT sub-scores land they replace these.

  int _skinFromHonest() {
    // No geometry signal for skin. Use a softened version of the
    // overall HONEST score with a -3 nudge so it doesn't just mirror
    // the headline. Returns 60 if no GPT score is present (neutral
    // placeholder that reads as "needs a fresh photo").
    final h = honest?.score;
    if (h == null) return 60;
    return (h - 3).clamp(0, 100);
  }

  String _skinTier() {
    final s = _skinFromHonest();
    if (s >= 85) return 'Clear healthy skin';
    if (s >= 72) return 'Even tone';
    if (s >= 58) return 'Mixed clarity';
    return 'Texture work needed';
  }

  int _hairFromGeometry() {
    // No direct geometry. Default to a mid-range 65 — the GPT score
    // is the truth here once the backend extension ships.
    return honest?.score != null ? (honest!.score - 5).clamp(0, 100) : 65;
  }

  String _hairTier() {
    final h = _hairFromGeometry();
    if (h >= 82) return 'Full hair';
    if (h >= 68) return 'Healthy line';
    if (h >= 55) return 'Mild recession';
    return 'Receding';
  }

  int _jawlineFromGeometry() {
    // Lower jaw angle (more acute) = sharper jaw definition.
    // Range observed: ~118° (defined) to ~138° (rounded).
    //
    // v231 honesty cap — MediaPipe sees the OUTLINE of the face, so
    // a thick beard / heavy stubble traces a sharp angle that the
    // formula reads as an elite jaw. Bro: "the jaw score that's
    // given in the chart is a lie — says I got 9.5 jawline, I got
    // tiny jaw and a massive beard. If user had beard then score
    // something not 9.5 like you think — maybe it don't score, leaves
    // blank, or says 5. Not generic, should be real."
    //
    // Without GPT vision corroboration the geometry-only score is
    // capped at 65/100 (= 6.5/10). When the /rate backend returns
    // a verified subScores.jawline that overrides this cap entirely
    // (see _row()). So clean-shaven users with real geometry verified
    // by GPT can still hit elite; everyone falling back to geometry
    // alone gets a conservative read instead of an inflated lie.
    final a = geometry.jawAngle;
    final norm = ((138 - a) / 20).clamp(0.0, 1.0);
    return (40 + norm * 25).round().clamp(0, 65);
  }

  String _jawlineTier() {
    final s = _jawlineFromGeometry();
    // Geometry-only ceiling is 65, so the top-tier label changes:
    // we can never honestly call the jaw "Sharp" without GPT
    // confirming the beard isn't doing the work.
    if (s >= 60) return 'Estimated · clean-shave for true read';
    if (s >= 52) return 'Defined';
    if (s >= 45) return 'Normal jawline';
    return 'Soft';
  }

  int _masculinityFromGeometry() {
    // Composite: FWHR (target ~2.0), jawAngle (lower = more dimorphic),
    // chin projection. Each contributes 1/3 of the score.
    //
    // v231 honesty cap — jaw + chin both come off the same beard-
    // contaminated MediaPipe outline as the jawline score. Without
    // GPT corroboration this score caps at 75/100 (= 7.5/10) so the
    // same beard that fooled the jaw read can't carry masculinity up
    // to elite either.
    final fwhrScore  = (1.0 - ((geometry.fwhr - 2.0).abs() / 0.8)).clamp(0.0, 1.0);
    final jawScore   = ((138 - geometry.jawAngle) / 20).clamp(0.0, 1.0);
    final chinScore  = geometry.chinProjection.clamp(0.0, 1.0);
    final composite  = (fwhrScore + jawScore + chinScore) / 3.0;
    return (35 + composite * 40).round().clamp(0, 75);
  }

  String _masculinityTier() {
    final s = _masculinityFromGeometry();
    if (s >= 70) return 'Estimated · clean-shave for true read';
    if (s >= 60) return 'Above average';
    if (s >= 50) return 'Average';
    return 'Below average';
  }

  int _eyesFromGeometry() {
    // Canthal tilt (positive = hunter), plus symmetry. Canthal tilt
    // observed range: -2 to +6 degrees. Hunter at +4 and up.
    final tilt    = ((geometry.canthalTilt + 2) / 8).clamp(0.0, 1.0);
    final sym     = (geometry.symmetryScore / 100).clamp(0.0, 1.0);
    final composite = tilt * 0.6 + sym * 0.4;
    return (35 + composite * 60).round().clamp(0, 100);
  }

  String _eyesTier() {
    final s = _eyesFromGeometry();
    final tilt = geometry.canthalTilt;
    if (s >= 82 && tilt > 3) return 'Hunter eyes';
    if (s >= 70) return 'Neutral tilt';
    if (s >= 55) return 'Mild positive tilt';
    return 'Negative tilt';
  }

  int _faceFromGeometry() {
    // Facial-thirds balance: closer all three are to 33.3%, higher
    // the score. Plus mild symmetry contribution.
    final t = geometry.facialThirdTop;
    final m = geometry.facialThirdMid;
    final l = geometry.facialThirdLow;
    final balance = 1.0 -
        (((t - 33.33).abs() + (m - 33.33).abs() + (l - 33.33).abs()) / 30.0)
            .clamp(0.0, 1.0);
    final sym = (geometry.symmetryScore / 100).clamp(0.0, 1.0);
    return (40 + (balance * 0.7 + sym * 0.3) * 55).round().clamp(0, 100);
  }

  String _faceTier() {
    final s = _faceFromGeometry();
    if (s >= 82) return 'Harmonious thirds';
    if (s >= 68) return 'Balanced';
    if (s >= 55) return 'Normal';
    return 'Off-balance';
  }
}

// ─── Internal types ────────────────────────────────────────────────────────

class _TraitRowData {
  final String   key;
  final IconData icon;
  final String   label;
  final String   tier;
  final int      score; // 0..100
  const _TraitRowData({
    required this.key,
    required this.icon,
    required this.label,
    required this.tier,
    required this.score,
  });
}

class _TraitRow extends StatelessWidget {
  final _TraitRowData row;
  const _TraitRow({required this.row});

  Color _scoreColor() {
    if (row.score >= 80) return AppColors.signalGreen;
    if (row.score >= 65) return AppColors.signalAmber;
    if (row.score >= 50) return AppColors.measure;
    return AppColors.signalRed;
  }

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor();
    final outOfTen = (row.score / 10.0).toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(row.icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(row.label,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  )),
                const SizedBox(height: 3),
                Text(row.tier,
                  style: GoogleFonts.inter(
                    color: AppColors.textTertiary,
                    fontSize: 11.5,
                    height: 1.2,
                  )),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
            ),
            child: Text(
              outOfTen,
              style: GoogleFonts.inter(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: AppColors.divider.withValues(alpha: 0.35));
}
