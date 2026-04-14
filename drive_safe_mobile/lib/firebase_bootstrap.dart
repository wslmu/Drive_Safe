import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';

class FirebaseBootstrap {
  static bool _initialized = false;
  static bool _enabled = false;

  static bool get isEnabled => _enabled;

  static String? get uid {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid;
  }

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _enabled = true;
    } catch (_) {
      _enabled = false;
      return;
    }

    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (_) {
      // App still works with local mode if anonymous auth fails.
    }
  }
}
