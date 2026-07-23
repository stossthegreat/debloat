import 'dart:math' as math;

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
/// A single PageView drives all 15 steps so the progress bar, back arrow,
/// and shared answers all live in one place:
///
///   0–2  Welcome carousel (Face Scan / Food / Routines)
///   3    Gender      4  Name       5  Shock stat + before/after
///   6    Social proof 7 Goals      8  Water intake (glass fill)
///   9    Sleep       10 Pain points 11 Struggles
///   12   Empathy 89% 13 Identity fork 14 Routine value graph
///
/// The last step hands off to AI-consent → scan → report (the results /
/// plan-ready payoff) → paywall.
class OnboardingFunnelScreen extends StatefulWidget {
  const OnboardingFunnelScreen({super.key});

  @override
  State<OnboardingFunnelScreen> createState() => _OnboardingFunnelScreenState();
}

class _OnboardingFunnelScreenState extends State<OnboardingFunnelScreen> {
  final _pc = PageController();
  int _i = 0;

  // The full designed funnel length (used only to scale the progress bar).
  static const int _kPlannedSteps = 15;

  // Answers held in memory during the funnel; persisted on each change so a
  // mid-funnel kill doesn't lose them.
  String? _gender;              // 'm' | 'f'
  String _name = '';
  final Set<String> _goals = {};
  double _water = 2.5;          // litres/day
  double _sleep = 6.5;          // hours/night
  final Set<String> _struggles = {};

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
      _finishFunnel();
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

  Future<void> _finishFunnel() async {
    // Hand off into the AI-consent → scan → report flow. The scan is the
    // payoff the whole funnel builds toward; the report IS the results /
    // plan-ready screen, and it routes on to the paywall.
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

      // 8 · WATER INTAKE (glass fill)
      _WaterStep(
        progress: _progressFor(here()),
        initial: _water,
        onBack: _back,
        onNext: (v) async {
          _water = v;
          await OnboardingStore.setWaterLitres(v);
          _next();
        },
      ),

      // 9 · SLEEP HOURS
      _SleepStep(
        progress: _progressFor(here()),
        initial: _sleep,
        onBack: _back,
        onNext: (v) async {
          _sleep = v;
          await OnboardingStore.setSleepHours(v);
          _next();
        },
      ),

      // 10 · PAIN-POINT REPORT
      _PainPointsStep(
        progress: _progressFor(here()),
        onBack: _back,
        onNext: _next,
      ),

      // 11 · STRUGGLES (multi-select)
      _StrugglesStep(
        progress: _progressFor(here()),
        selected: _struggles,
        onBack: _back,
        onToggle: (g) => setState(() {
          _struggles.contains(g) ? _struggles.remove(g) : _struggles.add(g);
        }),
        onNext: () async {
          await OnboardingStore.setStruggles(_struggles.toList());
          _next();
        },
      ),

      // 12 · EMPATHY / 89% PROOF
      _EmpathyStep(
        progress: _progressFor(here()),
        onBack: _back,
        onNext: _next,
      ),

      // 13 · IDENTITY FORK
      _IdentityForkStep(
        progress: _progressFor(here()),
        onBack: _back,
        onNext: _next,
      ),

      // 14 · ROUTINE VALUE GRAPH → hands off to the scan
      _RoutineGraphStep(
        progress: _progressFor(here()),
        onBack: _back,
        onNext: _next, // last step → _next() calls _finishFunnel()
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

// ═══════════════════════════════════════════════════════════════════════════
//  8 · WATER INTAKE (glass fill)
// ═══════════════════════════════════════════════════════════════════════════
class _WaterStep extends StatefulWidget {
  final double progress;
  final double initial;
  final VoidCallback onBack;
  final ValueChanged<double> onNext;
  const _WaterStep({
    required this.progress,
    required this.initial,
    required this.onBack,
    required this.onNext,
  });
  @override
  State<_WaterStep> createState() => _WaterStepState();
}

class _WaterStepState extends State<_WaterStep> {
  late double _v = widget.initial;

  @override
  Widget build(BuildContext context) {
    return OnbScaffold(
      progress: widget.progress,
      onBack: widget.onBack,
      footer: OnbCta(label: 'Continue', onTap: () => widget.onNext(_v)),
      child: Column(
        children: [
          const SizedBox(height: 8),
          const OnbHeadline(
            text: 'How much water do you ',
            emphasis: 'drink daily?',
            sub: 'Proper hydration is what tells the body to release '
                'retained fluid.'),
          const SizedBox(height: 28),
          Text('${_v.toStringAsFixed(1)}L',
            style: GoogleFonts.poppins(
              color: Onb.primaryLite, fontSize: 56, height: 1,
              fontWeight: FontWeight.w800, letterSpacing: -2)),
          const SizedBox(height: 20),
          // Glass fill
          SizedBox(
            width: 120, height: 170,
            child: CustomPaint(
              painter: _GlassPainter(fill: ((_v - 0.5) / 3.5).clamp(0.0, 1.0))),
          ),
          const SizedBox(height: 20),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Onb.primary,
              inactiveTrackColor: Onb.card,
              thumbColor: Colors.white,
              overlayColor: Onb.primary.withValues(alpha: 0.2),
              trackHeight: 6,
            ),
            child: Slider(
              value: _v, min: 0.5, max: 4.0, divisions: 35,
              onChanged: (x) => setState(() => _v = x)),
          ),
          Text('Drag to set your daily intake',
            style: GoogleFonts.inter(
              color: Onb.grey, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _GlassPainter extends CustomPainter {
  final double fill;
  const _GlassPainter({required this.fill});
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // trapezoid glass: wider at top
    final topInset = w * 0.06, botInset = w * 0.18;
    final path = Path()
      ..moveTo(topInset, 0)
      ..lineTo(w - topInset, 0)
      ..lineTo(w - botInset, h)
      ..lineTo(botInset, h)
      ..close();
    // liquid
    final liqTop = h * (1 - fill);
    canvas.save();
    canvas.clipPath(path);
    final liq = Paint()..color = const Color(0xFF6C4CF5).withValues(alpha: 0.85);
    canvas.drawRect(Rect.fromLTRB(0, liqTop, w, h), liq);
    final liqLite = Paint()..color = const Color(0xFFA78BFA).withValues(alpha: 0.5);
    canvas.drawRect(Rect.fromLTRB(0, liqTop, w, liqTop + 8), liqLite);
    canvas.restore();
    // outline
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = const Color(0xFF2A2444);
    canvas.drawPath(path, stroke);
  }
  @override
  bool shouldRepaint(_GlassPainter old) => old.fill != fill;
}

// ═══════════════════════════════════════════════════════════════════════════
//  9 · SLEEP HOURS
// ═══════════════════════════════════════════════════════════════════════════
class _SleepStep extends StatefulWidget {
  final double progress;
  final double initial;
  final VoidCallback onBack;
  final ValueChanged<double> onNext;
  const _SleepStep({
    required this.progress,
    required this.initial,
    required this.onBack,
    required this.onNext,
  });
  @override
  State<_SleepStep> createState() => _SleepStepState();
}

class _SleepStepState extends State<_SleepStep> {
  late double _v = widget.initial;

  @override
  Widget build(BuildContext context) {
    return OnbScaffold(
      progress: widget.progress,
      onBack: widget.onBack,
      footer: OnbCta(label: 'Continue', onTap: () => widget.onNext(_v)),
      child: Column(
        children: [
          const SizedBox(height: 8),
          const OnbHeadline(
            text: 'How many hours do you ',
            emphasis: 'sleep?',
            sub: 'Short sleep spikes cortisol — the hormone behind '
                '"cortisol face" puffiness.'),
          const SizedBox(height: 36),
          Container(
            width: 150, height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Onb.cardSel, Onb.card]),
              border: Border.all(color: Onb.primary.withValues(alpha: 0.4)),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.nightlight_round, color: Onb.primaryLite, size: 30),
                const SizedBox(height: 6),
                Text('${_v.toStringAsFixed(0)}h',
                  style: GoogleFonts.poppins(
                    color: Colors.white, fontSize: 40, height: 1,
                    fontWeight: FontWeight.w800, letterSpacing: -1)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Onb.primary,
              inactiveTrackColor: Onb.card,
              thumbColor: Colors.white,
              overlayColor: Onb.primary.withValues(alpha: 0.2),
              trackHeight: 6,
            ),
            child: Slider(
              value: _v, min: 3, max: 10, divisions: 7,
              onChanged: (x) => setState(() => _v = x)),
          ),
          Text('Drag to set your average night',
            style: GoogleFonts.inter(
              color: Onb.grey, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  10 · PAIN-POINT REPORT
// ═══════════════════════════════════════════════════════════════════════════
class _PainPointsStep extends StatelessWidget {
  final double progress;
  final VoidCallback onBack, onNext;
  const _PainPointsStep({
    required this.progress,
    required this.onBack,
    required this.onNext,
  });

  static const _cards = <({String title, String body, String sev, bool major, String emoji})>[
    (title: 'Morning puffiness ruins your look',
     body: 'You wake up looking tired and softer than you are.',
     sev: 'MAJOR IMPACT', major: true, emoji: '😪'),
    (title: 'Soft features read as less defined',
     body: 'Water weight hides the jaw and cheekbones you already have.',
     sev: 'SIGNIFICANT', major: false, emoji: '😕'),
    (title: 'A blurred jawline hurts first impressions',
     body: 'People read sharpness as discipline. Bloat blurs it.',
     sev: 'MAJOR IMPACT', major: true, emoji: '💼'),
  ];

  @override
  Widget build(BuildContext context) {
    return OnbScaffold(
      progress: progress,
      onBack: onBack,
      footer: OnbCta(label: 'Fix My Bloating', onTap: onNext),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 66, height: 66,
              decoration: BoxDecoration(
                color: Onb.danger.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: Onb.danger.withValues(alpha: 0.5))),
              child: const Icon(Icons.warning_amber_rounded,
                color: Onb.danger, size: 32),
            ),
          ),
          const SizedBox(height: 18),
          const OnbHeadline(
            text: 'Hidden bloating is\n',
            emphasis: 'sabotaging your looks',
            size: 25),
          const SizedBox(height: 8),
          Text('Your face reads less defined than it actually is.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Onb.grey, fontSize: 14.5, fontWeight: FontWeight.w500)),
          const SizedBox(height: 22),
          for (final c in _cards) ...[
            _PainCard(card: c),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _PainCard extends StatelessWidget {
  final ({String title, String body, String sev, bool major, String emoji}) card;
  const _PainCard({required this.card});
  @override
  Widget build(BuildContext context) {
    final accent = card.major ? Onb.danger : const Color(0xFFF9A825);
    return Container(
      decoration: BoxDecoration(
        color: Onb.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Onb.cardBorder),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)))),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.title,
                      style: GoogleFonts.inter(
                        color: Colors.white, fontSize: 15,
                        height: 1.25, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(card.body,
                      style: GoogleFonts.inter(
                        color: Onb.grey, fontSize: 13, height: 1.35,
                        fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(100)),
                      child: Text(card.sev,
                        style: GoogleFonts.inter(
                          color: accent, fontSize: 10, letterSpacing: 0.8,
                          fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(child: Text(card.emoji, style: const TextStyle(fontSize: 26))),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  11 · STRUGGLES (multi-select)
// ═══════════════════════════════════════════════════════════════════════════
class _StrugglesStep extends StatelessWidget {
  final double progress;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onBack, onNext;
  const _StrugglesStep({
    required this.progress,
    required this.selected,
    required this.onToggle,
    required this.onBack,
    required this.onNext,
  });

  static const _opts = <({String emoji, String label})>[
    (emoji: '☹️', label: 'Low confidence in how I look'),
    (emoji: '👥', label: 'I feel less confident in social situations'),
    (emoji: '🧠', label: 'I think about it multiple times a day'),
    (emoji: '😕', label: 'Skin issues — acne, dark circles'),
  ];

  @override
  Widget build(BuildContext context) {
    final n = selected.length;
    return OnbScaffold(
      progress: progress,
      onBack: onBack,
      footer: OnbCta(label: 'Continue', enabled: n > 0, onTap: n > 0 ? onNext : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const OnbHeadline(
            text: 'What are you ',
            emphasis: 'struggling with?',
            align: TextAlign.start,
            sub: 'Select all that apply — be honest with yourself.'),
          const SizedBox(height: 22),
          for (final o in _opts) ...[
            OnbMultiRow(
              emoji: o.emoji, label: o.label,
              selected: selected.contains(o.label),
              onTap: () => onToggle(o.label)),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  12 · EMPATHY / 89% PROOF
// ═══════════════════════════════════════════════════════════════════════════
class _EmpathyStep extends StatelessWidget {
  final double progress;
  final VoidCallback onBack, onNext;
  const _EmpathyStep({
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
          const SizedBox(height: 16),
          const OnbHeadline(text: 'We get it.', size: 30),
          const SizedBox(height: 28),
          SizedBox(
            width: 190, height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(190, 190),
                  painter: _RingArcPainter(progress: 0.89, color: Onb.primary)),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('89%',
                      style: GoogleFonts.poppins(
                        color: Onb.primaryLite, fontSize: 46, height: 1,
                        fontWeight: FontWeight.w800, letterSpacing: -2)),
                    Text('of users',
                      style: GoogleFonts.inter(
                        color: Onb.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Onb.card,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: Onb.cardBorder)),
            child: Text('feel more attractive & confident',
              style: GoogleFonts.inter(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 14),
          Text('after 28 days of following their personal plan.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Onb.grey, fontSize: 14, height: 1.4, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _RingArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _RingArcPainter({required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final c = (Offset.zero & size).center;
    final r = (math.min(size.width, size.height) - 14) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 13
      ..strokeCap = StrokeCap.round..color = Onb.card;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi/2, math.pi*2, false, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 13
      ..strokeCap = StrokeCap.round..color = color;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi/2, math.pi*2*progress, false, arc);
  }
  @override
  bool shouldRepaint(_RingArcPainter old) => old.progress != progress;
}

// ═══════════════════════════════════════════════════════════════════════════
//  13 · IDENTITY FORK
// ═══════════════════════════════════════════════════════════════════════════
class _IdentityForkStep extends StatelessWidget {
  final double progress;
  final VoidCallback onBack, onNext;
  const _IdentityForkStep({
    required this.progress,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return OnbScaffold(
      progress: progress,
      onBack: onBack,
      footer: OnbCta(label: 'That\'s the one', onTap: onNext),
      child: Column(
        children: [
          const SizedBox(height: 8),
          const OnbHeadline(
            text: 'Which one do you ',
            emphasis: 'want to be?',
            sub: 'Same face. Drag the last screen to see the difference.'),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _ForkCard(
                asset: 'assets/marketing/before.jpg',
                tag: 'Bloated now', color: Onb.danger,
                bullets: const [
                  'Wake up puffy',
                  'Soft, blurred jaw',
                  'Camera-shy',
                ])),
              const SizedBox(width: 12),
              Expanded(child: _ForkCard(
                asset: 'assets/marketing/after.jpg',
                tag: 'Your glow-up', color: Onb.success,
                bullets: const [
                  'Wake up drained',
                  'Sharp, defined jaw',
                  'Turn heads',
                ])),
            ],
          ),
        ],
      ),
    );
  }
}

class _ForkCard extends StatelessWidget {
  final String asset, tag;
  final Color color;
  final List<String> bullets;
  const _ForkCard({
    required this.asset,
    required this.tag,
    required this.color,
    required this.bullets,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Onb.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Image.asset(asset, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Onb.bg,
                  child: Icon(Icons.face_rounded, color: color, size: 48))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(100)),
                  child: Text(tag.toUpperCase(),
                    style: GoogleFonts.inter(
                      color: color, fontSize: 9.5, letterSpacing: 0.8,
                      fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 10),
                for (final b in bullets) Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.circle, color: color, size: 6),
                      const SizedBox(width: 7),
                      Expanded(child: Text(b,
                        style: GoogleFonts.inter(
                          color: Colors.white, fontSize: 12.5, height: 1.25,
                          fontWeight: FontWeight.w600))),
                    ],
                  ),
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
//  14 · ROUTINE VALUE GRAPH → hands off to the scan
// ═══════════════════════════════════════════════════════════════════════════
class _RoutineGraphStep extends StatelessWidget {
  final double progress;
  final VoidCallback onBack, onNext;
  const _RoutineGraphStep({
    required this.progress,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return OnbScaffold(
      progress: progress,
      onBack: onBack,
      footer: OnbCta(label: 'Scan my face', onTap: onNext),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: GoogleFonts.poppins(
                color: Onb.primaryLite, fontSize: 28, height: 1.15,
                fontWeight: FontWeight.w800, letterSpacing: -0.5),
              children: const [
                TextSpan(text: 'A real routine drains you '),
                TextSpan(text: '4× faster.',
                  style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('Most people never know which routine actually suits '
              'their face. Yours is built from your scan.',
            style: GoogleFonts.inter(
              color: Onb.grey, fontSize: 15, height: 1.45,
              fontWeight: FontWeight.w500)),
          const SizedBox(height: 28),
          Container(
            height: 220,
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            decoration: BoxDecoration(
              color: Onb.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Onb.cardBorder)),
            child: CustomPaint(
              size: Size.infinite,
              painter: _CurvePainter()),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _pill('Now', Onb.grey),
              _pill('Your glow-up', Onb.primary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(100),
      border: Border.all(color: c.withValues(alpha: 0.5))),
    child: Text(t, style: GoogleFonts.inter(
      color: c == Onb.grey ? Onb.grey : Onb.primaryLite,
      fontSize: 12.5, fontWeight: FontWeight.w700)),
  );
}

class _CurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // rising curve bottom-left → top-right
    final path = Path()
      ..moveTo(0, h * 0.9)
      ..cubicTo(w * 0.4, h * 0.88, w * 0.6, h * 0.5, w, h * 0.1);
    final fill = Path.from(path)
      ..lineTo(w, h)..lineTo(0, h)..close();
    canvas.drawPath(fill, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0x556C4CF5), Color(0x006C4CF5)],
      ).createShader(Rect.fromLTWH(0, 0, w, h)));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round..color = const Color(0xFF6C4CF5));
    // start + end dots
    canvas.drawCircle(Offset(0, h * 0.9), 6, Paint()..color = const Color(0xFF9A9AB0));
    canvas.drawCircle(Offset(w, h * 0.1), 7, Paint()..color = const Color(0xFFA78BFA));
  }
  @override
  bool shouldRepaint(_CurvePainter old) => false;
}
