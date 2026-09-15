import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Configure a separate Firebase project before enabling remote telemetry.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => throw UnsupportedError(
        'Firebase is not configured for OpenBand 5.',
      );
}
