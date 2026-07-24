import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

/// Firebase config for Debloat OS (project `debloat-os`).
///
/// These are the real client keys for the app. Firebase client keys are
/// NOT secrets — they're designed to ship inside the app binary; access is
/// gated by Firebase Security Rules, not by key secrecy. AnalyticsService
/// .init() passes [currentPlatform] to Firebase.initializeApp().
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        // macOS / other Apple targets reuse the iOS app; anything else
        // falls back to iOS options too (harmless for analytics).
        return ios;
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBpcjjHaTxaNFLr3RQD2DGAG5a_UUvsv-A',
    appId: '1:1097524443399:ios:241ad75dff43b469142da2',
    messagingSenderId: '1097524443399',
    projectId: 'debloat-os',
    storageBucket: 'debloat-os.firebasestorage.app',
    iosBundleId: 'com.debloatos.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDCFP90zG72sbYAvQjVa5nbkxoafTbOUdM',
    appId: '1:1097524443399:android:eaf60baf9b6696fc142da2',
    messagingSenderId: '1097524443399',
    projectId: 'debloat-os',
    storageBucket: 'debloat-os.firebasestorage.app',
  );
}
