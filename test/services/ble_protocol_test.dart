import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parcel_dropbox/services/ble_protocol.dart';

void main() {
  const qr = 'SPDBLE:AABBCCDDEEFF:00112233445566778899AABBCCDDEEFF';
  const challenge = '00112233445566778899aabbccddeeff';

  test(
      'setup QR selects one Dropbox and Wi-Fi credentials require its session key',
      () async {
    final code = BleSetupCode.parse(qr)!;
    expect(BleSetupCode.parse('SPDB-REG-482913'), isNull);
    expect(code.deviceId, 'AA:BB:CC:DD:EE:FF');
    expect(bleServiceId(code.deviceId), 'a9f40001-49af-44eb-b1ba-aabbccddeeff');

    const ssid = 'Lab 網路';
    const password = 'demo-password';
    final sealed = await encryptBleWifi(
        code: code, challenge: challenge, ssid: ssid, password: password);
    final network = utf8.encode(ssid);
    final box = SecretBox(
      bleUnhex(sealed['data']!, 1 + network.length + password.length),
      nonce: bleUnhex(sealed['iv']!, 12),
      mac: Mac(bleUnhex(sealed['tag']!, 16)),
    );
    final cipher = AesGcm.with256bits();
    final key = await bleMac(
        code.secret, 'SPD-BLE-WIFI-V1|AA:BB:CC:DD:EE:FF|$challenge');
    expect(await cipher.decrypt(box, secretKey: SecretKey(key)),
        [network.length, ...network, ...utf8.encode(password)]);
    final otherKey = await bleMac(
        code.secret, 'SPD-BLE-WIFI-V1|AA:BB:CC:DD:EE:FF|different');
    await expectLater(cipher.decrypt(box, secretKey: SecretKey(otherKey)),
        throwsA(isA<SecretBoxAuthenticationError>()));
  });

  test('maximum-size Wi-Fi setup fits the Bluetooth frame limit', () async {
    final command = await encryptBleWifi(
      code: BleSetupCode.parse(qr)!,
      challenge: challenge,
      ssid: 'S' * 32,
      password: 'P' * 63,
    );
    final payload =
        utf8.encode(jsonEncode({'op': 'wifi', 'rid': 2147483647, ...command}));
    final frames = bleFrames(payload);
    expect(frames.every((frame) => frame.length <= 20), isTrue);
    expect(frames.first.first, 0);
    expect(frames.last.first, 0x80 | (frames.length - 1));
    expect(frames.expand((frame) => frame.skip(1)), orderedEquals(payload));
  });
}
