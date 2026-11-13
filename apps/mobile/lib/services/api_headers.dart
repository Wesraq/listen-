/// Extra HTTP headers needed for some public tunnel frontends.
Map<String, String> tunnelAwareHeaders([Map<String, String>? base]) {
  final headers = <String, String>{...?base};
  // localtunnel interstitial bypass (harmless on other hosts).
  headers.putIfAbsent('Bypass-Tunnel-Reminder', () => 'true');
  return headers;
}
