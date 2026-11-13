import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'api_headers.dart';

/// Probes candidate Listen+ API base URLs and remembers the last healthy one.
class ApiDiscovery {
  ApiDiscovery({http.Client? client}) : _client = client ?? http.Client();

  static const _prefsKey = 'listen_api_base_v1';

  final http.Client _client;
  String? _resolved;

  String get baseUrl => _resolved ?? ApiConfig.baseUrl;

  Future<String> ensureResolved({bool force = false}) async {
    if (!force && _resolved != null) return _resolved!;

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsKey);

    // Prefer the known Cloud Run / dart-define host immediately — don't burn
    // seconds probing dead LAN IPs before every first request.
    final preferred = ApiConfig.baseUrl;
    if (await _healthy(preferred, timeout: const Duration(seconds: 4))) {
      _resolved = preferred;
      if (cached != preferred) await prefs.setString(_prefsKey, preferred);
      return preferred;
    }

    final candidates = ApiConfig.discoveryCandidates(cached: cached)
        .where((c) => c != preferred)
        .toList();

    for (final base in candidates) {
      // Skip obvious local/LAN hosts when we already have a public HTTPS API —
      // they just add multi-second timeouts on cellular.
      if (preferred.startsWith('https://') && _isLocalCandidate(base)) {
        continue;
      }
      if (await _healthy(base)) {
        _resolved = base;
        if (cached != base) await prefs.setString(_prefsKey, base);
        return base;
      }
    }

    _resolved = preferred;
    return _resolved!;
  }

  bool _isLocalCandidate(String base) {
    final lower = base.toLowerCase();
    return lower.contains('127.0.0.1') ||
        lower.contains('10.0.2.2') ||
        lower.contains('192.168.') ||
        lower.contains('10.136.') ||
        lower.contains('172.16.') ||
        lower.contains('169.254.');
  }

  Future<bool> _healthy(
    String base, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final uri = Uri.parse('$base/health');
      final response = await _client
          .get(uri, headers: tunnelAwareHeaders())
          .timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

}
