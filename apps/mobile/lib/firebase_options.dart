// Generated from GoogleService-Info.plist for project listenplus-d9188.
// Android options will be added when google-services.json is provided.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Firebase web options are not configured for Listen+ yet.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios;
      case TargetPlatform.android:
        // Native Android Firebase options require google-services.json.
        // The app falls back to Identity Toolkit REST auth on Android.
        throw UnsupportedError(
          'Firebase Android native options are not configured yet; using REST auth.',
        );
      default:
        throw UnsupportedError('Firebase is not configured for this platform yet.');
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAU0ScStCC92qekvuPTNAEmBHrNKIu1tqs',
    appId: '1:851945155141:ios:e0263738a21b577d3e912c',
    messagingSenderId: '851945155141',
    projectId: 'listenplus-d9188',
    storageBucket: 'listenplus-d9188.firebasestorage.app',
    iosBundleId: 'io.listen.listen',
  );
}
