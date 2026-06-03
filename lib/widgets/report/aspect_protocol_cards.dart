import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/face_geometry.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// ASPECT PROTOCOL CARDS — the four things that actually move the
/// needle on a man\'s face over 60 days. Plain English. Real action,
/// no jargon. Each card opens a /protocol screen that auto-starts
/// the right ProtocolService template against the latest scan.
///
/// Order — sleep is the cheapest fastest visible win, so SKIN
/// (sleep + SPF + retinol routine) leads. JAW second (body comp +
/// training is the bones-and-leanness lever). DEBLOAT third (water
/// + sodium + alcohol fixes facial puffiness within DAYS, visible
/// in the mirror tomorrow). HAIR fourth (the longest-feedback
/// intervention — judged at 6 months).
class AspectProtocolCards extends StatelessWidget {
  final FaceGeometry geometry;
  final String?      savedImagePath;
  const AspectProtocolCards({
    super.key,
    required this.geometry,
    this.savedImagePath,
  });

  @override
  Widget build(BuildContext context) {
    final aspects = _aspects;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('60-DAY PROTOCOLS',
          style: AppTypography.label.copyWith(
            color: AppColors.textTertiary,
            letterSpacing: 2.6,
            fontSize: 10.5,
            fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('Pick one. Do it daily. Re-scan day 30 and day 60.',
          style: GoogleFonts.inter(
            color: AppColors.textTertiary,
            fontSize: 11.5,
            height: 1.4,
            fontStyle: FontStyle.italic,
          )),
        const SizedBox(height: 12),
        for (int i = 0; i < aspects.length; i++) ...[
          _AspectCard(
            aspect: aspects[i],
            onTap: () {
              HapticFeedback.mediumImpact();
              // Pass the axis pulldown string in extras — the router
              // forwards it to ProtocolScreen, which auto-starts a
              // protocol on the chosen axis when none is active.
              // Avoids the "No active protocol" dead end.
              context.push(
                '/protocol',
                extra: {
                  'pulldown':       aspects[i].pulldownString,
                  'axis':           aspects[i].axisKey,
                  'geometry':       geometry,
                  'savedImagePath': savedImagePath,
                },
              );
            },
          ),
          if (i < aspects.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ─── The four aspects, in plain English ────────────────────────────────
  //
  // Every line is something a 22-year-old can do without a doctor, a
  // gym, or a $200 stack. Where a real intervention helps (tretinoin,
  // minoxidil, finasteride) we name it but don\'t pretend a card is a
  // prescription. The "WHY" line at the bottom of each card gives the
  // one-sentence reason that lever works — the user gets the what AND
  // the why without wading through a paper.
  List<_Aspect> get _aspects => const [
    _Aspect(
      axisKey:        'skin',
      pulldownString: 'Skin',
      title:          'SKIN',
      oneLiner:       'The fastest visible win. You\'ll see it in 4 weeks.',
      color:          AppColors.signalGreen,
      phases: [
        _Phase(label: 'EVERY MORNING', body: 'Wash your face. SPF 30+ before you leave the house. Drink a full glass of water.'),
        _Phase(label: 'EVERY NIGHT',   body: 'Wash again. A tiny pump of retinol cream every third night for week 1, then every other night. Sleep on your back.'),
        _Phase(label: 'EVERY WEEK',    body: 'One photo in the same light. No alcohol on weekdays. No touching your face during the day.'),
      ],
      why: 'Sun + sleep + retinol fix more skin in 30 days than any product stack.',
    ),
    _Aspect(
      axisKey:        'jaw',
      pulldownString: 'Jaw definition',
      title:          'JAW',
      oneLiner:       'The single biggest face change you control.',
      color:          AppColors.red,
      phases: [
        _Phase(label: 'EVERY MORNING', body: 'Eat protein at breakfast — eggs, yogurt, or shake. Walk 20 minutes before you sit down to anything.'),
        _Phase(label: 'TRAINING DAYS', body: '4 lifts a week. Push press, dips, pull-ups, deadlift. Train your neck twice a week. Hard food at lunch.'),
        _Phase(label: 'EVERY WEEK',    body: 'Weigh in. Hit 1g protein per pound of bodyweight. Trim your beard along your jaw line, not below it.'),
      ],
      why: 'Lean to 12-14% body fat, train shoulders, and your jaw appears. Bones don\'t change. Composition does.',
    ),
    _Aspect(
      axisKey:        'debloat',
      pulldownString: 'Puffiness',
      title:          'DEBLOAT',
      oneLiner:       'Visible tomorrow morning. The cheapest fix on the list.',
      color:          AppColors.signalAmber,
      phases: [
        _Phase(label: 'EVERY DAY',     body: 'Drink 2.5 litres of water. Cut salty processed food. No alcohol for 14 days straight.'),
        _Phase(label: 'EVERY NIGHT',   body: 'Sleep on your back, on two pillows so your head is slightly raised. 8 hours, dark room.'),
        _Phase(label: 'EVERY MORNING', body: 'Splash cold water on your face for 30 seconds. Walk for 15 minutes before you eat.'),
      ],
      why: 'Most face puffiness is water + sodium + bad sleep. Cut the three for two weeks and your face sharpens overnight.',
    ),
    _Aspect(
      axisKey:        'hair',
      pulldownString: 'Hair',
      title:          'HAIR',
      oneLiner:       'Long game. Worth it. Judge it at 6 months, not next week.',
      color:          AppColors.measure,
      phases: [
        _Phase(label: 'EVERY DAY',     body: 'A daily multivitamin. Massage your scalp for 2 minutes when you wash your hair. Gentle shampoo, not the cheapest one.'),
        _Phase(label: 'EVERY NIGHT',   body: 'Silk pillowcase — friction during sleep breaks hair shafts. 7-9 hours of sleep. Don\'t go to bed with wet hair.'),
        _Phase(label: 'IF RECEDING',   body: 'See a doctor about minoxidil or oral finasteride. They\'re the only two with real evidence. Photo your hairline today so you can compare in 6 months.'),
      ],
      why: 'The earlier you act on a moving hairline, the more you keep. Most men wait years too long.',
    ),
  ];
}

class _Aspect {
  final String        axisKey;        // canonical aspect key
  final String        pulldownString; // forwarded to /protocol → ProtocolService
  final String        title;
  final String        oneLiner;
  final String        why;
  final Color         color;
  final List<_Phase>  phases;
  const _Aspect({
    required this.axisKey,
    required this.pulldownString,
    required this.title,
    required this.oneLiner,
    required this.why,
    required this.color,
    required this.phases,
  });
}

class _Phase {
  final String label;
  final String body;
  const _Phase({required this.label, required this.body});
}

class _AspectCard extends StatelessWidget {
  final _Aspect       aspect;
  final VoidCallback  onTap;
  const _AspectCard({required this.aspect, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Rd.xl),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(Rd.xl),
            border: Border.all(
              color: aspect.color.withValues(alpha: 0.55), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: aspect.color.withValues(alpha: 0.16),
                blurRadius: 18, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: aspect.color,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(aspect.title,
                      style: AppTypography.label.copyWith(
                        color: Colors.black, fontSize: 10,
                        letterSpacing: 2.2,
                        fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('60-day plan',
                      style: GoogleFonts.inter(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                        letterSpacing: 1.3,
                        fontStyle: FontStyle.italic,
                      )),
                  ),
                  Icon(Icons.arrow_forward_rounded,
                      color: aspect.color.withValues(alpha: 0.7), size: 18),
                ],
              ),
              const SizedBox(height: 10),
              Text(aspect.oneLiner,
                style: GoogleFonts.playfairDisplay(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                )),
              const SizedBox(height: 12),
              for (final p in aspect.phases) ...[
                _PhaseRow(phase: p, color: aspect.color),
                if (p != aspect.phases.last) const SizedBox(height: 8),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: aspect.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: aspect.color.withValues(alpha: 0.3), width: 0.6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WHY ',
                      style: AppTypography.label.copyWith(
                        color: aspect.color,
                        fontSize: 9,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w900)),
                    Expanded(
                      child: Text(aspect.why,
                        style: GoogleFonts.inter(
                          color: AppColors.textSecondary,
                          fontSize: 11.5,
                          height: 1.4,
                          fontStyle: FontStyle.italic,
                        )),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: aspect.color,
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: [
                    BoxShadow(
                      color: aspect.color.withValues(alpha: 0.4),
                      blurRadius: 14, offset: const Offset(0, 4)),
                  ],
                ),
                child: Text('START THIS PLAN',
                  style: AppTypography.label.copyWith(
                    color: Colors.black,
                    fontSize: 11,
                    letterSpacing: 2.4,
                    fontWeight: FontWeight.w900,
                  )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhaseRow extends StatelessWidget {
  final _Phase phase;
  final Color  color;
  const _PhaseRow({required this.phase, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 6, height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(phase.label,
                style: AppTypography.label.copyWith(
                  color: color,
                  fontSize: 9.5,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w900,
                )),
              const SizedBox(height: 2),
              Text(phase.body,
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                )),
            ],
          ),
        ),
      ],
    );
  }
}
