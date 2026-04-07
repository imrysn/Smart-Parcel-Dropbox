import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'service_locator.dart';
import 'auth_service.dart';

/// Cryptographic Service for Secure Offline Authentication
///
/// Implements HMAC-SHA256 based Time-based One-Time Tokens (TOTP approach)
/// to allow high-security offline verification between Mobile App and Hardware.
class CryptoService {
  final _authService = getIt<AuthService>();
  
  // Rotating step in seconds (60s for better stability with network latency)
  static const int _timeStepSeconds = 60;

  /// Generates a secure, rotating authentication token.
  /// 
  /// This token combines the shared symmetric key and the current time-step
  /// to create a verifiable signature that changes every minute.
  Future<String?> generateRotatingToken() async {
    try {
      final keyString = await _authService.hmacKey;
      if (keyString == null) return null;

      final userId = await _authService.currentUserId;
      if (userId == null) return null;

      // 1. Calculate the current time step (RFC 6238 style)
      final int timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final int counter = timestamp ~/ _timeStepSeconds;

      // 2. Prepare the payload (userId + counter)
      final String payload = '$userId-$counter';
      
      // 3. Compute HMAC-SHA256
      final keyBytes = utf8.encode(keyString);
      final payloadBytes = utf8.encode(payload);
      
      final hmac = Hmac(sha256, keyBytes);
      final digest = hmac.convert(payloadBytes);

      // 4. Return the first 8 characters of the hash as a human-readable 
      // but secure suffix to the user ID.
      // Final Token Format: SPDB-AUT-<userId>-<shortHash>
      final shortHash = digest.toString().substring(0, 8).toUpperCase();
      
      return 'SPDB-AUT-$userId-$shortHash';
    } catch (e) {
      debugPrint('Error generating rotating token: $e');
      return null;
    }
  }

  /// Verification logic (for local testing / documentation)
  bool verifyToken(String token, String key, String userId, int offsetSteps) {
    try {
      final int timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000);
      final int counter = (timestamp ~/ _timeStepSeconds) + offsetSteps;
      
      final String payload = '$userId-$counter';
      final keyBytes = utf8.encode(key);
      final payloadBytes = utf8.encode(payload);
      
      final hmac = Hmac(sha256, keyBytes);
      final digest = hmac.convert(payloadBytes);
      final shortHash = digest.toString().substring(0, 8).toUpperCase();
      
      return token == 'SPDB-AUT-$userId-$shortHash';
    } catch (_) {
      return false;
    }
  }
}
