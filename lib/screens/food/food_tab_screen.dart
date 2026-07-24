import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/food_analysis.dart';
import '../../services/analytics_service.dart';
import '../../services/mirror_api_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../widgets/common/mirrorly_wordmark.dart';

/// FOOD tab — "Scan meals that cause puffiness."
///
/// Replaces the old Mirror tab. The user photographs a meal or drink,
/// GPT-4o Vision grades it for FACIAL BLOAT (sodium load + a graded
/// metric grid), and the result renders as a clean diagnostic card with
/// ring gauges — the debloat answer to a food scanner.
class FoodTabScreen extends StatefulWidget {
  const FoodTabScreen({super.key});

  @override
  State<FoodTabScreen> createState() => _FoodTabScreenState();
}

class _FoodTabScreenState extends State<FoodTabScreen> {
  static const _kLastResult = 'food_last_result';
  static const _kLastPhoto  = 'food_last_photo';

  final _picker = ImagePicker();

  FoodAnalysis? _result;
  Uint8List?    _photo;
  bool          _loading = false;
  String?       _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final rawResult = prefs.getString(_kLastResult);
    final rawPhoto  = prefs.getString(_kLastPhoto);
    if (rawResult == null) return;
    try {
      final result = FoodAnalysis.fromJson(
          jsonDecode(rawResult) as Map<String, dynamic>);
      final photo = rawPhoto != null ? base64Decode(rawPhoto) : null;
      if (!mounted) return;
      setState(() {
        _result = result;
        _photo  = photo;
      });
    } catch (_) {/* stale cache — ignore */}
  }

  Future<void> _persist(FoodAnalysis result, Uint8List photo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastResult, jsonEncode(result.toJson()));
    // Cap the stored photo so prefs stays lean — it's only a thumbnail
    // for re-entry, the fresh scan always uses the in-memory bytes.
    if (photo.lengthInBytes < 900 * 1024) {
      await prefs.setString(_kLastPhoto, base64Encode(photo));
    } else {
      await prefs.remove(_kLastPhoto);
    }
  }

  Future<void> _scan(ImageSource source) async {
    HapticFeedback.selectionClick();
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1400,
        imageQuality: 85,
      );
      if (file == null) return; // user cancelled
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo   = bytes;
        _loading = true;
        _error   = null;
        _result  = null;
      });
      // ignore: discarded_futures
      AnalyticsService.foodScanStarted(
          source == ImageSource.camera ? 'camera' : 'library');
      final result = await MirrorApiService.analyseFood(imageBytes: bytes);
      if (!mounted) return;
      setState(() {
        _result  = result;
        _loading = false;
      });
      // ignore: discarded_futures
      AnalyticsService.foodScanCompleted(
        name: result.name,
        score: result.overallScore,
        sodiumMg: result.sodiumMg,
        risk: result.puffinessRisk,
      );
      await _persist(result, bytes);
    } catch (err) {
      // ignore: discarded_futures
      AnalyticsService.foodScanFailed();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not read that one. Try another photo.';
      });
    }
  }

  void _reset() {
    HapticFeedback.selectionClick();
    setState(() {
      _result = null;
      _error  = null;
      _photo  = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: Sp.xxl),
          children: [
            // ── Masthead ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
              child: Row(
                children: [
                  const MirrorlyWordmark(fontSize: 34),
                  const Spacer(),
                  if (_result != null && !_loading)
                    _PillButton(
                      icon: Icons.add_a_photo_rounded,
                      label: 'Scan',
                      onTap: () => _scan(ImageSource.camera),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                'Scan meals that cause puffiness.',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 15, height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: Sp.lg),

            if (_loading)
              _LoadingCard(photo: _photo)
            else if (_result != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                child: _FoodResultCard(
                  result: _result!,
                  photo: _photo,
                  onScanAnother: _reset,
                ).animate().fadeIn(duration: 400.ms)
                  .slideY(begin: 0.03, end: 0, curve: Curves.easeOut),
              )
            else
              _Landing(
                error: _error,
                onCamera: () => _scan(ImageSource.camera),
                onLibrary: () => _scan(ImageSource.gallery),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  LANDING — pre-scan sell + CTA
// ═══════════════════════════════════════════════════════════════════════════
class _Landing extends StatelessWidget {
  final String? error;
  final VoidCallback onCamera;
  final VoidCallback onLibrary;
  const _Landing({
    required this.error,
    required this.onCamera,
    required this.onLibrary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Spot bloating triggers, sodium load,\nand smarter food choices in seconds.',
            style: GoogleFonts.spaceGrotesk(
              color: AppColors.textPrimary,
              fontSize: 22, height: 1.25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            )),
          const SizedBox(height: Sp.lg),

          // How it reads — three quick value rows.
          _ValueRow(
            icon: Icons.opacity_rounded,
            title: 'Sodium load',
            body: 'The #1 driver of next-morning face bloat, estimated per portion.'),
          const SizedBox(height: 14),
          _ValueRow(
            icon: Icons.blur_on_rounded,
            title: 'Bloat grade',
            body: 'Bloating, inflammation, digestion, skin, fluid balance — scored.'),
          const SizedBox(height: 14),
          _ValueRow(
            icon: Icons.swap_horiz_rounded,
            title: 'Better swaps',
            body: 'A lower-bloat substitution when there\'s an easy win.'),

          const SizedBox(height: Sp.xl),

          if (error != null) ...[
            _ErrorStrip(error!),
            const SizedBox(height: Sp.md),
          ],

          _PrimaryButton(
            icon: Icons.photo_camera_rounded,
            label: 'Scan a meal',
            onTap: onCamera,
          ),
          const SizedBox(height: 12),
          _SecondaryButton(
            icon: Icons.photo_library_outlined,
            label: 'Choose from library',
            onTap: onLibrary,
          ),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _ValueRow({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.brandGlow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.brand.withValues(alpha: 0.35), width: 0.8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: AppColors.brand),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                style: GoogleFonts.inter(
                  color: AppColors.textPrimary,
                  fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(body,
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 13, height: 1.35,
                  fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  LOADING
// ═══════════════════════════════════════════════════════════════════════════
class _LoadingCard extends StatelessWidget {
  final Uint8List? photo;
  const _LoadingCard({required this.photo});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Rd.xl),
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (photo != null)
                    Image.memory(photo!, fit: BoxFit.cover)
                  else
                    Container(color: AppColors.surface2),
                  Container(color: Colors.black.withValues(alpha: 0.45)),
                  const Center(
                    child: SizedBox(
                      width: 30, height: 30,
                      child: CircularProgressIndicator(
                        color: AppColors.brand, strokeWidth: 2.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Sp.md),
          Text('Reading the bloat load…',
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  RESULT CARD
// ═══════════════════════════════════════════════════════════════════════════
class _FoodResultCard extends StatelessWidget {
  final FoodAnalysis result;
  final Uint8List? photo;
  final VoidCallback onScanAnother;
  const _FoodResultCard({
    required this.result,
    required this.photo,
    required this.onScanAnother,
  });

  @override
  Widget build(BuildContext context) {
    if (result.isEmpty) {
      return Column(
        children: [
          _ErrorStrip('No food detected — point the camera at a meal or drink.'),
          const SizedBox(height: Sp.md),
          _PrimaryButton(
            icon: Icons.photo_camera_rounded,
            label: 'Try again',
            onTap: onScanAnother),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Photo with sodium chip + score ring overlay ────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(Rd.xl),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (photo != null)
                  Image.memory(photo!, fit: BoxFit.cover)
                else
                  Container(color: AppColors.surface2,
                    child: const Icon(Icons.restaurant_rounded,
                      color: AppColors.surface3, size: 48)),
                // bottom shade for legibility
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.75),
                        ],
                        stops: const [0.45, 1.0],
                      ),
                    ),
                  ),
                ),
                // Sodium load chip — top left
                Positioned(
                  left: 12, top: 12,
                  child: _SodiumChip(
                    mg: result.sodiumMg,
                    pct: result.sodiumPctDaily,
                    risk: result.puffinessRisk),
                ),
                // Overall score ring — top right
                Positioned(
                  right: 12, top: 12,
                  child: _ScoreRing(
                    score: result.overallScore,
                    verdict: result.verdict),
                ),
                // Food name — bottom left
                Positioned(
                  left: 14, right: 14, bottom: 12,
                  child: Text(result.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 24, height: 1.05,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    )),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: Sp.md),

        // ── Metric grid ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(Rd.xl),
            border: Border.all(color: AppColors.surface3, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 5, height: 5,
                    decoration: const BoxDecoration(
                      color: AppColors.brand, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Text('BLOAT BREAKDOWN',
                    style: AppTypography.label.copyWith(
                      color: AppColors.brand,
                      fontSize: 10.5, letterSpacing: 3.0,
                      fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, c) {
                  const gap = 10.0;
                  final tileW = (c.maxWidth - gap) / 2;
                  return Wrap(
                    spacing: gap,
                    runSpacing: 12,
                    children: [
                      for (final s in result.stats)
                        SizedBox(width: tileW, child: _StatTile(stat: s)),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),

        // ── Better swap ────────────────────────────────────────────────
        if (result.betterSwap != null) ...[
          const SizedBox(height: Sp.md),
          _SwapCard(swap: result.betterSwap!),
        ],

        // ── Tip ────────────────────────────────────────────────────────
        if (result.tip.isNotEmpty) ...[
          const SizedBox(height: Sp.md),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.brandGlow,
              borderRadius: BorderRadius.circular(Rd.lg),
              border: Border.all(
                color: AppColors.brand.withValues(alpha: 0.3), width: 0.8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.tips_and_updates_rounded,
                  color: AppColors.brand, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(result.tip,
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontSize: 13.5, height: 1.4,
                      fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: Sp.lg),
        _PrimaryButton(
          icon: Icons.add_a_photo_rounded,
          label: 'Scan another meal',
          onTap: onScanAnother),
      ],
    );
  }
}

// ── Sodium chip ─────────────────────────────────────────────────────────────
class _SodiumChip extends StatelessWidget {
  final int mg;
  final int pct;
  final String risk;
  const _SodiumChip({required this.mg, required this.pct, required this.risk});

  @override
  Widget build(BuildContext context) {
    final color = _riskColor(risk);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SODIUM LOAD',
            style: AppTypography.label.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 8.5, letterSpacing: 1.6, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$mg',
                style: GoogleFonts.spaceGrotesk(
                  color: Colors.white,
                  fontSize: 22, height: 1,
                  fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(width: 2),
              Text('mg',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text('$risk risk · $pct% daily',
              style: GoogleFonts.inter(
                color: color,
                fontSize: 9.5, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

// ── Overall score ring ──────────────────────────────────────────────────────
class _ScoreRing extends StatelessWidget {
  final int score;
  final String verdict;
  const _ScoreRing({required this.score, required this.verdict});

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(score);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 64, height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(64, 64),
                  painter: _RingPainter(
                    progress: score / 100, color: color, stroke: 6,
                    trackColor: Colors.white.withValues(alpha: 0.18)),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$score',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 22, height: 1,
                        fontWeight: FontWeight.w800, letterSpacing: -1)),
                    Text('/100',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 8, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(verdict.toUpperCase(),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: AppTypography.label.copyWith(
              color: color, fontSize: 8, letterSpacing: 1.0,
              fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

// ── Stat tile (label + score + rating pill + bar) ───────────────────────────
class _StatTile extends StatelessWidget {
  final FoodStat stat;
  const _StatTile({required this.stat});

  @override
  Widget build(BuildContext context) {
    final color = _ratingColor(stat.rating);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(color: AppColors.surface3, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(stat.label,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 11.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('${stat.score}',
                style: GoogleFonts.spaceGrotesk(
                  color: AppColors.textPrimary,
                  fontSize: 22, height: 1,
                  fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(_ratingLabel(stat.rating),
                  style: GoogleFonts.inter(
                    color: color, fontSize: 9.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: (stat.score / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.surface3,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Better-swap card ────────────────────────────────────────────────────────
class _SwapCard extends StatelessWidget {
  final BetterSwap swap;
  const _SwapCard({required this.swap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(
          color: AppColors.signalGreen.withValues(alpha: 0.4), width: 0.9),
      ),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz_rounded,
            color: AppColors.signalGreen, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BETTER SWAP',
                  style: AppTypography.label.copyWith(
                    color: AppColors.signalGreen,
                    fontSize: 9.5, letterSpacing: 2.0,
                    fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(swap.from,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: AppColors.textTertiary,
                          fontSize: 14, fontWeight: FontWeight.w600,
                          decoration: TextDecoration.lineThrough))),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward_rounded,
                        color: AppColors.textTertiary, size: 15)),
                    Flexible(
                      child: Text(swap.to,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 14, fontWeight: FontWeight.w800))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Shared bits
// ═══════════════════════════════════════════════════════════════════════════
class _ErrorStrip extends StatelessWidget {
  final String message;
  const _ErrorStrip(this.message);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.signalRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Rd.lg),
        border: Border.all(
          color: AppColors.signalRed.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
            color: AppColors.signalRed, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PrimaryButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brand,
      borderRadius: BorderRadius.circular(Rd.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.lg),
        child: Container(
          height: 54,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.base, size: 20),
              const SizedBox(width: 10),
              Text(label,
                style: GoogleFonts.inter(
                  color: AppColors.base,
                  fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SecondaryButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(Rd.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.lg),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rd.lg),
            border: Border.all(color: AppColors.surface3, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.textSecondary, size: 19),
              const SizedBox(width: 10),
              Text(label,
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PillButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brand,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.base, size: 16),
              const SizedBox(width: 6),
              Text(label,
                style: GoogleFonts.inter(
                  color: AppColors.base,
                  fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Colour helpers ──────────────────────────────────────────────────────────
Color _ratingColor(String rating) {
  switch (rating) {
    case 'great': return AppColors.signalGreen;
    case 'good':  return AppColors.signalGreen;
    case 'bad':   return AppColors.signalRed;
    default:      return AppColors.signalAmber; // moderate
  }
}

String _ratingLabel(String rating) {
  switch (rating) {
    case 'great': return 'Great';
    case 'good':  return 'Good';
    case 'bad':   return 'High';
    default:      return 'Moderate';
  }
}

Color _scoreColor(int score) {
  if (score >= 74) return AppColors.signalGreen;
  if (score >= 50) return AppColors.signalAmber;
  return AppColors.signalRed;
}

Color _riskColor(String risk) {
  switch (risk.toLowerCase()) {
    case 'low':  return AppColors.signalGreen;
    case 'high': return AppColors.signalRed;
    default:     return AppColors.signalAmber;
  }
}

// ── Ring painter ────────────────────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double stroke;
  final Color trackColor;
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.stroke,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = (Offset.zero & size).center;
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, math.pi * 2, false, track);
    final p = progress.clamp(0.0, 1.0);
    if (p > 0) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, math.pi * 2 * p, false, arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
