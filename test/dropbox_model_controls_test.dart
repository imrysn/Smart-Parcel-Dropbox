import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:smart_parcel_dropbox/models/dropbox_model.dart';
import 'package:smart_parcel_dropbox/screens/dropbox_control_screen.dart';
import 'package:smart_parcel_dropbox/services/auth_service.dart';
import 'package:smart_parcel_dropbox/services/device_control_service.dart';
import 'package:smart_parcel_dropbox/services/dropbox_service.dart';
import 'package:smart_parcel_dropbox/services/service_locator.dart';
import 'package:smart_parcel_dropbox/services/websocket_service.dart';
import 'package:smart_parcel_dropbox/widgets/dropbox_model_view.dart';

const _deviceId = 'test-dropbox';

Map<String, dynamic> _doorState({bool receivedUnlocked = false}) => {
      'deviceId': _deviceId,
      'parcelDoorOpen': false,
      'pickupDoorOpen': false,
      'receivedDoorOpen': receivedUnlocked,
    };

class _Auth extends Mock implements AuthService {
  @override
  Future<String?> get currentUserId async => 'owner';
}

class _DropboxService extends Mock implements DropboxService {
  @override
  Future<Dropbox?> getUserDropbox(String userId) async => const Dropbox(
        deviceId: _deviceId,
        primaryUserId: 'owner',
        name: 'Test Dropbox',
        isRegistered: true,
        status: 'online',
      );

  @override
  Stream<Map<String, dynamic>> get deviceRegisteredStream =>
      const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get deviceUnregisteredStream =>
      const Stream.empty();
}

class _Socket extends Mock implements WebSocketService {
  final status = StreamController<Map<String, dynamic>>.broadcast();
  final doors = StreamController<Map<String, dynamic>>.broadcast();
  final bins = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get esp32StatusUpdates => status.stream;

  @override
  Stream<Map<String, dynamic>> get doorStateUpdates => doors.stream;

  @override
  Stream<Map<String, dynamic>> get binStatusUpdates => bins.stream;

  @override
  Stream<bool> get connectionStatusStream => const Stream.empty();
}

class _DeviceControl extends Mock implements DeviceControlService {
  final commands = <({String door, bool unlock, String? device})>[];

  @override
  Future<Map<String, dynamic>> setDoorLock({
    required String doorType,
    required bool unlock,
    String? deviceId,
  }) async {
    commands.add((door: doorType, unlock: unlock, device: deviceId));
    return _doorState(receivedUnlocked: unlock);
  }
}

void main() {
  testWidgets('One tap animates the rear door and reed reports reconcile it',
      variant: const TargetPlatformVariant({TargetPlatform.windows}),
      (tester) async {
    final socket = _Socket();
    final deviceControl = _DeviceControl();
    getIt.registerSingleton<AuthService>(_Auth());
    getIt.registerSingleton<DropboxService>(_DropboxService());
    getIt.registerSingleton<WebSocketService>(socket);
    getIt.registerSingleton<DeviceControlService>(deviceControl);
    addTearDown(getIt.reset);
    addTearDown(socket.status.close);
    addTearDown(socket.doors.close);
    addTearDown(socket.bins.close);

    await tester.pumpWidget(const MaterialApp(home: DropboxControlScreen()));
    await tester.pumpAndSettle();
    socket.status.add({'deviceId': _deviceId, 'connected': true});
    socket.doors.add(_doorState());
    await tester.pumpAndSettle();

    DropboxModelView model() =>
        tester.widget<DropboxModelView>(find.byType(DropboxModelView));
    model().onDoorSelected(kDoorReceived);
    await tester.pumpAndSettle();
    expect(deviceControl.commands, [
      (door: kDoorReceived, unlock: true, device: _deviceId),
    ]);
    expect(model().openDoors[kDoorReceived], isTrue);

    socket.doors
        .add({..._doorState(receivedUnlocked: true), 'REED_RECEIVED': true});
    await tester.pumpAndSettle();
    expect(model().openDoors[kDoorReceived], isTrue);
    socket.doors
        .add({..._doorState(receivedUnlocked: true), 'REED_RECEIVED': false});
    socket.bins.add({'deviceId': _deviceId, 'logicalDropoffCount': 2});
    await tester.pumpAndSettle();
    expect(model().openDoors[kDoorReceived], isFalse);
    expect(model().parcelCount, 2);

    model().onDoorSelected(kDoorReceived);
    await tester.pumpAndSettle();
    expect(deviceControl.commands.last,
        (door: kDoorReceived, unlock: false, device: _deviceId));
    expect(deviceControl.commands, hasLength(2));

    socket.doors.add({..._doorState(), 'REED_RECEIVED': true});
    await tester.pumpAndSettle();
    expect(model().openDoors[kDoorReceived], isTrue);
    socket.status.add({'deviceId': _deviceId, 'connected': false});
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(model().openDoors[kDoorReceived], isFalse);
    model().onDoorSelected(kDoorReceived);
    await tester.pumpAndSettle();
    expect(model().openDoors[kDoorReceived], isTrue);
    model().onDoorSelected(kDoorReceived);
    await tester.pumpAndSettle();
    expect(model().openDoors[kDoorReceived], isFalse);
    model().onDoorSelected(kDoorReceived);
    model().onDoorSelected(kDoorTop);
    await tester.pumpAndSettle();
    expect(model().openDoors[kDoorReceived], isTrue);
    expect(model().openDoors[kDoorTop], isTrue);

    socket.status.add({'deviceId': _deviceId, 'connected': false});
    await tester.pumpAndSettle();
    expect(model().openDoors[kDoorReceived], isTrue);
    expect(deviceControl.commands, hasLength(2));

    socket.status.add({'deviceId': _deviceId, 'connected': true});
    await tester.pumpAndSettle();
    expect(find.text('Online'), findsOneWidget);
    expect(model().openDoors.values, everyElement(isFalse));
    expect(deviceControl.commands, hasLength(2));

    socket.doors.add({..._doorState(), 'REED_RECEIVED': true});
    await tester.pumpAndSettle();
    expect(model().openDoors[kDoorReceived], isTrue);
    expect(deviceControl.commands, hasLength(2));
  });
}
