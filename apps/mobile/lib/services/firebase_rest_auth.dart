import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// Firebase Auth via Identity Toolkit REST — works on Android without
/// `google-services.json` / native Firebase init.
class FirebaseRestAuthService implements AuthService {
  FirebaseRestAuthService({
    http.Client? client,
    this.apiKey = defaultApiKey,
  }) : _client = client ?? http.Client();

  /// Browser / iOS key from Firebase project `listenplus-d9188`.
  static const defaultApiKey = 'AIzaSyAU0ScStCC92qekvuPTNAEmBHrNKIu1tqs';

  static const _prefsUid = 'listen_rest_auth_uid';
  static const _prefsEmail = 'listen_rest_auth_email';
  static const _prefsName = 'listen_rest_auth_name';
  static const _prefsIdToken = 'listen_rest_auth_id_token';
  static const _prefsRefresh = 'listen_rest_auth_refresh';
  static const _prefsDeviceEmail = 'listen_rest_device_email';
  static const _prefsDevicePassword = 'listen_rest_device_password';
  static const _prefsIsDevice = 'listen_rest_auth_is_device';

  final http.Client _client;
  final String apiKey;

  AuthUser? _user;
  String? _idToken;
  String? _refreshToken;
  bool _isDeviceSession = false;
  bool _hydrated = false;

  @override
  bool get isAvailable => true;

  /// True when the active session is a silent device guest (not a real account).
  bool get isDeviceSession => _isDeviceSession;

  @override
  AuthUser? get currentUser => _isDeviceSession ? null : _user;

  @override
  Stream<AuthUser?> authStateChanges() async* {
    await _ensureHydrated();
    yield currentUser;
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    await _ensureHydrated();
    if (_idToken == null || _idToken!.isEmpty) return null;
    if (forceRefresh) {
      final ok = await _refreshIdToken();
      if (!ok) return null;
    }
    return _idToken;
  }

  /// Ensures a Firebase token exists for free-media signing, without surfacing
  /// a signed-in Listen+ account in the UI.
  Future<void> ensureDeviceSession() async {
    await _ensureHydrated();
    if (_idToken != null && _idToken!.isNotEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    var email = prefs.getString(_prefsDeviceEmail);
    var password = prefs.getString(_prefsDevicePassword);
    if (email == null || password == null) {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      email = 'device.$stamp@guest.listenplus.app';
      password = _randomPassword();
      await prefs.setString(_prefsDeviceEmail, email);
      await prefs.setString(_prefsDevicePassword, password);
    }

    try {
      await _signInRaw(email: email, password: password, deviceSession: true);
    } on AuthException {
      await _signUpRaw(
        email: email,
        password: password,
        displayName: 'Guest',
        deviceSession: true,
      );
    }
  }

  @override
  Future<AuthUser> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _ensureHydrated();
    return _signUpRaw(
      email: email.trim(),
      password: password,
      displayName: displayName.trim(),
      deviceSession: false,
    );
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    await _ensureHydrated();
    return _signInRaw(
      email: email.trim(),
      password: password,
      deviceSession: false,
    );
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    final response = await _client.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=$apiKey',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'requestType': 'PASSWORD_RESET',
        'email': email.trim(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(_messageFromBody(response.body, fallback: 'Could not send reset email.'));
    }
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    await _ensureHydrated();
    final token = _idToken;
    if (token == null || _isDeviceSession) {
      throw AuthException('Sign in before updating your profile.');
    }
    final response = await _client.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:update?key=$apiKey',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': token,
        'displayName': displayName.trim(),
        'returnSecureToken': false,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(_messageFromBody(response.body, fallback: 'Could not update profile.'));
    }
    _user = AuthUser(
      uid: _user!.uid,
      email: _user!.email,
      displayName: displayName.trim(),
    );
    await _persist();
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _idToken = null;
    _refreshToken = null;
    _isDeviceSession = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsUid);
    await prefs.remove(_prefsEmail);
    await prefs.remove(_prefsName);
    await prefs.remove(_prefsIdToken);
    await prefs.remove(_prefsRefresh);
    await prefs.remove(_prefsIsDevice);
  }

  Future<void> _ensureHydrated() async {
    if (_hydrated) return;
    _hydrated = true;
    final prefs = await SharedPreferences.getInstance();
    _idToken = prefs.getString(_prefsIdToken);
    _refreshToken = prefs.getString(_prefsRefresh);
    _isDeviceSession = prefs.getBool(_prefsIsDevice) ?? false;
    final uid = prefs.getString(_prefsUid);
    if (uid != null && uid.isNotEmpty) {
      _user = AuthUser(
        uid: uid,
        email: prefs.getString(_prefsEmail),
        displayName: prefs.getString(_prefsName),
      );
    }
    if (_refreshToken != null && _refreshToken!.isNotEmpty) {
      await _refreshIdToken();
    }
  }

  Future<AuthUser> _signUpRaw({
    required String email,
    required String password,
    required String displayName,
    required bool deviceSession,
  }) async {
    final response = await _client.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(_messageFromBody(response.body));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw AuthException('Account was created, but no user was returned. Try signing in.');
    }
    await _applyAuthMap(
      Map<String, dynamic>.from(decoded),
      displayName: displayName,
      deviceSession: deviceSession,
    );
    if (!deviceSession && displayName.isNotEmpty) {
      try {
        await updateDisplayName(displayName);
      } catch (_) {}
    }
    return currentUser ??
        AuthUser(uid: '${decoded['localId']}', email: email, displayName: displayName);
  }

  Future<AuthUser> _signInRaw({
    required String email,
    required String password,
    required bool deviceSession,
  }) async {
    final response = await _client.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey',
      ),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(_messageFromBody(response.body));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw AuthException('Sign-in succeeded, but no user was returned.');
    }
    await _applyAuthMap(
      Map<String, dynamic>.from(decoded),
      displayName: decoded['displayName']?.toString(),
      deviceSession: deviceSession,
    );
    final user = currentUser;
    if (user == null) {
      throw AuthException('Sign-in succeeded, but no user was returned.');
    }
    return user;
  }

  Future<void> _applyAuthMap(
    Map<String, dynamic> decoded, {
    String? displayName,
    required bool deviceSession,
  }) async {
    final uid = '${decoded['localId'] ?? ''}';
    if (uid.isEmpty) {
      throw AuthException('Authentication failed.');
    }
    _idToken = decoded['idToken']?.toString();
    _refreshToken = decoded['refreshToken']?.toString();
    _isDeviceSession = deviceSession;
    _user = AuthUser(
      uid: uid,
      email: decoded['email']?.toString(),
      displayName: displayName ?? decoded['displayName']?.toString(),
    );
    await _persist();
  }

  Future<bool> _refreshIdToken() async {
    final refresh = _refreshToken;
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final response = await _client.post(
        Uri.parse('https://securetoken.googleapis.com/v1/token?key=$apiKey'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'grant_type=refresh_token&refresh_token=${Uri.encodeQueryComponent(refresh)}',
      );
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return false;
      final next = decoded['id_token']?.toString();
      final nextRefresh = decoded['refresh_token']?.toString();
      if (next == null || next.isEmpty) return false;
      _idToken = next;
      if (nextRefresh != null && nextRefresh.isNotEmpty) {
        _refreshToken = nextRefresh;
      }
      await _persist();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_user == null || _idToken == null) return;
    await prefs.setString(_prefsUid, _user!.uid);
    await prefs.setString(_prefsEmail, _user!.email ?? '');
    await prefs.setString(_prefsName, _user!.displayName ?? '');
    await prefs.setString(_prefsIdToken, _idToken!);
    await prefs.setString(_prefsRefresh, _refreshToken ?? '');
    await prefs.setBool(_prefsIsDevice, _isDeviceSession);
  }

  String _randomPassword() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'Lp!$stamp!Aa1';
  }

  String _messageFromBody(String body, {String? fallback}) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final message = '${error['message'] ?? ''}';
          return switch (message) {
            'EMAIL_EXISTS' =>
              'That email already has a Listen+ account. Sign in instead.',
            'INVALID_EMAIL' => 'Enter a valid email address.',
            'WEAK_PASSWORD' || 'WEAK_PASSWORD : Password should be at least 6 characters' =>
              'Choose a stronger password (at least 8 characters, with a letter and a number).',
            'EMAIL_NOT_FOUND' || 'INVALID_PASSWORD' || 'INVALID_LOGIN_CREDENTIALS' =>
              'Email or password is incorrect.',
            'USER_DISABLED' => 'This account has been disabled. Contact support.',
            'TOO_MANY_ATTEMPTS_TRY_LATER' => 'Too many attempts. Wait a moment and try again.',
            'OPERATION_NOT_ALLOWED' =>
              'Email/password sign-in is disabled in Firebase. Enable Email/Password under Authentication → Sign-in method.',
            _ => fallback ??
                (message.isNotEmpty
                    ? 'Authentication failed ($message).'
                    : 'Authentication failed. Try again.'),
          };
        }
      }
    } catch (_) {}
    return fallback ?? 'Authentication failed. Try again.';
  }
}
