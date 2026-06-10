// Hand-generated Firebase options. The standard FlutterFire CLI
// output, recreated here so we don't need to run the CLI inside the
// remote dev box. Values pulled from:
//   ios/Runner/GoogleService-Info.plist
//   android/app/google-services.json
//
// Wired into Firebase.initializeApp(options: DefaultFirebaseOptions
// .currentPlatform) in analytics_service.dart — that's the path that
// actually works without the iOS plist being registered as a bundled
// resource in the Xcode project.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Web is not configured for ImHim Firebase. '
        'Drop in web options if/when a web build ships.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return _ios;
      case TargetPlatform.android:
        return _android;
      default:
        throw UnsupportedError(
          'ImHim Firebase is only configured for iOS + Android.',
        );
    }
  }

  static const _ios = FirebaseOptions(
    apiKey:            'AIzaSyCS4IezUsdIuTjO80L8fk7AnHyNwREIcf4',
    appId:             '1:18046958403:ios:a5110f75386d960acdcdf6',
    messagingSenderId: '18046958403',
    projectId:         'mirrorly-f5a1b',
    storageBucket:     'mirrorly-f5a1b.firebasestorage.app',
    iosBundleId:       'com.mirrorly.app',
  );

  static const _android = FirebaseOptions(
    apiKey:            'AIzaSyBNbzoG8rMZeA0wT4Mb8aBy0Bl-m_H3Yj0',
    appId:             '1:18046958403:android:a30b7c849c91d683cdcdf6',
    messagingSenderId: '18046958403',
    projectId:         'mirrorly-f5a1b',
    storageBucket:     'mirrorly-f5a1b.firebasestorage.app',
  );
}
