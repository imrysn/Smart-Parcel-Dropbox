import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parcel_dropbox/services/database_service.dart';
import 'package:smart_parcel_dropbox/services/device_control_service.dart';
import 'package:smart_parcel_dropbox/services/notification_service.dart';
import 'package:smart_parcel_dropbox/services/service_locator.dart';
import 'package:smart_parcel_dropbox/services/tracking_service.dart';
import 'package:smart_parcel_dropbox/services/websocket_service.dart';

class _Socket extends Fake implements WebSocketService {
  final updates = StreamController<void>.broadcast();
  final connectedUsers = <String>[];
  int disconnects = 0;

  @override
  Future<void> connect(String userId) async => connectedUsers.add(userId);
  @override
  void disconnect() => disconnects++;
  @override
  Stream<void> get trackingUpdates => updates.stream;
  @override
  Stream<bool> get connectionStatusStream => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get notificationUpdates => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get doorStateUpdates => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get trackingStatusChanges => const Stream.empty();
}

class _Tracking extends Fake implements TrackingService {
  final refreshedUsers = <String>[];
  int cleared = 0;

  @override
  Future<void> refreshTracking(String userId) async => refreshedUsers.add(userId);
  @override
  void clearSession() => cleared++;
}

class _Notifications extends Fake implements NotificationService {
  int cleared = 0;
  @override
  void clearSession() => cleared++;
}

class _DoorState extends Fake implements DeviceControlService {
  int cleared = 0;
  @override
  void clearSession() => cleared++;
  @override
  void updateDoorState(Map<String, dynamic> state) {}
}

void main() {
  test('logout clears cached state and only the next account receives updates', () async {
    final socket = _Socket();
    final tracking = _Tracking();
    final notifications = _Notifications();
    final door = _DoorState();
    getIt.registerSingleton<WebSocketService>(socket);
    getIt.registerSingleton<TrackingService>(tracking);
    getIt.registerSingleton<NotificationService>(notifications);
    getIt.registerSingleton<DeviceControlService>(door);
    final database = DatabaseService();
    addTearDown(() async {
      database.endSession();
      await socket.updates.close();
      await getIt.reset();
    });

    await database.initSocket('first-account');
    socket.updates.add(null);
    await Future<void>.delayed(Duration.zero);
    database.endSession();
    expect(database.sessionUserId, isNull);
    expect([tracking.cleared, notifications.cleared, door.cleared, socket.disconnects], [1, 1, 1, 1]);

    await database.initSocket('second-account');
    await database.initSocket('second-account');
    socket.updates.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(tracking.refreshedUsers, ['first-account', 'second-account']);
    expect(socket.connectedUsers, ['first-account', 'second-account', 'second-account']);
  });
}
