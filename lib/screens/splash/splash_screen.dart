import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../services/local_store_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final onboarded   = await LocalStoreService.isOnboarded();
    final hasGender   = (await LocalStoreService.userGender()) != null;
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;

    // Gating order:
    //
    // 0) FIRST EVER LAUNCH (no gender, never onboarded) → play the
    //    cinematic INTRO REEL. It pushes /onboarding/gender after BEGIN
    //    so the rest of the funnel proceeds as designed.
    //
    // 1) Has the user picked Men's / Women's? If NOT — even if they've
    //    already completed onboarding on a previous version of the app
    //    — send them to /onboarding/gender and force a pick. Without
    //    this every analysis + render downstream stays male-coded for
    //    women, which is brand-killing.
    //
    // 2) Otherwise, returning user → /home.
    //
    // 3) Otherwise, fresh install (no onboarded flag, no gender) →
    //    /onboarding/gender too. Same destination as case 1 but the
    //    gender screen also serves as the entry funnel for first
    //    launches.
    if (!hasGender && !onboarded) {
      context.go('/intro');
    } else if (!hasGender) {
      context.go('/onboarding/gender');
    } else {
      context.go(onboarded ? '/home' : '/scan');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pure black loading screen — just the logo, centred, breathing in.
    // Bro: "change to use logo and black screen." No gradient wash, no
    // grid, no crosshair, no taglines — the mark carries it alone.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Image.asset(
          'assets/icons/appstore.png',
          width: 148,
          height: 148,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => const SizedBox(
            width: 148, height: 148,
          ),
        )
            .animate()
            .fadeIn(duration: 700.ms, curve: Curves.easeOut)
            .scale(
              begin: const Offset(0.94, 0.94),
              end: const Offset(1, 1),
              duration: 900.ms,
              curve: Curves.easeOut,
            ),
      ),
    );
  }
}
