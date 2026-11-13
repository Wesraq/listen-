import 'dart:convert';

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
    final candidates = ApiConfig.discoveryCandidates(cached: cached);

    for (final base in candidates) {
      if (await _healthy(base)) {
        _resolved = base;
        if (cached != base) await prefs.setString(_prefsKey, base);
        return base;
      }
    }

    // Try expanding from a reachable health payload's lanHosts (if any candidate answered).
    for (final base in candidates) {
      final hosts = await _lanHosts(base);
      for (final host in hosts) {
        if (await _healthy(host)) {
          _resolved = host;
          await prefs.setString(_prefsKey, host);
          return host;
        }
      }
    }

    _resolved = ApiConfig.baseUrl;
    return _resolved!;
  }

  Future<bool> _healthy(String base) async {
    try {
      final uri = Uri.parse('$base/health');
      final response = await _client
          .get(uri, headers: tunnelAwareHeaders())
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> _lanHosts(String base) async {
    try {
      final uri = Uri.parse('$base/health');
      final response = await _client
          .get(uri, headers: tunnelAwareHeaders())
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return const [];
      final hosts = decoded['lanHosts'];
      if (hosts is! List) return const [];
      return hosts.whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }
}
