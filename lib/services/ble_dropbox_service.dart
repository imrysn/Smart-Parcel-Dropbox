import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';
import 'ble_protocol.dart';

class BleDropboxException implements Exception {
  const BleDropboxException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BleDropboxService {
  BleDropboxService(this._auth);

  final AuthService _auth;
  final _storage = const FlutterSecureStorage();
  static const _storageKey = 'offline_unlock_grant';
  static const _permissions = MethodChannel('spd/ble_permissions');
  static final _writeId = Uuid.parse('a9f40002-49af-44eb-b1ba-000000000000');
  static final _readId = Uuid.parse('a9f40003-49af-44eb-b1ba-000000000000');
  int _sessionGeneration = 0;
  Future<void> _grantStorageWork = Future<void>.value();
  bool _active = false;

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> clearGrant() async {
    _sessionGeneration++;
    try {
      await _updateGrantStorage(() => _storage.delete(key: _storageKey));
    } on PlatformException {
      // Reads also require the matching signed-in account and server.
    }
  }

  Future<OfflineUnlockGrant?> readGrant() async {
    final generation = _sessionGeneration;
    final user = await _auth.currentUserId;
    if (user == null || !await _auth.isLoggedIn) return null;
    await _grantStorageWork;
    final saved = await _storage.read(key: _storageKey);
    if (saved == null || generation != _sessionGeneration) return null;
    try {
      final record = jsonDecode(saved) as Map<String, dynamic>;
      if (record['account'] != user ||
          record['server'] != ApiConfig.serverUrl) {
        return null;
      }
      return OfflineUnlockGrant.fromJson(
          record['grant'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<OfflineUnlockGrant> prepareGrant(String deviceId) async {
    final generation = _sessionGeneration;
    final user = await _auth.currentUserId;
    if (user == null) {
      throw const BleDropboxException('Sign in as the primary owner first.');
    }
    final url = Uri.parse(
        '${ApiConfig.dropbox}/${Uri.encodeComponent(deviceId)}/offline-unlock-grant');
    if (url.scheme != 'https') {
      throw const BleDropboxException(
          'Connect to the HTTPS server to prepare offline unlock.');
    }
    final response = await http
        .post(url, headers: await _auth.getAuthHeaders())
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      switch (response.statusCode) {
        case 403:
          throw const BleDropboxException(
              'Only the primary owner can prepare offline unlock.');
        case 409:
          throw const BleDropboxException(
              'Connect the Dropbox to the server with updated firmware first.');
        default:
          throw const BleDropboxException(
              'Could not prepare offline unlock. Check the server connection.');
      }
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final grant = OfflineUnlockGrant.fromJson(payload);
    if (grant.deviceId != deviceId.toUpperCase() ||
        generation != _sessionGeneration ||
        user != await _auth.currentUserId ||
        !await _auth.isLoggedIn) {
      throw const BleDropboxException(
          'The Dropbox or sign-in session changed. Try again.');
    }
    await _updateGrantStorage(() async {
      if (generation != _sessionGeneration) return;
      await _storage.write(
          key: _storageKey,
          value: jsonEncode({
            'account': user,
            'server': ApiConfig.serverUrl,
            'grant': payload,
          }));
    });
    if (generation != _sessionGeneration) {
      throw const BleDropboxException(
          'The sign-in session changed. Try again.');
    }
    return grant;
  }

  Future<void> _updateGrantStorage(Future<void> Function() update) {
    final operation = _grantStorageWork.then((_) => update());
    _grantStorageWork =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  Future<void> configureWifi(
      BleSetupCode code, String ssid, String password) async {
    await _withBox(code.deviceId, (send) async {
      final nonce =
          _challenge(await send({'op': 'hello'}, const Duration(seconds: 5)));
      final encrypted = await encryptBleWifi(
          code: code, challenge: nonce, ssid: ssid, password: password);
      final response =
          await send({'op': 'wifi', ...encrypted}, const Duration(seconds: 28));
      final status = response['status'];
      if (status is! String ||
          !await verifyBleMac(
              code.secret,
              'SPD-BLE-WIFI-RESULT-V1|${code.deviceId}|$nonce|$status',
              response['proof'])) {
        throw const BleDropboxException(
            'The Dropbox could not confirm setup. Scan its current setup QR.');
      }
      if (status != 'connected') {
        throw const BleDropboxException(
            'The Dropbox could not join or save that network. Check the Wi-Fi settings and retry.');
      }
    });
  }

  Future<void> unlockReceivedDoor(OfflineUnlockGrant grant) async {
    final generation = _sessionGeneration;
    final cached = await readGrant();
    if (cached?.grantId != grant.grantId ||
        !grant.expiry.isAfter(DateTime.now())) {
      throw const BleDropboxException(
          'Prepare a valid offline unlock grant while the box is online.');
    }
    await _withBox(grant.deviceId, (send) async {
      final nonce =
          _challenge(await send({'op': 'hello'}, const Duration(seconds: 5)));
      final proof =
          bleHex(await bleMac(grant.secret, 'SPD-BLE-OPEN-V1|$nonce'));
      if (generation != _sessionGeneration) {
        throw const BleDropboxException('The sign-in session changed.');
      }
      final response = await send({
        'op': 'unlock',
        'grant': grant.grantId,
        'expires': grant.expiresAt,
        'proof': proof,
      }, const Duration(seconds: 6));
      if (response['status'] != 'opened' ||
          !await verifyBleMac(grant.secret,
              'SPD-BLE-UNLOCK-RESULT-V1|$nonce|opened', response['proof'])) {
        throw const BleDropboxException(
            'The Dropbox did not confirm the unlock. Check the door before retrying.');
      }
    });
  }

  String _challenge(Map<String, dynamic> response) {
    final nonce = response['nonce'];
    if (nonce is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(nonce)) {
      throw const BleDropboxException(
          'Open the Bluetooth screen on the Dropbox and try again.');
    }
    return nonce;
  }

  Future<void> _withBox(
      String id, Future<void> Function(_BleRequest) operation) async {
    if (!supported) {
      throw const BleDropboxException(
          'Bluetooth setup and unlock require Android or iOS.');
    }
    if (_active) {
      throw const BleDropboxException(
          'Another Bluetooth request is in progress.');
    }
    _active = true;
    StreamSubscription<ConnectionStateUpdate>? subscription;
    try {
      if (defaultTargetPlatform == TargetPlatform.android &&
          await _permissions.invokeMethod<bool>('request') != true) {
        throw const BleDropboxException(
            'Allow nearby device access to connect to the Dropbox.');
      }
      final ble = FlutterReactiveBle();
      final status = await ble.statusStream
          .firstWhere((status) => status != BleStatus.unknown)
          .timeout(const Duration(seconds: 8));
      if (status != BleStatus.ready) {
        throw const BleDropboxException(
            'Turn on Bluetooth and allow the app to find nearby devices.');
      }
      final service = Uuid.parse(bleServiceId(id));
      final target = await ble
          .scanForDevices(
              withServices: [service], scanMode: ScanMode.lowLatency)
          .timeout(const Duration(seconds: 10))
          .first;
      final ready = Completer<void>();
      var connected = false;
      subscription = ble
          .connectToDevice(
              id: target.id, connectionTimeout: const Duration(seconds: 10))
          .listen(
        (update) {
          connected = update.connectionState == DeviceConnectionState.connected;
          if (connected && !ready.isCompleted) ready.complete();
          if (update.connectionState == DeviceConnectionState.disconnected &&
              !ready.isCompleted) {
            ready.completeError(
                const BleDropboxException('Could not connect to the Dropbox.'));
          }
        },
        onError: (Object error) {
          connected = false;
          if (!ready.isCompleted) ready.completeError(error);
        },
      );
      await ready.future.timeout(const Duration(seconds: 12));
      final tx = QualifiedCharacteristic(
          serviceId: service, characteristicId: _writeId, deviceId: target.id);
      final rx = QualifiedCharacteristic(
          serviceId: service, characteristicId: _readId, deviceId: target.id);
      await operation((command, timeout) async {
        final rid = Random.secure().nextInt(0x7fffffff) + 1;
        for (final frame
            in bleFrames(utf8.encode(jsonEncode({...command, 'rid': rid})))) {
          await ble
              .writeCharacteristicWithResponse(tx, value: frame)
              .timeout(const Duration(seconds: 4));
        }
        final elapsed = Stopwatch()..start();
        while (connected && elapsed.elapsed < timeout) {
          final bytes = await ble
              .readCharacteristic(rx)
              .timeout(const Duration(seconds: 3));
          final response = jsonDecode(utf8.decode(bytes));
          if (response is Map<String, dynamic> && response['rid'] == rid) {
            return response;
          }
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        throw const BleDropboxException(
            'No confirmation from the Dropbox. Check its screen before retrying.');
      });
    } on TimeoutException {
      throw const BleDropboxException(
          'The Bluetooth request timed out. Stay near the box and reopen its Bluetooth screen.');
    } on FormatException catch (error) {
      throw BleDropboxException(error.message);
    } on BleDropboxException {
      rethrow;
    } catch (_) {
      throw const BleDropboxException(
          'Bluetooth connection failed. Reopen the Bluetooth screen on the box and try again.');
    } finally {
      try {
        await subscription?.cancel();
      } finally {
        _active = false;
      }
    }
  }
}

typedef _BleRequest = Future<Map<String, dynamic>> Function(
    Map<String, dynamic>, Duration);
