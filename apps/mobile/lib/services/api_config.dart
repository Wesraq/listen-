import 'dart:io';

/// Listen+ API base URL for the local Nest API (`apps/api`).
///
/// Override when your Mac Wi‑Fi IP changes:
/// `flutter run --dart-define=LISTEN_API_BASE=http://192.168.1.180:3001/v1`
///
/// Physical phones cannot use 127.0.0.1 — that is the phone itself.
class ApiConfig {
  static const _fromDefine = String.fromEnvironment('LISTEN_API_BASE');

  /// Current Mac LAN IP serving `apps/api` (update when Wi‑Fi DHCP changes).
  static const lanDevHost = 'http://192.168.1.180:3001/v1';

  static const loopback = 'http://127.0.0.1:3001/v1';

  static String get baseUrl {
    if (_fromDefine.isNotEmpty) return _fromDefine;
    // Prefer LAN for all mobile targets so a physical device install works.
    if (Platform.isIOS || Platform.isAndroid) return lanDevHost;
    return loopback;
  }
}
