import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/admob_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error, stackTrace) {
    // Keep the prototype usable on platforms that are not Firebase-configured yet.
    debugPrint('Firebase init skipped/failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  // Never block first frame on ads — a native AdMob failure must not kill startup.
  runApp(const ListenPlusApp());
  unawaited(AdMobService.instance.initialise());
}
