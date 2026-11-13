import 'dart:io';

/// Listen+ API base URL for the Nest API (`apps/api`).
///
/// Off-LAN testers (Firestore-backed API behind a tunnel / cloud host):
/// `flutter run --release --dart-define=LISTEN_API_BASE=https://YOUR_HOST/v1`
///
/// Local LAN:
/// `flutter run --dart-define=LISTEN_API_BASE=http://192.168.1.180:3001/v1`
///
/// Physical phones cannot use 127.0.0.1 — that is the phone itself.
/// Prefer [ApiDiscovery] so DHCP IP changes are handled automatically.
class ApiConfig {
  static const _fromDefine = String.fromEnvironment('LISTEN_API_BASE');

  /// Last-known Mac LAN IP serving `apps/api` (seed candidate only).
  static const lanDevHost = 'http://10.136.231.188:3001/v1';

  /// Cloud Run API (no local Mac required).
  static const publicDevHost =
      'https://listen-api-851945155141.us-central1.run.app/v1';

  static const loopback = 'http://127.0.0.1:3001/v1';

  static const androidEmulatorHost = 'http://10.0.2.2:3001/v1';

  static String get baseUrl {
    if (_fromDefine.isNotEmpty) return _fromDefine;
    // Prefer the public tunnel so installs work for remote testers.
    if (Platform.isIOS || Platform.isAndroid) return publicDevHost;
    return loopback;
  }

  /// Ordered probe list for [ApiDiscovery].
  static List<String> discoveryCandidates({String? cached}) {
    final out = <String>[];
    void add(String? value) {
      final v = value?.trim();
      if (v == null || v.isEmpty) return;
      if (!out.contains(v)) out.add(v);
    }

    add(_fromDefine.isNotEmpty ? _fromDefine : null);
    add(publicDevHost);
    add(cached);
    add(lanDevHost);
    if (Platform.isAndroid) add(androidEmulatorHost);
    add(loopback);
    return out;
  }
}
