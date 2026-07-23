import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../services/local_store_service.dart';
import '../../../services/onboarding_store.dart';
import 'onboarding_kit.dart';

/// THE DEPUFF FUNNEL — the masterful emotional onboarding.
///
/// A single PageView drives every step so the progress bar, back arrow, and
/// shared answers all live in one place. This file is Part 1 (hook &
/// qualify); it ends by routing into the AI-consent → scan flow. Parts 2–4
/// (lifestyle inputs, belief-building, plan-ready) extend the [_steps]
/// list.
///
/// Total planned funnel length is [_kPlannedSteps] so the progress bar
/// grows realistically even while later parts are still being built.
class OnboardingFunnelScreen extends StatefulWidget {
  const OnboardingFunnelScreen({super.key});

  @override
  State<OnboardingFunnelScreen> createState() => _OnboardingFunnelScreenState();
}

class _OnboardingFunnelScreenState extends State<OnboardingFunnelScreen> {
  final _pc = PageController();
  int _i = 0;

  // The full designed funnel length (used only to scale the progress bar).
  static const int _kPlannedSteps = 18;

  // Answers held in memory during the funnel; persisted on each change so a
  // mid-funnel kill doesn't lose them.
  String? _gender;              // 'm' | 'f'
  String _name = '';
  final Set<String> _goals = {};

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.lightImpact();
    final steps = _buildSteps();
    if (_i < steps.length - 1) {
      _pc.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic);
    } else {
      _finishPartOne();
    }
  }

  void _back() {
    if (_i > 0) {
      _pc.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic);
    } else {
      context.go('/intro');
    }
  }

  Future<void> _finishPartOne() async {
    // Hand off into the existing AI-consent → scan flow. (Parts 2–4 will
    // slot in ahead of this hand-off as they're built.)
    await LocalStoreService.setOnboarded(true);
    if (!mounted) return;
    context.go('/onboarding/consent');
  }

  Future<void> _pickGender(String code) async {
    setState(() => _gender = code);
    await LocalStoreService.setUserGender(code);
    _next();
  }

  @override
  Widget build(BuildContext context) {
    final steps = _buildSteps();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _back(); },
      child: PageView(
        controller: _pc,
        physics: const NeverScrollableScrollPhysics(), // advance via CTAs only
        onPageChanged: (i) => setState(() => _i = i),
        children: steps,
      ),
    );
  }

  double _progressFor(int index) => (index + 1) / _kPlannedSteps;

  List<Widget> _buildSteps() {
    // NOTE: index positions matter — _progressFor keys off them. Welcome
    // slides (0–2) intentionally hide the progress bar.
    var idx = 0;
    int here() => idx++;

    return [
      // 0–2 · WELCOME CAROUSEL
      _WelcomeSlide(
        index: here(),
        showProgress: false,
        emoji: '⛶',
        label: 'Face Scan',
        image: 'assets/onboarding/welcome_scan.jpg',
        headTop: 'Wake Up',
        headBottom: 'Less Puffy',
        sub: 'Track puffiness. See real progress.',
        cta: 'Continue',
        onBack: _back,
        onNext: _next,
      ),
      _WelcomeSlide(
        index: here(),
        showProgress: false,
        emoji: '🥗',
        label: 'Food Analysis',
        image: 'assets/onboarding/welcome_food.jpg',
        headTop: 'Scan Meals.',
        headBottom: 'Eat Smarter.',
        sub: 'Spot the foods that puff your face up.',
        cta: 'Continue',
        onBack: _back,
        onNext: _next,
      ),
      _WelcomeSlide(
        index: here(),
        showProgress: false,
        emoji: '📅',
        label: 'Daily Routines',
        image: 'assets/onboarding/welcome_routine.jpg',
        headTop: 'Personalized',
        headBottom: 'Debloat Plan.',
        sub: 'A daily routine built for your face.',
        cta: 'Get Started',
        onBack: _back,
        onNext: _next,
      ),

      // 3 · GENDER
      _GenderStep(
        progress: _progressFor(here()),
        selected: _gender,
        onPick: _pickGender,
        onBack: _back,
      ),

      // 4 · NAME
      _NameStep(
        progress: _progressFor(here()),
        initial: _name,
        onBack: _back,
        onNext: (name) async {
          _name = name;
          await OnboardingStore.setName(name);
          _next();
        },
      ),

      // 5 · SHOCK STAT + BEFORE/AFTER
      _ShockStatStep(
        progress: _progressFor(here()),
        gender: _gender,
        onBack: _back,
        onNext: _next,
      ),

      // 6 · SOCIAL PROOF
      _SocialProofStep(
        progress: _progressFor(here()),
        onBack: _back,
        onNext: _next,
      ),

      // 7 · GOALS (multi-select)
      _GoalsStep(
        progress: _progressFor(here()),
        selected: _goals,
        onBack: _back,
        onToggle: (g) => setState(() {
          _goals.contains(g) ? _goals.remove(g) : _goals.add(g);
        }),
        onNext: () async {
          await OnboardingStore.setGoals(_goals.toList());
          _next();
        },
      ),
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  0–2 · WELCOME CAROUSEL SLIDE
// ═══════════════════════════════════════════════════════════════════════════
class _WelcomeSlide extends StatelessWidget {
  final int index;
  final bool showProgress;
  final String emoji, label, image, headTop, headBottom, sub, cta;
  final VoidCallback onBack, onNext;
  const _WelcomeSlide({
    required this.index,
    required this.showProgress,
    required this.emoji,
    required this.label,
    required this.image,
    required this.headTop,
    required this.headBottom,
    required this.sub,
    required this.cta,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return OnbScaffold(
      showBack: index != 0,
      onBack: onBack,
      progress: null,
      footer: OnbCta(label: cta, onTap: onNext),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: GoogleFonts.poppins(
                fontSize: 40, height: 1.05,
                fontWeight: FontWeight.w800, letterSpacing: -1),
              children: [
                TextSpan(text: '$headTop\n',
                  style: const TextStyle(color: Colors.white)),
                TextSpan(text: headBottom,
                  style: const TextStyle(color: Onb.primaryLite)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Hero image card
          ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: AspectRatio(
              aspectRatio: 4 / 5,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Onb.cardSel, Onb.bg]),
                  border: Border.all(
                    color: Onb.primary.withValues(alpha: 0.4), width: 1),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(image, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(emoji,
                          style: const TextStyle(fontSize: 84)))),
                    Positioned(
                      left: 14, bottom: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(emoji, style: const TextStyle(fontSize: 15)),
                            const SizedBox(width: 7),
                            Text(label,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 13.5, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ).animate().fadeIn(duration: 400.ms).scale(
            begin: const Offset(0.97, 0.97), end: const Offset(1, 1),
            duration: 400.ms, curve: Curves.easeOut),
          const SizedBox(height: 20),
          Text(sub,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Onb.grey, fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          _Dots(count: 3, active: index),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count, active;
  const _Dots({required this.count, required this.active});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 22 : 7, height: 7,
            decoration: BoxDecoration(
              color: i == active ? Onb.primary : Onb.cardBorder,
              borderRadius: BorderRadius.circular(100)),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  3 · GENDER
// ═══════════════════════════════════════════════════════════════════════════
class _GenderStep extends StatelessWidget {
  final double progress;
  final String? selected;
  final ValueChanged<String> onPick;
  final VoidCallback onBack;
  const _GenderStep({
    required this.progress,
    required this.selected,
    required this.onPick,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return OnbScaffold(
      progress: progress,
      onBack: onBack,
      child: Column(
        children: [
          const SizedBox(height: 8),
          const OnbHeadline(
            text: 'First, tell us ',
            emphasis: 'who you are',
            sub: 'This personalizes your face analysis.'),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(child: _GenderCard(
                emoji: '🧔', label: 'Male',
                image: 'assets/onboarding/gender_male.png',
                selected: selected == 'm',
                onTap: () => onPick('m'))),
              const SizedBox(width: 14),
              Expanded(child: _GenderCard(
                emoji: '👩', label: 'Female',
                image: 'assets/onboarding/gender_female.png',
                selected: selected == 'f',
                onTap: () => onPick('f'))),
            ],
          ),
        ],
      ),
    );
  }
}

class _GenderCard extends StatelessWidget {
  final String emoji, label, image;
  final bool selected;
  final VoidCallback onTap;
  const _GenderCard({
    required this.emoji,
    required this.label,
    required this.image,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Onb.cardSel : Onb.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? Onb.primary : Onb.cardBorder,
              width: selected ? 1.5 : 1),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22)),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Image.asset(image, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Onb.bg,
                      alignment: Alignment.center,
                      child: Text(emoji,
                        style: const TextStyle(fontSize: 64)))),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(label,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  4 · NAME
// ═══════════════════════════════════════════════════════════════════════════
class _NameStep extends StatefulWidget {
  final double progress;
  final String initial;
  final VoidCallback onBack;
  final ValueChanged<String> onNext;
  const _NameStep({
    required this.progress,
    required this.initial,
    required this.onBack,
    required this.onNext,
  });

  @override
  State<_NameStep> createState() => _NameStepState();
}

class _NameStepState extends State<_NameStep> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _c.text.trim();
    return OnbScaffold(
      progress: widget.progress,
      onBack: widget.onBack,
      footer: OnbCta(
        label: 'Continue',
        enabled: name.isNotEmpty,
        onTap: name.isEmpty ? null : () => widget.onNext(name)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const OnbHeadline(
            text: "What should we ",
            emphasis: 'call you?',
            align: TextAlign.start,
            sub: "We'll use it to personalize your plan."),
          const SizedBox(height: 28),
          TextField(
            controller: _c,
            onChanged: (_) => setState(() {}),
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.poppins(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
            cursorColor: Onb.primary,
            decoration: InputDecoration(
              hintText: 'Your first name',
              hintStyle: GoogleFonts.poppins(
                color: Onb.grey, fontSize: 22, fontWeight: FontWeight.w600),
              filled: true,
              fillColor: Onb.card,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18, vertical: 18),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Onb.cardBorder)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Onb.primary, width: 1.5)),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  5 · SHOCK STAT + BEFORE/AFTER
// ═══════════════════════════════════════════════════════════════════════════
class _ShockStatStep extends StatelessWidget {
  final double progress;
  final String? gender;
  final VoidCallback onBack, onNext;
  const _ShockStatStep({
    required this.progress,
    required this.gender,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final who = gender == 'f' ? 'Women' : 'Men';
    return OnbScaffold(
      progress: progress,
      onBack: onBack,
      footer: OnbCta(label: 'Continue', onTap: onNext),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: GoogleFonts.poppins(
                color: Colors.white, fontSize: 27, height: 1.15,
                fontWeight: FontWeight.w800, letterSpacing: -0.5),
              children: [
                TextSpan(text: '$who are '),
                const TextSpan(text: '67% more bloated',
                  style: TextStyle(color: Onb.danger)),
                const TextSpan(text: ' than they realise.'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const BeforeAfterSlider(),
          const SizedBox(height: 20),
          RichText(
            text: TextSpan(
              style: GoogleFonts.inter(
                color: Onb.grey, fontSize: 15.5, height: 1.5,
                fontWeight: FontWeight.w500),
              children: [
                const TextSpan(text: 'Facial bloating quietly '),
                TextSpan(text: 'steals your definition',
                  style: GoogleFonts.inter(
                    color: Colors.white, fontWeight: FontWeight.w700)),
                const TextSpan(text: ' — and can make you look up to '),
                TextSpan(text: '46% less attractive',
                  style: GoogleFonts.inter(
                    color: Onb.danger, fontWeight: FontWeight.w700)),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  6 · SOCIAL PROOF
// ═══════════════════════════════════════════════════════════════════════════
class _SocialProofStep extends StatelessWidget {
  final double progress;
  final VoidCallback onBack, onNext;
  const _SocialProofStep({
    required this.progress,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return OnbScaffold(
      progress: progress,
      onBack: onBack,
      footer: OnbCta(label: 'Continue', onTap: onNext),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Text('100,000+',
            style: GoogleFonts.poppins(
              color: Onb.primaryLite,
              fontSize: 52, height: 1, fontWeight: FontWeight.w800,
              letterSpacing: -2)),
          const SizedBox(height: 12),
          const OnbHeadline(
            text: 'people are already draining the bloat.\n',
            emphasis: 'Are you?',
            size: 24),
          const SizedBox(height: 20),
          Text('Most users see visible change in 28 days.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Onb.grey, fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AvatarStack(),
              const SizedBox(width: 12),
              const Icon(Icons.star_rounded, color: Onb.primaryLite, size: 22),
              const SizedBox(width: 4),
              Text('4.9',
                style: GoogleFonts.poppins(
                  color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const colors = [Onb.primary, Onb.primaryLite, Onb.success, Onb.danger, Color(0xFF38BDF8)];
    return SizedBox(
      width: 5 * 22.0 + 12,
      height: 36,
      child: Stack(
        children: [
          for (var i = 0; i < 5; i++)
            Positioned(
              left: i * 22.0,
              child: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: colors[i],
                  shape: BoxShape.circle,
                  border: Border.all(color: Onb.bg, width: 2)),
                child: const Icon(Icons.person_rounded,
                  color: Colors.white70, size: 18),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  7 · GOALS (multi-select)
// ═══════════════════════════════════════════════════════════════════════════
class _GoalsStep extends StatelessWidget {
  final double progress;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onBack;
  final VoidCallback onNext;
  const _GoalsStep({
    required this.progress,
    required this.selected,
    required this.onToggle,
    required this.onBack,
    required this.onNext,
  });

  static const _opts = <({String emoji, String label})>[
    (emoji: '🙂', label: 'Boost confidence & self-esteem'),
    (emoji: '❤️', label: 'Get more dates / a relationship'),
    (emoji: '⛶', label: 'Wake up with a less puffy face'),
    (emoji: '💎', label: 'A sharper, more defined jawline'),
  ];

  @override
  Widget build(BuildContext context) {
    final n = selected.length;
    return OnbScaffold(
      progress: progress,
      onBack: onBack,
      footer: OnbCta(
        label: 'Continue',
        enabled: n > 0,
        onTap: n > 0 ? onNext : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const OnbHeadline(
            text: "What's your ",
            emphasis: 'goal?',
            align: TextAlign.start,
            sub: 'Choose all that apply — we prioritise these.'),
          const SizedBox(height: 22),
          for (final o in _opts) ...[
            OnbMultiRow(
              emoji: o.emoji,
              label: o.label,
              selected: selected.contains(o.label),
              onTap: () => onToggle(o.label)),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 6),
          if (n > 0)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Onb.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Onb.cardBorder)),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                    color: Onb.primaryLite, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You selected $n ${n == 1 ? 'goal' : 'goals'}. '
                      'Our AI will prioritise these areas.',
                      style: GoogleFonts.inter(
                        color: Onb.grey, fontSize: 13,
                        fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
