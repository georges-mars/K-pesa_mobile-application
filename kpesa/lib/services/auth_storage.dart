import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Stores and retrieves all Deriv OAuth tokens securely.
/// Uses Android Keystore on Android and Keychain on iOS.
///
/// Note: Deriv API tokens are LONG-LIVED and don't expire unless:
/// - User revokes app access in Deriv settings
/// - User changes their Deriv password
/// - Deriv invalidates for security reasons
class AuthStorage {
  const AuthStorage._();
  static const AuthStorage instance = AuthStorage._();

  static const _storage = FlutterSecureStorage();

  // ── Keys ──────────────────────────────────────────────────────────────────
  static const _kAccessToken = 'deriv_access_token';
  static const _kRefreshToken = 'deriv_refresh_token';
  static const _kIdToken = 'deriv_id_token';
  static const _kExpiresAt = 'deriv_expires_at';
  static const _kAccount = 'deriv_account';
  static const _kName = 'deriv_name';
  static const _kEmail = 'deriv_email';
  static const _kPkceVerifier = 'oauth_pkce_verifier';
  static const _kPkceState = 'oauth_pkce_state';

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> saveTokens({
    required String accessToken,
    required int expiresIn, // seconds from now
    String? refreshToken,
    String? idToken,
  }) async {
    final expiresAt = DateTime.now()
        .add(Duration(seconds: expiresIn))
        .toIso8601String();

    await Future.wait([
      _storage.write(key: _kAccessToken, value: accessToken),
      _storage.write(key: _kExpiresAt, value: expiresAt),
      if (refreshToken != null)
        _storage.write(key: _kRefreshToken, value: refreshToken),
      if (idToken != null) _storage.write(key: _kIdToken, value: idToken),
    ]);
  }

  Future<void> saveProfile({
    required String account,
    required String name,
    required String email,
  }) async {
    await Future.wait([
      _storage.write(key: _kAccount, value: account),
      _storage.write(key: _kName, value: name),
      _storage.write(key: _kEmail, value: email),
    ]);
  }

  Future<void> savePkceState({
    required String verifier,
    required String state,
  }) => Future.wait([
    _storage.write(key: _kPkceVerifier, value: verifier),
    _storage.write(key: _kPkceState, value: state),
  ]).then((_) {});

  Future<String?> get pkceVerifier => _storage.read(key: _kPkceVerifier);
  Future<String?> get pkceState => _storage.read(key: _kPkceState);

  Future<void> clearPkceState() => Future.wait([
    _storage.delete(key: _kPkceVerifier),
    _storage.delete(key: _kPkceState),
  ]).then((_) {});

  // ── Read ───────────────────────────────────────────────────────────────────

  Future<String?> get accessToken => _storage.read(key: _kAccessToken);
  Future<String?> get refreshToken => _storage.read(key: _kRefreshToken);
  Future<String?> get idToken => _storage.read(key: _kIdToken);
  Future<String?> get account => _storage.read(key: _kAccount);
  Future<String?> get name => _storage.read(key: _kName);
  Future<String?> get email => _storage.read(key: _kEmail);

  /// Check if we have a stored token (Deriv tokens are long-lived)
  Future<bool> get hasToken async {
    final token = await accessToken;
    return token != null && token.isNotEmpty;
  }

  /// Returns the stored access token.
  /// Deriv tokens are long-lived and don't need refreshing.
  Future<String?> getValidAccessToken() async {
    return accessToken;
  }

  /// Validates the stored token by checking with Deriv's WebSocket API.
  /// Returns authorization data if valid, null if invalid or error.
  /// Use this before making important API calls to ensure token is still valid.
  Future<Map<String, dynamic>?> validateToken() async {
    final token = await accessToken;
    if (token == null || token.isEmpty) {
      debugPrint('No token to validate');
      return null;
    }

    try {
      final channel = WebSocketChannel.connect(
        Uri.parse('wss://ws.binaryws.com/websockets/v3?app_id=130232'),
      );

      // Send authorize request
      channel.sink.add(jsonEncode({'authorize': token}));

      // Wait for response
      final response = await channel.stream.first.timeout(
        const Duration(seconds: 10),
        onTimeout: () => '{"error": {"message": "Connection timeout"}}',
      );

      await channel.sink.close();

      final data = jsonDecode(response as String) as Map<String, dynamic>;

      if (data.containsKey('authorize')) {
        debugPrint('Token is valid');
        return data['authorize'] as Map<String, dynamic>;
      } else if (data.containsKey('error')) {
        final error = data['error'] as Map<String, dynamic>;
        debugPrint('Token validation failed: ${error['message']}');
        return null;
      }

      return null;
    } catch (e) {
      debugPrint('Token validation error: $e');
      return null;
    }
  }

  // ── Clear ─────────────────────────────────────────────────────────────────

  Future<void> clearAll() => _storage.deleteAll();
}
