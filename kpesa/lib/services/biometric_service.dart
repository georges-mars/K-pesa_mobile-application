import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Manages biometric authentication and device-email association.
class BiometricService {
  BiometricService._();

  static final _auth = LocalAuthentication();
  static const _storage = FlutterSecureStorage();

  static const _kBiometricEmail = 'kp_biometric_email';

  // ── Device biometric availability ─────────────────────────────────────────

  /// Returns `true` if the device has biometric hardware AND at least one
  /// biometric (fingerprint / face) enrolled in OS settings.
  static Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      if (!canCheck || !isDeviceSupported) return false;

      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  // ── Trigger biometric prompt ──────────────────────────────────────────────

  /// Shows the OS biometric prompt. Returns `true` if authentication succeeds.
  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Authenticate to sign in to K-Pesa',
        persistAcrossBackgrounding: true,
        biometricOnly: true,
      );
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    } catch (e) {
      return false;
    }
  }

  // ── Device ID ─────────────────────────────────────────────────────────────

  /// Returns a stable, platform-specific device identifier.
  ///  - Android: `androidId` (persists across app reinstalls on the same device)
  ///  - iOS:     `identifierForVendor` (resets on uninstall + reinstall)
  static Future<String> getDeviceId() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      return android.id; // hardware-based Android ID
    } else if (Platform.isIOS) {
      final ios = await info.iosInfo;
      return ios.identifierForVendor ?? '';
    }
    return '';
  }

  /// Returns a human-readable device name like "Pixel 7" or "iPhone 15".
  static Future<String> getDeviceName() async {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      return '${android.manufacturer} ${android.model}';
    } else if (Platform.isIOS) {
      final ios = await info.iosInfo;
      return ios.utsname.machine;
    }
    return 'Unknown';
  }

  // ── Enrolled email (local persistence) ────────────────────────────────────

  /// Read the email associated with this device for biometric login.
  static Future<String?> getBiometricEmail() =>
      _storage.read(key: _kBiometricEmail);

  /// Save the email that was enrolled for biometric login on this device.
  static Future<void> saveBiometricEmail(String email) =>
      _storage.write(key: _kBiometricEmail, value: email);

  /// Remove the locally stored biometric email (logout / disable).
  static Future<void> clearBiometricEmail() =>
      _storage.delete(key: _kBiometricEmail);
}
