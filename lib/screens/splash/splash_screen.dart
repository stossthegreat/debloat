import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../services/local_store_service.dart';
import '../../widgets/common/mirrorly_wordmark.dart';

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
    // 0) NOT ONBOARDED → always play the cinematic INTRO REEL, which
    //    leads into the full onboarding funnel. This must key off the
    //    ONBOARDED flag alone, NOT gender: the funnel sets gender at
    //    step 3, so gating on gender used to make a user who quit
    //    mid-funnel skip the entire reel + funnel on the next launch
    //    (they'd get dumped straight to /scan). The onboarded flag is
    //    only set when the funnel actually completes, so onboarding
    //    correctly replays until the user finishes it.
    //
    // 1) ONBOARDED but no gender (legacy installs from before the
    //    gender pick existed) → force a gender pick so downstream
    //    analysis/render isn't mis-coded.
    //
    // 2) ONBOARDED with gender → returning user → /home.
    if (!onboarded) {
      context.go('/intro');
    } else if (!hasGender) {
      context.go('/onboarding/gender');
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pure black loading screen — logo sitting a touch above centre with
    // the Debloat OS wordmark beneath it, set exactly like the Looks-tab
    // header. Bro: "move the logo higher then write Debloat OS in the same
    // way it's written on the Looks tab header."
    return Scaffold(
      backgroundColor: Colors.black,
      body: Align(
        alignment: const Alignment(0, -0.22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icons/appstore.png',
              width: 150,
              height: 150,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, __, ___) => const SizedBox(
                width: 150, height: 150,
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
            const SizedBox(height: 22),
            const MirrorlyWordmark(fontSize: 40)
                .animate()
                .fadeIn(delay: 260.ms, duration: 700.ms, curve: Curves.easeOut),
          ],
        ),
      ),
    );
  }
}
