import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:smart_parcel_dropbox/models/dropbox_model.dart';
import 'package:smart_parcel_dropbox/models/tracking_model.dart';
import 'package:smart_parcel_dropbox/screens/dropbox_control_screen.dart';
import 'package:smart_parcel_dropbox/screens/home_screen.dart';
import 'package:smart_parcel_dropbox/services/auth_service.dart';
import 'package:smart_parcel_dropbox/services/database_service.dart';
import 'package:smart_parcel_dropbox/services/device_control_service.dart';
import 'package:smart_parcel_dropbox/services/dropbox_service.dart';
import 'package:smart_parcel_dropbox/services/notification_service.dart';
import 'package:smart_parcel_dropbox/services/service_locator.dart';
import 'package:smart_parcel_dropbox/services/tracking_service.dart';
import 'package:smart_parcel_dropbox/services/user_service.dart';
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
  final tracking = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get esp32StatusUpdates => status.stream;

  @override
  Stream<Map<String, dynamic>> get doorStateUpdates => doors.stream;

  @override
  Stream<Map<String, dynamic>> get binStatusUpdates => bins.stream;

  @override
  Stream<bool> get connectionStatusStream => const Stream.empty();

  @override
  bool get isConnected => false;

  @override
  Future<void> connect(String userId) async {}

  @override
  Stream<void> get trackingUpdates => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get notificationUpdates => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get trackingStatusChanges => tracking.stream;

  @override
  Stream<Map<String, dynamic>> get deviceRegisteredStream =>
      const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get deviceUnregisteredStream =>
      const Stream.empty();
}

class _UserService extends Mock implements UserService {
  @override
  Future<Map<String, dynamic>?> getUserData(String userId) async => null;
}

class _TrackingService extends Mock implements TrackingService {
  @override
  List<TrackingModel> get cachedTracking => const [];

  @override
  Stream<List<TrackingModel>> getUserTrackingIds(String userId) =>
      const Stream.empty();
}

class _NotificationService extends Mock implements NotificationService {
  @override
  Stream<int> getUnreadNotificationsCount(String userId) =>
      const Stream.empty();
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
  testWidgets('Profile saves Dev mode and controls the mobile simulator',
      variant: const TargetPlatformVariant({TargetPlatform.android}),
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({'user_id': 'owner'});
    final socket = _Socket();
    final deviceControl = _DeviceControl();
    getIt.registerSingleton<AuthService>(_Auth());
    getIt.registerSingleton<DropboxService>(_DropboxService());
    getIt.registerSingleton<WebSocketService>(socket);
    getIt.registerSingleton<DeviceControlService>(deviceControl);
    getIt.registerSingleton<UserService>(_UserService());
    getIt.registerSingleton<TrackingService>(_TrackingService());
    getIt.registerSingleton<NotificationService>(_NotificationService());
    addTearDown(() async {
      DatabaseService().endSession();
      await socket.status.close();
      await socket.doors.close();
      await socket.bins.close();
      await socket.tracking.close();
      await getIt.reset();
    });

    Future<void> openTab(String tab) async {
      await tester.tap(find.byTooltip(tab));
      await tester.pumpAndSettle();
    }

    final devMode = find.widgetWithText(SwitchListTile, 'Dev mode');
    Future<void> toggleDevMode({required bool from}) async {
      expect(tester.widget<SwitchListTile>(devMode).value, from);
      await tester.ensureVisible(devMode);
      await tester.pumpAndSettle();
      await tester.tap(devMode);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(devMode).value, !from);
    }

    const home = MaterialApp(home: HomeScreen());
    await tester.pumpWidget(home);
    await tester.pumpAndSettle();
    await openTab('Dropbox');
    expect(find.text('Set weather'), findsOneWidget);
    expect(find.text('Weather'), findsNothing);

    await openTab('Profile');
    await toggleDevMode(from: false);
    await openTab('Dropbox');
    Finder button(String label) => find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((widget) => widget is TextButton),
        );
    final weather = button('Weather');
    final manage = button('Manage');
    final manageBounds = tester.getRect(manage);
    final weatherBounds = tester.getRect(weather);
    expect(weatherBounds.top - manageBounds.bottom, closeTo(8, 1));
    expect(weatherBounds.right, closeTo(manageBounds.right, 1));
    expect(find.text('Simulate'), findsNothing);
    expect(find.text('Front'), findsNothing);
    expect(find.text('Rear'), findsNothing);

    double textContrast(Color foreground, Color background) =>
        (background.computeLuminance() + 0.05) /
        (foreground.computeLuminance() + 0.05);

    final offlineDot = find.descendant(
      of: find.byType(AppBar),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Dropbox offline',
      ),
    );
    expect(offlineDot, findsOneWidget);
    expect(find.text('Offline'), findsNothing);

    final navigation = tester
        .widget<Scaffold>(find.byType(Scaffold).first)
        .bottomNavigationBar!;
    final navigationDecoration = tester
        .widget<Container>(find.descendant(
          of: find.byWidget(navigation),
          matching: find.byWidgetPredicate(
            (widget) => widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).boxShadow != null,
          ),
        ))
        .decoration as BoxDecoration;
    final navigationFill = navigationDecoration.color!;
    expect(navigationFill.a, lessThan(1));
    for (final control in [manage, weather]) {
      final style = tester.widget<TextButton>(control).style!;
      final fill = style.backgroundColor!.resolve({})!;
      expect(fill.a, navigationFill.a);
      expect(
          textContrast(style.foregroundColor!.resolve({})!,
              Color.alphaBlend(fill, Colors.black)),
          greaterThanOrEqualTo(4.5));
    }

    final navigationIcon = tester.widget<IconButton>(find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Dropbox',
    ));
    expect(
        textContrast(navigationIcon.color!,
            Color.alphaBlend(navigationFill, Colors.black)),
        greaterThanOrEqualTo(4.5));

    await tester.tap(weather);
    await tester.pumpAndSettle();
    expect(find.text('Clear'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);

    socket.status.add({'deviceId': _deviceId, 'connected': true});
    await tester.pumpAndSettle();
    expect(find.text('Dropbox Control', skipOffstage: false), findsNothing);
    expect(tester.getRect(button('Manage')), manageBounds);
    expect(offlineDot, findsNothing);
    expect(find.text('Online'), findsNothing);
    socket.bins.add({'deviceId': _deviceId, 'logicalDropoffCount': 2});
    await tester.pumpAndSettle();
    expect(find.text('2 parcels waiting'), findsOneWidget);

    socket.status.add({'deviceId': 'another-box', 'connected': false});
    await tester.pumpAndSettle();
    expect(offlineDot, findsNothing);
    socket.status.add({'deviceId': _deviceId, 'connected': false});
    await tester.pumpAndSettle();
    expect(offlineDot, findsOneWidget);
    await openTab('Profile');
    expect(offlineDot, findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(home);
    await tester.pumpAndSettle();
    await openTab('Profile');
    await toggleDevMode(from: true);
    await openTab('Dropbox');
    expect(find.text('Set weather'), findsOneWidget);
    expect(find.text('Weather'), findsNothing);
    await tester.tap(find.text('Set weather'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    socket.status.add({'deviceId': _deviceId, 'connected': true});
    await tester.pumpAndSettle();
    expect(find.text('Dropbox Control', skipOffstage: false), findsNothing);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(deviceControl.commands, isEmpty);
  });

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
    addTearDown(socket.tracking.close);

    await tester.pumpWidget(const MaterialApp(home: DropboxControlScreen()));
    await tester.pumpAndSettle();
    socket.status.add({'deviceId': _deviceId, 'connected': true});
    socket.doors.add(_doorState());
    await tester.pumpAndSettle();

    DropboxModelView model() =>
        tester.widget<DropboxModelView>(find.byType(DropboxModelView));
    expect(model().hardwareOnline, isTrue);
    expect(model().anyDoorUnlocked, isFalse);
    model().onDoorSelected(kDoorReceived);
    await tester.pumpAndSettle();
    expect(deviceControl.commands, [
      (door: kDoorReceived, unlock: true, device: _deviceId),
    ]);
    expect(model().openDoors[kDoorReceived], isTrue);
    expect(model().anyDoorUnlocked, isTrue);

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
    expect(model().latestDelivery, isNull);

    socket.tracking.add({
      'deviceId': 'another-box',
      'mode': 'drop_off',
      'status': 'delivered',
    });
    await tester.pumpAndSettle();
    expect(model().latestDelivery, isNull);
    socket.tracking.add({
      'deviceId': _deviceId,
      'mode': 'drop_off',
      'status': 'delivered',
    });
    await tester.pumpAndSettle();
    expect(model().latestDelivery, isNotNull);

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
    expect(find.text('Offline'), findsNothing);
    expect(model().hardwareOnline, isFalse);
    expect(model().anyDoorUnlocked, isNull);
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
    expect(model().hardwareOnline, isTrue);
    expect(model().openDoors.values, everyElement(isFalse));
    expect(deviceControl.commands, hasLength(2));

    socket.doors.add({..._doorState(), 'REED_RECEIVED': true});
    await tester.pumpAndSettle();
    expect(model().openDoors[kDoorReceived], isTrue);
    expect(deviceControl.commands, hasLength(2));
  });
}
