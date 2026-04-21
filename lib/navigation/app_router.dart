import 'dart:typed_data';
import 'package:go_router/go_router.dart';
import '../models/face_geometry.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/paywall/paywall_screen.dart';
import '../screens/protocol/protocol_screen.dart';
import '../screens/scan/scan_screen.dart';
import '../screens/report/report_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/splash/splash_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/',           builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
    GoRoute(path: '/paywall',    builder: (_, __) => const PaywallScreen()),
    GoRoute(path: '/home',     builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/scan',     builder: (_, __) => const ScanScreen()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    GoRoute(path: '/protocol', builder: (_, __) => const ProtocolScreen()),
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
