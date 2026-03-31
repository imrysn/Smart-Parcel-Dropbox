import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  /// Returns true only on platforms where biometrics are actually supported.
  bool get _isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Check if biometrics are available on the device.
  /// Always returns false on Windows/Desktop so callers can show a PIN/modal fallback.
  Future<bool> isBiometricAvailable() async {
    if (!_isSupportedPlatform) return false;
    try {
      final canCheck = await _auth.canCheckBiometrics;
      return canCheck || await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  /// Authenticate using biometrics (Android/iOS only).
  /// On Windows this always returns false — the caller must show a fallback UI.
  Future<bool> authenticate({required String reason}) async {
    if (!_isSupportedPlatform) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allow PIN/pattern as fallback on Android
        ),
      );
    } on PlatformException {
      return false;
    }
  }

  /// Get list of available biometric types.
  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (!_isSupportedPlatform) return [];
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }
}
