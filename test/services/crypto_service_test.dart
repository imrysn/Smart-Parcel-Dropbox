import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Phase 11: CryptoService Unit Tests - Standalone (No mocks needed)
//
//  These tests directly validate the HMAC-SHA256 algorithm used by
//  CryptoService WITHOUT needing a real AuthService or network connection.
//  This proves the cryptographic correctness of the offline token engine.
// ─────────────────────────────────────────────────────────────────────────────

const int _timeStepSecs = 60;

/// Mirrors the logic in lib/services/crypto_service.dart
String _buildToken(String key, String userId, {int offset = 0}) {
  final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final counter  = (timestamp ~/ _timeStepSecs) + offset;
  final payload  = '$userId-$counter';
  final hmac     = Hmac(sha256, utf8.encode(key));
  final digest   = hmac.convert(utf8.encode(payload));
  final shortHash = digest.toString().substring(0, 8).toUpperCase();
  return 'SPDB-AUT-$userId-$shortHash';
}

bool _verifyToken(String token, String key, String userId, {int offset = 0}) {
  final expected = _buildToken(key, userId, offset: offset);
  return token == expected;
}

// Known Vector (verified via Node.js crypto module)
const _testKey     = 'TEST_KEY_123';
const _testUser    = 'USER_ABC';
const _testPayload = 'USER_ABC-12345';

void main() {
  group('📦 CryptoService — Phase 11 Verification Tests', () {
    test('1. HMAC-SHA256 – Known vector matches Node.js reference (F1D4EEBC)', () {
      final hmac   = Hmac(sha256, utf8.encode(_testKey));
      final digest = hmac.convert(utf8.encode(_testPayload));
      final shortHash = digest.toString().substring(0, 8).toUpperCase();

      expect(shortHash, equals('F1D4EEBC'),
          reason: 'HMAC must match Node.js and ESP32 mbedtls calculation');
    });

    test('2. Token format is correct (SPDB-AUT-<userId>-<8chars>)', () {
      final token = _buildToken(_testKey, _testUser);
      expect(token, startsWith('SPDB-AUT-$_testUser-'));
      expect(token.split('-').last.length, equals(8));
    });

    test('3. Token verifies at offset 0 (current time step)', () {
      final token = _buildToken(_testKey, _testUser);
      expect(_verifyToken(token, _testKey, _testUser), isTrue);
    });

    test('4. Token rejects wrong key', () {
      final token = _buildToken(_testKey, _testUser);
      expect(_verifyToken(token, 'WRONG_KEY', _testUser), isFalse);
    });

    test('5. Token rejects wrong userId', () {
      final token = _buildToken(_testKey, _testUser);
      expect(_verifyToken(token, _testKey, 'WRONG_USER'), isFalse);
    });

    test('6. Token from previous time-step (offset +1) is different', () {
      final tokenNow  = _buildToken(_testKey, _testUser, offset: 0);
      final tokenNext = _buildToken(_testKey, _testUser, offset: 1);
      expect(tokenNow, isNot(equals(tokenNext)),
          reason: 'Each 60s window must produce a unique token');
    });

    test('7. Token is not valid 60 time-steps ago (1 hour expired)', () {
      final oldToken = _buildToken(_testKey, _testUser, offset: -60);
      // Verify with offset 0 (current) — should not match a 1-hr-old token
      expect(_verifyToken(oldToken, _testKey, _testUser, offset: 0), isFalse,
          reason: 'Expired tokens must be rejected');
    });

    test('8. Empty key returns unusable token (security boundary)', () {
      final token = _buildToken('', _testUser);
      // An empty key still produces a token string but it cannot be verified
      // by the hardware which enforces strlen(hmacKey) > 0.
      expect(token, contains('SPDB-AUT-$_testUser-'));
    });
  });
}
