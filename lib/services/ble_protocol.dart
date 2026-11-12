import 'dart:convert';

import 'package:cryptography/cryptography.dart';

final _devicePattern = RegExp(r'^(?:[0-9A-F]{2}:){5}[0-9A-F]{2}$');
final _setupPattern = RegExp(r'^SPDBLE:([0-9A-F]{12}):([0-9A-F]{32})$');

class BleSetupCode {
  const BleSetupCode._(this.deviceId, this.secret);

  final String deviceId;
  final List<int> secret;

  static BleSetupCode? parse(String value) {
    final match = _setupPattern.firstMatch(value.trim().toUpperCase());
    if (match == null) return null;
    final mac = match[1]!;
    final deviceId = [
      for (var i = 0; i < mac.length; i += 2) mac.substring(i, i + 2)
    ].join(':');
    return BleSetupCode._(deviceId, bleUnhex(match[2]!, 16));
  }
}

class OfflineUnlockGrant {
  const OfflineUnlockGrant._(
      this.deviceId, this.grantId, this.expiresAt, this.secret);

  final String deviceId;
  final String grantId;
  final int expiresAt;
  final List<int> secret;

  DateTime get expiry => DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);

  factory OfflineUnlockGrant.fromJson(Map<String, dynamic> data) {
    final deviceId = data['deviceId'];
    final grantId = data['grantId'];
    final expiresAt = data['expiresAt'];
    final secret = data['secret'];
    if (deviceId is! String ||
        !_devicePattern.hasMatch(deviceId) ||
        grantId is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(grantId) ||
        expiresAt is! int ||
        expiresAt <= 0 ||
        expiresAt > 0xffffffff ||
        secret is! String) {
      throw const FormatException('Invalid offline unlock grant.');
    }
    return OfflineUnlockGrant._(
        deviceId, grantId, expiresAt, bleUnhex(secret, 32));
  }
}

String bleServiceId(String deviceId) {
  final normalized = deviceId.toUpperCase();
  if (!_devicePattern.hasMatch(normalized)) {
    throw const FormatException('Invalid Dropbox ID.');
  }
  return 'a9f40001-49af-44eb-b1ba-${normalized.replaceAll(':', '').toLowerCase()}';
}

String bleHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

List<int> bleUnhex(String value, int byteCount) {
  if (value.length != 2 * byteCount ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
    throw const FormatException('Invalid Bluetooth message.');
  }
  return [
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16)
  ];
}

Future<List<int>> bleMac(List<int> key, String message) async {
  final mac = await Hmac.sha256()
      .calculateMac(utf8.encode(message), secretKey: SecretKey(key));
  return mac.bytes;
}

Future<bool> verifyBleMac(List<int> key, String message, Object? proof) async {
  if (proof is! String) return false;
  final actual = Mac(bleUnhex(proof, 32));
  return actual == Mac(await bleMac(key, message));
}

Future<Map<String, String>> encryptBleWifi({
  required BleSetupCode code,
  required String challenge,
  required String ssid,
  required String password,
}) async {
  final network = utf8.encode(ssid);
  final pass = utf8.encode(password);
  if (network.isEmpty ||
      network.length > 32 ||
      network.contains(0) ||
      pass.length > 63 ||
      pass.contains(0) ||
      (pass.isNotEmpty && pass.length < 8)) {
    throw const FormatException(
        'Enter a Wi-Fi name up to 32 bytes and a password of 8–63 bytes, or leave it blank for an open network.');
  }
  final key =
      await bleMac(code.secret, 'SPD-BLE-WIFI-V1|${code.deviceId}|$challenge');
  final cipher = AesGcm.with256bits();
  final sealed = await cipher.encrypt([network.length, ...network, ...pass],
      secretKey: SecretKey(key));
  return {
    'iv': bleHex(sealed.nonce),
    'data': bleHex(sealed.cipherText),
    'tag': bleHex(sealed.mac.bytes)
  };
}

List<List<int>> bleFrames(List<int> payload) {
  if (payload.isEmpty || payload.length > 400) {
    throw const FormatException('Invalid Bluetooth message size.');
  }
  return [
    for (var offset = 0; offset < payload.length; offset += 19)
      [
        offset ~/ 19 | (offset + 19 >= payload.length ? 0x80 : 0),
        ...payload.skip(offset).take(19),
      ],
  ];
}
