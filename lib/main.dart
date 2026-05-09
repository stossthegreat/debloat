import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config/dev_flags.dart';
import 'navigation/app_router.dart';
import 'services/analytics_service.dart';
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

  // Dev-flag bypass: force the subscribed flag true so every gate in the
  // app (scan → report, Mirror tab, Progress tab, etc.) reads the user
  // as Pro without any purchase. Safe to leave on for local testing —
  // on a real release build this no-ops because kBypassPaywall is false.
  if (kBypassPaywall) {
    await LocalStoreService.setSubscribed(true);
  }

  runApp(const MirrorApp());
}

class MirrorApp extends StatelessWidget {
  const MirrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'MIRROR',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: appRouter,
    );
  }
}
