import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error, stackTrace) {
    // Keep the prototype usable on platforms that are not Firebase-configured yet.
    debugPrint('Firebase init skipped/failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  runApp(const ListenPlusApp());
}
