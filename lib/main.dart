import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/dev_flags.dart';
import 'navigation/app_router.dart';
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

  // Retention engine — rolling 14-day horizon, morning DREAM pump +
  // evening STREAK nudge, refreshed on every app open. markAppOpened
  // stamps the open time then rebuilds the whole horizon. This is the
  // SINGLE source of truth for retention notifications now; the legacy
  // streak/training/rescan schedulers are no longer wired in (they'd
  // only fight the horizon by competing for the same OS slots).
  // ignore: discarded_futures
  DailyNudgeService.markAppOpened();

  // Dev-flag bypass: force the subscribed flag true so every gate in the
  // app (scan → report, Mirror tab, Progress tab, etc.) reads the user
  // as Pro without any purchase. Safe to leave on for local testing —
  // on a real release build this no-ops because kBypassPaywall is false.
  if (kBypassPaywall) {
    await LocalStoreService.setSubscribed(true);
  } else {
    // v375 — the locks are back on for distribution. The v373/v374
    // test builds force-wrote subscribed=true above; clear that stale
    // cache ONCE so bypass-era installs re-lock. Real subscribers are
    // re-validated live by RevenueCat on their next gate check.
    await LocalStoreService.resetBypassSubscribedOnce();
  }

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
        // v280 — clear the iOS app-icon badge (red unread-count dot)
        // as soon as the user foregrounds the app. Opening the app
        // IS the "I saw the notification" signal; leaving the dot
        // on after the open looks broken and stops being a useful
        // retention trigger for the NEXT notification.
        // ignore: discarded_futures
        NotificationService.clearIconBadge();
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
    return MaterialApp.router(
      title: 'Debloat OS',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: appRouter,
    );
  }
}
