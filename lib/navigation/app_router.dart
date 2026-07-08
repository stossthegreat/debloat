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

// ── Auralay graft (Eyes + Game tabs) ───────────────────────────────────────
import '../screens/debug/diagnostic_screen.dart';
import '../screens/eyes/selene_lesson_screen.dart';
import '../screens/game/pickup_line/pickup_line_screen.dart';
import '../screens/game/rizz/rizz_reply_screen.dart';
import '../screens/rizz/rizz_chat_screen.dart';
import '../screens/rizz/rizz_tab_screen.dart' show RizzCardAction;
import '../services/share_intake_service.dart' show SharedScreenshotPayload;
import '../models/gaze/gaze_syllabus.dart';
import '../screens/lessons/lesson_detail_screen.dart';
import '../screens/test/charisma_test_screen.dart';
import '../screens/test/result_reveal_screen.dart';
import '../screens/test/seduction_lesson_screen.dart' show PresenceLessonScreen;
import '../screens/test/seduction_test_screen.dart' show PresenceTestScreen;
import '../screens/train/post_session_screen.dart';
import '../screens/train/train_screen.dart';
import '../services/test/charisma_test_engine.dart';

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
    GoRoute(path: '/lines',    builder: (_, __) => const PickupLineScreen()),
    GoRoute(
      path: '/rizz',
      builder: (_, state) {
        final extra = state.extra;
        final launchUpload = extra is RizzCardAction && extra.launchUpload;
        // The iOS Share Extension routes here with the screenshot bytes
        // already loaded. The screen auto-fires the OCR + reply
        // pipeline as if the user had picked the image from Photos.
        final preloaded = extra is SharedScreenshotPayload ? extra.bytes : null;
        return RizzReplyScreen(
          launchUpload:        launchUpload,
          preloadedScreenshot: preloaded,
        );
      },
    ),
    GoRoute(
      path: '/rizz-chat',
      builder: (_, __) => const RizzChatScreen(),
    ),
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
    // Progress page — direct deep-link reachable from the Looks +
    // Rizz tab top-right "chart" icons. ProgressScreen reads the
    // scan history, game-score timeline, and Auralay training stats
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

    // ── Auralay-imported routes ─────────────────────────────────────────
    // Charisma test + result reveal + presence test (onboarding viral
    // hook funnel from Auralay — pushed by some lesson flows + post-
    // session screens). Result-reveal needs the photo + score extras.
    GoRoute(
      path: '/charisma-test',
      builder: (_, __) => const CharismaTestScreen(),
    ),
    GoRoute(
      path: '/presence-test',
      builder: (_, __) => const PresenceTestScreen(),
    ),
    GoRoute(
      path: '/presence-lesson',
      builder: (_, __) => const PresenceLessonScreen(),
    ),
    GoRoute(
      path: '/test-result',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>?;
        final result = extra?['result'] as CharismaTestResult?;
        if (result == null) {
          // Shouldn't ever hit — push always carries a result. Bail
          // gracefully to home rather than crash on the cast.
          return const HomeScreen();
        }
        return ResultRevealScreen(
          result:          result,
          photoBytes:      extra?['photoBytes'] as Uint8List?,
          eyeY:            extra?['eyeY'] as double?,
          isFreeTraining:  (extra?['isFreeTraining'] as bool?)   ?? false,
          isPresenceTest: (extra?['isPresenceTest'] as bool?)  ?? false,
        );
      },
    ),

    // Eye-contact training + post-session reflection.
    GoRoute(path: '/train', builder: (_, __) => const TrainScreen()),
    GoRoute(
      path: '/post-session',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return PostSessionScreen(results: extra ?? const {});
      },
    ),

    // Lesson detail (Auralay's Eyes-tab curriculum, hit from the You
    // section of Progress tab and from the bottom-sheet picker).
    GoRoute(
      path: '/lesson/:id',
      builder: (_, state) {
        final id = state.pathParameters['id'] ?? '';
        final extra = state.extra as Map<String, dynamic>?;
        final currentDay = (extra?['currentDay'] as int?) ?? 1;
        return LessonDetailScreen(techniqueId: id, currentDay: currentDay);
      },
    ),

    // Auralay's profile route — folded into Mirrorly's HomeScreen
    // Progress tab (tab index 4). Pushing /you lands on that tab.
    GoRoute(
      path: '/you',
      builder: (_, __) => const HomeScreen(initialTab: 4),
    ),

    // SELENE — live AI gaze lesson. Realtime API persona that frames,
    // teaches, runs the drill, coaches in real time against the
    // apprentice's face metrics, and debriefs in her own voice. The
    // proof build ships THE LOCK; other lessons fall through to the
    // same persona until each gets its own masterclass prompt.
    GoRoute(
      path: '/eyes/live/:id',
      builder: (_, state) {
        final id = state.pathParameters['id'] ?? 'the_lock';
        return SeleneLessonScreen(lesson: GazeSyllabus.byId(id));
      },
    ),

    // Debug HUD (Auralay's diagnostic console, gated behind 5-tap easter
    // egg in Settings). Useful for backend health checks post-graft.
    GoRoute(path: '/diagnostic', builder: (_, __) => const DiagnosticScreen()),
  ],
);
