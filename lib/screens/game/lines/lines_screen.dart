import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../data/rizz_lines.dart';
import '../../../services/paywall_gate.dart';
import '../../../theme/app_colors.dart';

/// LINES — the arsenal. Five categories of curated 2026 rizz, tap-to-copy.
/// Editorial card composition: small-caps red eyebrow, italic Playfair
/// headline, italic body subtitle, tab strip, cards. No bullshit.
class LinesScreen extends StatefulWidget {
  const LinesScreen({super.key});

  @override
  State<LinesScreen> createState() => _LinesScreenState();
}

class _LinesScreenState extends State<LinesScreen>
    with TickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: RizzArsenal.categories.length, vsync: this);
    _tab.addListener(() {
      if (_tab.indexIsChanging) HapticFeedback.selectionClick();
    });
    // Pro-only route — bounce non-pro deep links to paywall on mount.
    WidgetsBinding.instance.addPostFrameCallback((_) => _gate());
  }

  Future<void> _gate() async {
    final pro = await PaywallGate.isPro();
    if (!mounted || pro) return;
    context.pushReplacement('/paywall',
        extra: {'source': 'rizz_lines_locked'});
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _copy(RizzLine line) async {
    HapticFeedback.mediumImpact();
    await Clipboard.setData(ClipboardData(text: line.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied. Paste it tonight.',
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 14, fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            )),
        backgroundColor: AppColors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCat = RizzArsenal.categories[_tab.index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28, minHeight: 28),
                      ),
                      const SizedBox(width: 6),
                      Text('LINES',
                        style: GoogleFonts.inter(
                          color: AppColors.red,
                          fontSize: 12, letterSpacing: 3.6,
                          fontWeight: FontWeight.w800,
                        )),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    child: Text(activeCat.headline,
                      key: ValueKey(activeCat.slug),
                      style: GoogleFonts.playfairDisplay(
                        color: Colors.white,
                        fontSize: 42, height: 1.05,
                        letterSpacing: -0.8,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w800,
                      )),
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    child: Text(activeCat.hint,
                      key: ValueKey('${activeCat.slug}-hint'),
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 14, height: 1.45,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                      )),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // Tab strip
            TabBar(
              controller: _tab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 18),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              indicator: const UnderlineTabIndicator(
                borderSide: BorderSide(color: AppColors.red, width: 2.4),
                insets: EdgeInsets.symmetric(horizontal: 4),
              ),
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              labelColor: AppColors.red,
              unselectedLabelColor: AppColors.textTertiary,
              labelStyle: GoogleFonts.inter(
                fontSize: 13, letterSpacing: 2.4,
                fontWeight: FontWeight.w900,
              ),
              unselectedLabelStyle: GoogleFonts.inter(
                fontSize: 13, letterSpacing: 2.4,
                fontWeight: FontWeight.w700,
              ),
              onTap: (_) => setState(() {}),
              tabs: RizzArsenal.categories
                  .map((c) => Tab(text: c.label))
                  .toList(),
            ),

            const SizedBox(height: 4),

            // Lines list
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: RizzArsenal.categories.map((cat) {
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                    itemCount: cat.lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _LineCard(
                      line: cat.lines[i],
                      onTap: () => _copy(cat.lines[i]),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  final RizzLine line;
  final VoidCallback onTap;
  const _LineCard({required this.line, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: AppColors.red.withValues(alpha: 0.06),
        highlightColor: AppColors.red.withValues(alpha: 0.04),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.surface3, width: 0.6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (line.isSequence)
                      // Multi-line sequence — each part renders as its
                      // own paragraph with a small left-rule, so the
                      // setup → payoff reads as separate beats.
                      ..._buildSequenceParts(line.parts!)
                    else
                      Text('"${line.text}"',
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 16, height: 1.32,
                          fontWeight: FontWeight.w600,
                          fontStyle: FontStyle.italic,
                        )),
                    const SizedBox(height: 10),
                    Text(line.tag,
                      style: GoogleFonts.inter(
                        color: AppColors.red,
                        fontSize: 10.5, letterSpacing: 2.0,
                        fontWeight: FontWeight.w800,
                      )),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.copy_rounded,
                    size: 16,
                    color: AppColors.textTertiary.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Render multi-part sequences. Each beat sits in its own italic
  /// quoted line with a tiny red dash gutter on the left so the
  /// setup → payoff structure is visually unambiguous.
  List<Widget> _buildSequenceParts(List<String> parts) {
    final widgets = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) widgets.add(const SizedBox(height: 8));
      widgets.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 7, right: 8),
            width: 8, height: 2,
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: i == 0 ? 0.55 : 0.85),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Expanded(
            child: Text('"${parts[i]}"',
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 15.5, height: 1.32,
                fontWeight: FontWeight.w600,
                fontStyle: FontStyle.italic,
              )),
          ),
        ],
      ));
    }
    return widgets;
  }
}
