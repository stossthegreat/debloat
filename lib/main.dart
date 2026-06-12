import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/dev_flags.dart';
import 'navigation/app_router.dart';
import 'providers/auralay_app_provider.dart';
import 'services/analytics_service.dart';
import 'services/daily_nudge_service.dart';
import 'services/local_store_service.dart';
import 'services/notification_service.dart';
import 'services/purchase_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
  ));

  // Initialise Firebase + Analytics. Safe to call even before the
  // native config files (GoogleService-Info.plist / google-services
  // .json) are dropped in — the service catches the init error and
  // leaves every event call a silent no-op until config arrives.
  await AnalyticsService.init();
  AnalyticsService.appOpen();

  // Initialise RevenueCat. Safe to call even when keys aren't
  // configured yet — the service no-ops in that case and the rest of
  // the app runs as a dev stub (paywall shows "—" for prices, CTA is
  // disabled). See lib/config/purchase_config.dart for setup.
  await PurchaseService.init();

  // Initialise local notifications. Permission is NOT requested here —
  // it's deferred to the first protocol start so the prompt has context
  // ("your streak reminder").
  await NotificationService.init();

  // Daily retention nudge — single 7:30pm notification, state-picked
  // copy. Marks app-open + reschedules; this replaces the legacy
  // streak/training/rescan schedulers which fired too often.
  // ignore: discarded_futures
  DailyNudgeService.markAppOpened();

  // ── Auralay training-streak nudge ──────────────────────────────────────
  // Reschedule the 9pm training nudge with the latest streak state every
  // launch. Reads streak count directly from prefs so it works even
  // before the Provider has loaded. Idempotent — call site can be called
  // again from session log without conflict.
  try {
    final prefs = await SharedPreferences.getInstance();
    final streak = prefs.getInt('streak_days') ?? 0;
    await NotificationService.scheduleTrainingNudge(streakDays: streak);
  } catch (_) {
    // Non-fatal — the next session will reschedule.
  }

  // Dev-flag bypass: force the subscribed flag true so every gate in the
  // app (scan → report, Mirror tab, Progress tab, etc.) reads the user
  // as Pro without any purchase. Safe to leave on for local testing —
  // on a real release build this no-ops because kBypassPaywall is false.
  if (kBypassPaywall) {
    await LocalStoreService.setSubscribed(true);
  }

  // v181 one-shot — clear the stale gameFreeUsed bool that v171..v178
  // dispose() over-eagerly burnt for testers who only briefly held
  // the orb and then tab-switched. After this runs once, the flag
  // only flips at legitimate session-end (60s timer expiry / manual
  // end). See LocalStoreService.migrateGameFreeUsedFlagOnce.
  await LocalStoreService.migrateGameFreeUsedFlagOnce();

  runApp(const MirrorApp());
}

class MirrorApp extends StatefulWidget {
  const MirrorApp({super.key});

  @override
  State<MirrorApp> createState() => _MirrorAppState();
}

class _MirrorAppState extends State<MirrorApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // App-lifecycle observer — the drop-off detector. Pairs with the
    // AnalyticsRouteObserver wired into appRouter so every backgrounding
    // event carries the screen the user was looking at when they bailed.
    // Resumes also fire so we can measure session count + return cadence.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // ignore: discarded_futures
        AnalyticsService.appPaused();
        break;
      case AppLifecycleState.resumed:
        // ignore: discarded_futures
        AnalyticsService.appResumed();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
        // detached fires on cold-kill and is best-effort: the OS may
        // not give us long enough to flush the event over the wire.
        // We still try.
        // ignore: discarded_futures
        AnalyticsService.appPaused();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ChangeNotifierProvider wraps the app so the Auralay-imported state
    // (Aura score, current day, gaze streak) is reachable from the
    // Progress tab + the Eyes/Game session screens. Mirrorly's own state
    // continues to live in SharedPreferences-backed static services
    // (LocalStoreService, PurchaseService, etc.) — no migration needed.
    return ChangeNotifierProvider(
      create: (_) => AuralayAppProvider()..load(),
      child: MaterialApp.router(
        title: 'MIRROR',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routerConfig: appRouter,
      ),
    );
  }
}
