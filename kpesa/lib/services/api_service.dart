import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Central HTTP client for the K-Pesa backend API.
///
///
/// - Injects the JWT access token on every authenticated request.
/// - Automatically attempts a token refresh on 401, then retries once.
/// - Stores access + refresh tokens in FlutterSecureStorage.
class ApiService {
  // ── Base URL ─────────────────────────────────────────────────────────────────
  // Switch to your VPS URL before releasing to production.
  // For Android emulator local dev use: 'http://10.0.2.2:3000/api/v1'
  static const _baseUrl =
      'http://192.168.21.6:3000/api/v1'; //'https://api.k-pesa.tech/api/v1'

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── Token helpers ─────────────────────────────────────────────────────────────

  static Future<String?> getAccessToken() =>
      _storage.read(key: 'kp_access_token');
  static Future<String?> getRefreshToken() =>
      _storage.read(key: 'kp_refresh_token');

  static Future<void> saveTokens(String access, String refresh) async {
    await Future.wait([
      _storage.write(key: 'kp_access_token', value: access),
      _storage.write(key: 'kp_refresh_token', value: refresh),
    ]);
  }

  static Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: 'kp_access_token'),
      _storage.delete(key: 'kp_refresh_token'),
    ]);
  }

  static Future<bool> isLoggedIn() async => (await getAccessToken()) != null;

  // ── Internal HTTP helpers ─────────────────────────────────────────────────────

  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = await getAccessToken();
      if (token != null) h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  static Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  static const _timeout = Duration(seconds: 15);

  static http.Response _errorResponse(String message, [int statusCode = 503]) =>
      http.Response('{"error":"$message"}', statusCode);

  /// POST with automatic 401 → refresh → retry.
  static Future<http.Response> _post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    try {
      var res = await http
          .post(
            _uri(path),
            headers: await _headers(auth: auth),
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (auth && res.statusCode == 401) {
        final refreshed = await _tryRefresh();
        if (refreshed) {
          res = await http
              .post(
                _uri(path),
                headers: await _headers(auth: true),
                body: jsonEncode(body),
              )
              .timeout(_timeout);
        }
      }
      return res;
    } on TimeoutException {
      return _errorResponse('Request timed out. Please try again.');
    } catch (_) {
      return _errorResponse('Network error. Check your connection.');
    }
  }

  /// PATCH with automatic 401 → refresh → retry.
  static Future<http.Response> _patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      var res = await http
          .patch(_uri(path), headers: await _headers(), body: jsonEncode(body))
          .timeout(_timeout);
      if (res.statusCode == 401) {
        final refreshed = await _tryRefresh();
        if (refreshed) {
          res = await http
              .patch(
                _uri(path),
                headers: await _headers(),
                body: jsonEncode(body),
              )
              .timeout(_timeout);
        }
      }
      return res;
    } on TimeoutException {
      return _errorResponse('Request timed out. Please try again.');
    } catch (_) {
      return _errorResponse('Network error. Check your connection.');
    }
  }

  /// GET with automatic 401 → refresh → retry.
  static Future<http.Response> _get(String path) async {
    try {
      var res = await http
          .get(_uri(path), headers: await _headers())
          .timeout(_timeout);
      if (res.statusCode == 401) {
        final refreshed = await _tryRefresh();
        if (refreshed) {
          res = await http
              .get(_uri(path), headers: await _headers())
              .timeout(_timeout);
        }
      }
      return res;
    } on TimeoutException {
      return _errorResponse('Request timed out. Please try again.');
    } catch (_) {
      return _errorResponse('Network error. Check your connection.');
    }
  }

  static Future<bool> _tryRefresh() async {
    final rt = await getRefreshToken();
    if (rt == null) return false;
    try {
      final res = await http
          .post(
            _uri('/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': rt}),
          )
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        await saveTokens(data['accessToken'], data['refreshToken']);
        return true;
      }
    } catch (_) {}
    await clearTokens();
    return false;
  }

  // ── OTP ───────────────────────────────────────────────────────────────────────

  /// Returns true if the backend accepted the request (OTP dispatched).
  static Future<bool> sendOtp({
    required String destination,
    required String type, // 'sms' | 'email'
    required String purpose, // 'signup' | 'login' | 'password_reset'
  }) async {
    final res = await _post('/otp/send', {
      'destination': destination,
      'type': type,
      'purpose': purpose,
    }, auth: false);
    return res.statusCode == 200;
  }

  /// Returns the verificationToken on success, null on failure.
  static Future<({String? token, String? errorMsg})> verifyOtp({
    required String destination,
    required String otp,
    required String purpose,
  }) async {
    try {
      final res = await _post('/otp/verify', {
        'destination': destination,
        'otp': otp,
        'purpose': purpose,
      }, auth: false);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && body['valid'] == true) {
        return (token: body['verificationToken'] as String?, errorMsg: null);
      }
      return (
        token: null,
        errorMsg: body['error'] as String? ?? 'Verification failed.',
      );
    } catch (_) {
      return (
        token: null,
        errorMsg: 'Could not reach server. Check your connection.',
      );
    }
  }

  // ── Auth ──────────────────────────────────────────────────────────────────────

  /// Register a new user. Returns the error message on failure, null on success.
  static Future<String?> register({
    required String email,
    required String password,
    required String verificationToken,
    required String fullName,
    String? derivEmail,
    String? derivName,
    String? derivAccount,
    String? derivAccessToken,
    String? derivRefreshToken,
    String? derivTokenExpiresAt,
    String? binanceId,
    String? mpesaPhone,
    String? airtelPhone,
    String? bankName,
    String? bankAccountName,
    String? bankAccountNumber,
    String? affiliateCode,
  }) async {
    final res = await _post('/auth/register', {
      'email': email,
      'password': password,
      'verificationToken': verificationToken,
      'fullName': fullName,
      'derivEmail': ?derivEmail,
      'derivName': ?derivName,
      'derivAccount': ?derivAccount,
      'derivAccessToken': ?derivAccessToken,
      'derivRefreshToken': ?derivRefreshToken,
      'derivTokenExpiresAt': ?derivTokenExpiresAt,
      'binanceId': ?binanceId,
      'mpesaPhone': ?mpesaPhone,
      'airtelPhone': ?airtelPhone,
      'bankName': ?bankName,
      'bankAccountName': ?bankAccountName,
      'bankAccountNumber': ?bankAccountNumber,
      'affiliateCode': ?affiliateCode,
    }, auth: false);

    if (res.statusCode == 201) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      await saveTokens(data['accessToken'], data['refreshToken']);
      return null; // success
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['error'] as String? ?? 'Registration failed.';
  }

  /// Login. Returns error message on failure, null on success.
  static Future<String?> login(String email, String password) async {
    final res = await _post('/auth/login', {
      'email': email,
      'password': password,
    }, auth: false);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      await saveTokens(data['accessToken'], data['refreshToken']);
      return null; // success
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['error'] as String? ?? 'Login failed.';
  }

  static Future<void> logout() async {
    final rt = await getRefreshToken();
    if (rt != null) {
      await _post('/auth/logout', {
        'refreshToken': rt,
      }).catchError((_) => http.Response('', 200));
    }
    await clearTokens();
  }

  /// Initiate password reset. Returns null on success, error message on failure.
  static Future<String?> forgotPassword(String email) async {
    final res = await _post('/auth/forgot-password', {
      'email': email,
    }, auth: false);
    if (res.statusCode == 200) return null; // success
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['error'] as String? ?? 'Failed to send reset code.';
  }

  /// Complete password reset. Returns null on success, error message on failure.
  static Future<String?> resetPassword({
    required String verificationToken,
    required String newPassword,
  }) async {
    final res = await _post('/auth/reset-password', {
      'verificationToken': verificationToken,
      'newPassword': newPassword,
    }, auth: false);
    if (res.statusCode == 200) return null; // success
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['error'] as String? ?? 'Failed to reset password.';
  }

  // ── User ──────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getProfile() async {
    final res = await _get('/user/profile');
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    return null;
  }

  /// Save a display name for the user. Returns null on success, error message on failure.
  static Future<String?> updateDisplayName(String name) async {
    final res = await _patch('/user/profile', {'displayName': name});
    if (res.statusCode == 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['error'] as String? ?? 'Failed to save name.';
  }

  static Future<Map<String, dynamic>?> getBalances() async {
    final res = await _get('/user/balances');
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> getPaymentMethods() async {
    final res = await _get('/user/payment-methods');
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['paymentMethods'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Add a new payment method. Returns null on success, error message on failure.
  static Future<String?> addPaymentMethod({
    required String type,
    String? phoneNumber,
    String? bankName,
    String? accountName,
    String? accountNumber,
  }) async {
    final body = <String, dynamic>{'type': type};
    if (phoneNumber != null) body['phoneNumber'] = phoneNumber;
    if (bankName != null) body['bankName'] = bankName;
    if (accountName != null) body['accountName'] = accountName;
    if (accountNumber != null) body['accountNumber'] = accountNumber;
    final res = await _post('/user/payment-methods', body);
    if (res.statusCode == 201) return null;
    final resBody = jsonDecode(res.body) as Map<String, dynamic>;
    return resBody['error'] as String? ?? 'Failed to add payment method.';
  }

  /// Delete a payment method. Returns null on success, error message on failure.
  static Future<String?> deletePaymentMethod(String id) async {
    try {
      var res = await http
          .delete(_uri('/user/payment-methods/$id'), headers: await _headers())
          .timeout(_timeout);
      if (res.statusCode == 401) {
        final refreshed = await _tryRefresh();
        if (refreshed) {
          res = await http
              .delete(
                _uri('/user/payment-methods/$id'),
                headers: await _headers(),
              )
              .timeout(_timeout);
        }
      }
      if (res.statusCode == 204 || res.statusCode == 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['error'] as String? ?? 'Failed to delete payment method.';
    } on TimeoutException {
      return 'Request timed out.';
    } catch (_) {
      return 'Network error.';
    }
  }

  static Future<List<dynamic>> getTransactions({
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _get('/user/transactions?page=$page&limit=$limit');
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['transactions'] as List<dynamic>? ?? [];
    }
    return [];
  }

  // ── Deposit ───────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> initiateDeposit({
    required double amountKes,
    required String destinationType,
    required String mpesaPhone,
  }) async {
    final res = await _post('/deposit/initiate', {
      'amountKes': amountKes,
      'destinationType': destinationType,
      'mpesaPhone': mpesaPhone,
    });
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getDepositStatus(
    String transactionId,
  ) async {
    final res = await _get('/deposit/$transactionId/status');
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    return null;
  }

  // ── Deriv ─────────────────────────────────────────────────────────────────────

  /// Verify a Deriv OAuth token and return the account profile.
  /// Pass the token1 + acct1 values from the Deriv OAuth redirect URL.
  /// Returns { name, email, account, hasLiveAccount } or null on failure.
  static Future<Map<String, dynamic>?> connectDeriv({
    required String derivToken,
    String? derivAccount,
  }) async {
    final res = await _post('/deriv/connect', {
      'derivToken': derivToken,
      'derivAccount': ?derivAccount,
    }, auth: false);
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['profile'] as Map<String, dynamic>?;
    }
    return null;
  }

  // ── Withdrawal ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> initiateWithdrawal({
    required double amountUsd,
    required String sourceType,
    required String mpesaPhone,
  }) async {
    final res = await _post('/withdraw/initiate', {
      'amountUsd': amountUsd,
      'sourceType': sourceType,
      'mpesaPhone': mpesaPhone,
    });
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    return null;
  }

  // ── Biometric Device Login ─────────────────────────────────────────────────

  /// Enroll this device for biometric login. Requires an active JWT session.
  /// Returns null on success, error message on failure.
  static Future<String?> enrollBiometric({
    required String deviceId,
    String? deviceName,
  }) async {
    final res = await _post('/auth/biometric/enroll', {
      'deviceId': deviceId,
      'deviceName': deviceName,
    });
    if (res.statusCode == 201) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['error'] as String? ?? 'Failed to enroll device.';
  }

  /// Login using a previously enrolled device ID. No JWT needed.
  /// Returns null on success (tokens are saved), error message on failure.
  static Future<String?> biometricLogin(String deviceId) async {
    final res = await _post('/auth/biometric/login', {
      'deviceId': deviceId,
    }, auth: false);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      await saveTokens(data['accessToken'], data['refreshToken']);
      return null; // success
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['error'] as String? ?? 'Biometric login failed.';
  }

  /// Remove a device from biometric login. Requires an active JWT session.
  /// Returns null on success, error message on failure.
  static Future<String?> removeBiometric(String deviceId) async {
    try {
      var res = await http
          .delete(
            _uri('/auth/biometric/remove'),
            headers: await _headers(),
            body: jsonEncode({'deviceId': deviceId}),
          )
          .timeout(_timeout);
      if (res.statusCode == 401) {
        final refreshed = await _tryRefresh();
        if (refreshed) {
          res = await http
              .delete(
                _uri('/auth/biometric/remove'),
                headers: await _headers(),
                body: jsonEncode({'deviceId': deviceId}),
              )
              .timeout(_timeout);
        }
      }
      if (res.statusCode == 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['error'] as String? ?? 'Failed to remove device.';
    } on TimeoutException {
      return 'Request timed out.';
    } catch (_) {
      return 'Network error.';
    }
  }
}
