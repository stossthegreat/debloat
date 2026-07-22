import 'dart:typed_data';
import 'package:go_router/go_router.dart';
import '../models/face_geometry.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/legal/legal_screen.dart';
import '../screens/onboarding/ai_consent_screen.dart';
import '../screens/onboarding/gender_pick_screen.dart';
import '../screens/onboarding/intro_reel_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/paywall/paywall_screen.dart';
import '../screens/progress/progress_screen.dart';
import '../screens/protocol/protocol_screen.dart';
import '../screens/scan/scan_screen.dart';
import '../screens/report/report_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/splash/splash_screen.dart';
import '../services/analytics_route_observer.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  // Every navigator push/pop/replace fires screen_view through
  // AnalyticsRouteObserver, which also updates
  // AnalyticsService.currentScreen so the app-lifecycle hook in
  // main.dart's MirrorApp can tag "where did the user quit from".
  observers: [AnalyticsRouteObserver()],
  routes: [
    GoRoute(path: '/',           builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/intro',      builder: (_, __) => const IntroReelScreen()),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
    // Pre-scan gender pick. First-launch users get routed here from
    // splash; existing users can re-open it from Settings → Glow-up
    // style with `extra: {'fromSettings': true}`.
    GoRoute(
      path: '/onboarding/gender',
      builder: (context, state) {
        final extra = state.extra is Map<String, dynamic>
            ? state.extra as Map<String, dynamic>
            : const <String, dynamic>{};
        return GenderPickScreen(
          fromSettings: extra['fromSettings'] == true,
        );
      },
    ),
    // AI-data consent — sits between the gender pick and the first scan
    // so every new user grants permission before any data reaches a
    // third-party AI service (App Store 5.1.1(i) / 5.1.2(i)).
    GoRoute(
      path: '/onboarding/consent',
      builder: (_, __) => const AiConsentScreen(),
    ),
    GoRoute(
      path: '/paywall',
      builder: (context, state) {
        final extra = state.extra;
        return PaywallScreen(
          context: extra is Map<String, dynamic> ? extra : null,
        );
      },
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) {
        final extra = state.extra is Map<String, dynamic>
            ? state.extra as Map<String, dynamic>
            : const <String, dynamic>{};
        return HomeScreen(initialTab: (extra['initialTab'] as int?));
      },
    ),
    GoRoute(path: '/scan',     builder: (_, __) => const ScanScreen()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    GoRoute(
      path: '/protocol',
      builder: (_, state) {
        // Optional extras — the report\'s aspect-protocol cards pass
        // {pulldown: "Skin"} (or "Jaw definition", "Hair", "Puffiness")
        // so the screen auto-starts a brand-new protocol on the right
        // axis when none is active. Home tab tap passes nothing, falls
        // back to Foundations against the latest scan inside the screen.
        String? startPulldown;
        final extra = state.extra;
        if (extra is Map) {
          final v = extra['pulldown'];
          if (v is String && v.trim().isNotEmpty) startPulldown = v.trim();
        }
        return ProtocolScreen(startPulldown: startPulldown);
      },
    ),
    // Progress page — direct deep-link reachable from the Looks tab
    // top-right "chart" icon. ProgressScreen reads the scan history
    // itself; the constructor params are kept null because nothing
    // in the body actually reads `latest`/`protocol`, and onReload
    // is a no-op here (pull-to-refresh just re-runs the screen's
    // own _loadAll).
    GoRoute(
      path: '/progress',
      builder: (_, __) => ProgressScreen(
        latest:   null,
        protocol: null,
        onReload: () async {},
      ),
    ),
    GoRoute(path: '/terms',    builder: (_, __) => LegalScreen(doc: termsDoc)),
    GoRoute(path: '/privacy',  builder: (_, __) => LegalScreen(doc: privacyDoc)),
    GoRoute(
      path: '/report',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return ReportScreen(
          imageBytes:  extra['imageBytes'] as Uint8List,
          geometry:    extra['geometry']   as FaceGeometry,
          extraImages: (extra['extraImages'] as List?)?.cast<Uint8List>() ?? const [],
        );
      },
    ),
    // THE MIRROR — the AI glow-up chat, reached from the Transform tab
    // hero with the latest scan geometry.
    GoRoute(
      path: '/chat',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return ChatScreen(
          geometry:  extra['geometry']  as FaceGeometry,
          imagePath: extra['imagePath'] as String?,
          autoSend:  extra['autoSend']  as String?,
        );
      },
    ),
  ],
);
