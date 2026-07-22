import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Firebase config for Debloat OS.
///
/// PLACEHOLDER — no Firebase project is linked yet. Create a new
/// Firebase project for `com.debloatos.app`, run `flutterfire
/// configure`, and this file gets regenerated with real values.
/// Until then AnalyticsService.init() catches the init failure and
/// every analytics call is a silent no-op — the app runs fine.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => const FirebaseOptions(
        apiKey:       'unconfigured',
        appId:        'unconfigured',
        messagingSenderId: 'unconfigured',
        projectId:    'unconfigured',
      );
}
