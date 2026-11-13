import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_rest_auth.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AuthUser {
  const AuthUser({
    required this.uid,
    required this.email,
    required this.displayName,
  });

  final String uid;
  final String? email;
  final String? displayName;
}

abstract class AuthService {
  bool get isAvailable;
  AuthUser? get currentUser;
  Stream<AuthUser?> authStateChanges();

  /// Firebase ID token for API Bearer auth, or null when unavailable.
  Future<String?> idToken({bool forceRefresh = false});

  Future<AuthUser> createAccount({
    required String email,
    required String password,
    required String displayName,
  });

  Future<AuthUser> signIn({
    required String email,
    required String password,
  });

  Future<void> sendPasswordReset(String email);
  Future<void> updateDisplayName(String displayName);
  Future<void> signOut();
}

class NoopAuthService implements AuthService {
  @override
  bool get isAvailable => false;

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> authStateChanges() => Stream<AuthUser?>.value(null);

  @override
  Future<String?> idToken({bool forceRefresh = false}) async => null;

  @override
  Future<AuthUser> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    throw AuthException('Firebase Auth is not available in this environment.');
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    throw AuthException('Firebase Auth is not available in this environment.');
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    throw AuthException('Firebase Auth is not available in this environment.');
  }

  @override
  Future<void> updateDisplayName(String displayName) async {}

  @override
  Future<void> signOut() async {}
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({FirebaseAuth? auth}) : _authOverride = auth;

  final FirebaseAuth? _authOverride;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  @override
  bool get isAvailable => Firebase.apps.isNotEmpty || _authOverride != null;

  @override
  AuthUser? get currentUser {
    if (!isAvailable) return null;
    return _map(_auth.currentUser);
  }

  @override
  Stream<AuthUser?> authStateChanges() {
    if (!isAvailable) return Stream<AuthUser?>.value(null);
    return _auth.authStateChanges().map(_map);
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    if (!isAvailable) return null;
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken(forceRefresh);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AuthUser> createAccount({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _ensureAvailable();
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw AuthException('Account was created, but no user was returned. Try signing in.');
      }
      await user.updateDisplayName(displayName.trim());
      await user.reload();
      return _map(_auth.currentUser) ??
          AuthUser(uid: user.uid, email: user.email, displayName: displayName.trim());
    } on FirebaseAuthException catch (error) {
      _logAuthError('createAccount', error);
      throw AuthException(_messageFor(error));
    }
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    _ensureAvailable();
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw AuthException('Sign-in succeeded, but no user was returned.');
      }
      return _map(user)!;
    } on FirebaseAuthException catch (error) {
      _logAuthError('signIn', error);
      throw AuthException(_messageFor(error));
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    _ensureAvailable();
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      _logAuthError('sendPasswordReset', error);
      throw AuthException(_messageFor(error));
    }
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    _ensureAvailable();
    final user = _auth.currentUser;
    if (user == null) {
      throw AuthException('Sign in before updating your profile.');
    }
    await user.updateDisplayName(displayName.trim());
    await user.reload();
  }

  @override
  Future<void> signOut() async {
    if (!isAvailable) return;
    await _auth.signOut();
  }

  void _ensureAvailable() {
    if (!isAvailable) {
      throw AuthException('Firebase is not ready on this device yet. Try again in a moment.');
    }
  }

  AuthUser? _map(User? user) {
    if (user == null) return null;
    return AuthUser(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
    );
  }

  void _logAuthError(String action, FirebaseAuthException error) {
    // Keep the console details for simulator debugging.
    // ignore: avoid_print
    print(
      'FirebaseAuth.$action failed code=${error.code} '
      'plugin=${error.plugin} message=${error.message} details=${error.toString()}',
    );
  }

  String _messageFor(FirebaseAuthException error) {
    return switch (error.code) {
      'email-already-in-use' => 'That email already has a Listen+ account. Sign in instead.',
      'invalid-email' => 'Enter a valid email address.',
      'weak-password' =>
        'Choose a stronger password (at least 8 characters, with a letter and a number).',
      'user-not-found' || 'wrong-password' || 'invalid-credential' =>
        'Email or password is incorrect.',
      'user-disabled' => 'This account has been disabled. Contact support.',
      'too-many-requests' => 'Too many attempts. Wait a moment and try again.',
      'network-request-failed' => 'Network error. Check your connection and try again.',
      'operation-not-allowed' =>
        'Email/password sign-in is disabled in Firebase. Enable Email/Password under Authentication → Sign-in method.',
      'internal-error' =>
        'Firebase Authentication is not set up for this project (CONFIGURATION_NOT_FOUND). In Firebase Console open Authentication → Get started, enable Email/Password, then retry. (${error.code})',
      _ => 'Authentication failed (${error.code}). '
          '${error.message?.isNotEmpty == true ? error.message! : 'Try again.'}',
    };
  }
}

AuthService createDefaultAuthService() {
  if (Firebase.apps.isNotEmpty) return FirebaseAuthService();
  // Android APK builds currently lack google-services.json — use Identity Toolkit REST.
  return FirebaseRestAuthService();
}
