import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:smart_parcel_dropbox/models/dropbox_model.dart';
import 'package:smart_parcel_dropbox/screens/dropbox_control_screen.dart';
import 'package:smart_parcel_dropbox/services/auth_service.dart';
import 'package:smart_parcel_dropbox/services/device_control_service.dart';
import 'package:smart_parcel_dropbox/services/dropbox_service.dart';
import 'package:smart_parcel_dropbox/services/service_locator.dart';
import 'package:smart_parcel_dropbox/services/websocket_service.dart';

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
  Future<Dropbox?> getUserDropbox(String userId) async => Dropbox(
        deviceId: _deviceId,
        userIds: const ['owner', 'partner'],
        primaryUserId: 'owner',
        name: 'Front Porch Box',
        isRegistered: true,
        status: 'online',
        wifiSSID: 'OfficeWiFi',
        pickupCount: 1,
        dropoffCount: 2,
        diagnostics: HardwareDiagnostics(
          firmwareVersion: '2.1.0',
          wifiRssi: -58,
          uptimeSeconds: 3720,
          reportedAt: DateTime.now(),
        ),
      );

  @override
  Stream<Map<String, dynamic>> get deviceRegisteredStream =>
      const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get deviceUnregisteredStream =>
      const Stream.empty();

  @override
  Future<Map<String, dynamic>?> getDeviceMembers(String deviceId) async => {
        'isPrimaryOwner': true,
        'members': [
          {'id': 'owner', 'fullName': 'Homeowner', 'isPrimaryOwner': true},
        ],
      };

  @override
  Future<Map<String, dynamic>> createHouseholdInvite({
    required String deviceId,
  }) async =>
      {'token': 'test-invite-token', 'pin': '123456'};
}

class _Socket extends Mock implements WebSocketService {
  final status = StreamController<Map<String, dynamic>>.broadcast();
  final doors = StreamController<Map<String, dynamic>>.broadcast();
  final bins = StreamController<Map<String, dynamic>>.broadcast();
  int statusRequests = 0;

  @override
  void requestEsp32Status() => statusRequests++;

  @override
  bool get isConnected => true;

  @override
  Stream<Map<String, dynamic>> get esp32StatusUpdates => status.stream;

  @override
  Stream<Map<String, dynamic>> get doorStateUpdates => doors.stream;

  @override
  Stream<Map<String, dynamic>> get binStatusUpdates => bins.stream;

  @override
  Stream<bool> get connectionStatusStream => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get trackingStatusChanges =>
      const Stream.empty();

  @override
  Future<Map<String, dynamic>> requestOwnerPass() async => {
        'token': 'owner-qr-demo-token',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      };
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

Future<void> _pumpUi(WidgetTester tester) async {
  // The native 3D viewer can remain on its loading indicator in widget tests.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<(_Socket, _DeviceControl)> _mountDropbox(
  WidgetTester tester, {
  required Size size,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

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

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness, useMaterial3: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: const DropboxControlScreen(),
    ),
  );
  await _pumpUi(tester);
  return (socket, deviceControl);
}

Future<void> _tapText(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await _pumpUi(tester);
}

void main() {
  const windows = TargetPlatformVariant({TargetPlatform.windows});

  testWidgets(
    'Household sheet and nested dialogs share styling and stay usable',
    variant: windows,
    (tester) async {
      await _mountDropbox(
        tester,
        size: const Size(320, 640),
        brightness: Brightness.dark,
        textScale: 1.6,
      );
      await _tapText(tester, 'Manage');
      await _tapText(tester, 'Access');
      await _tapText(tester, 'Household members');

      final sheet = find.byType(BottomSheet);
      expect(tester.widget<BottomSheet>(sheet).backgroundColor,
          const Color(0xFF201F1D));
      await _tapText(tester, 'Add by email');
      final dialog = find.byType(AlertDialog);
      expect(find.text('Add household member'), findsOneWidget);
      expect(Theme.of(tester.element(dialog)).dialogTheme.backgroundColor,
          const Color(0xFF201F1D));
      await _tapText(tester, 'Cancel');
      expect(dialog, findsNothing);
      expect(sheet, findsOneWidget);

      await _tapText(tester, 'Invite QR / PIN');
      expect(find.text('Household invite code'), findsOneWidget);
      expect(find.text('123456'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.byType(QrImageView)),
        findsOneWidget,
      );
      await _tapText(tester, 'Done');
      expect(dialog, findsNothing);
      expect(sheet, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Manage keeps sync, hardware details, filters, QR and remote door controls',
    variant: windows,
    (tester) async {
      final (socket, deviceControl) =
          await _mountDropbox(tester, size: const Size(390, 844));
      socket.status.add({'deviceId': _deviceId, 'connected': true});
      socket.doors.add(_doorState());
      await _pumpUi(tester);

      await _tapText(tester, 'Manage');

      final unitTitle = find.text('Front Porch Box');
      final summary = find.ancestor(of: unitTitle, matching: find.byType(Card));
      expect(summary, findsOneWidget);
      final summaryCard = tester.widget<Card>(summary);
      expect(summaryCard.color, const Color(0xFFFFFDFA));
      expect(
        (summaryCard.shape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(24),
      );
      expect(
        tester.getTopLeft(unitTitle).dx - tester.getTopLeft(summary).dx,
        20,
      );
      expect(find.text('Connected · OfficeWiFi'), findsOneWidget);
      expect(find.text('Door Controls'), findsOneWidget);
      expect(find.text('Storage Bins'), findsOneWidget);
      expect(find.text('Quick Unlock QR'), findsOneWidget);
      final wifiSetup = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Wi-Fi Setup'),
      );
      expect(wifiSetup.onPressed, isNotNull);

      final initialStatusRequests = socket.statusRequests;
      await _tapText(tester, 'Sync Unit');
      expect(socket.statusRequests, greaterThan(initialStatusRequests));

      await _tapText(tester, 'Hardware details');
      expect(find.text('Unit ID: test-dropbox'), findsOneWidget);
      expect(find.text('Firmware: 2.1.0'), findsOneWidget);
      await _tapText(tester, 'Hardware details');

      await _tapText(tester, 'Bins');
      expect(find.text('Door Controls'), findsNothing);
      expect(find.text('Pickup Bin'), findsOneWidget);
      expect(find.text('1 parcel'), findsOneWidget);
      expect(find.text('2 parcels'), findsOneWidget);

      await _tapText(tester, 'Access');
      expect(find.text('Household members'), findsOneWidget);
      expect(find.text('2 people paired'), findsOneWidget);
      expect(find.text('Storage Bins'), findsNothing);
      await _tapText(tester, 'Generate one-time QR');
      expect(find.text('Hold this QR code in front of the Dropbox scanner.'),
          findsOneWidget);
      expect(find.text('Generate new QR'), findsOneWidget);

      await _tapText(tester, 'Doors');
      expect(find.text('Quick Unlock QR'), findsNothing);
      final unlock = find.widgetWithText(OutlinedButton, 'Unlock');
      expect(unlock, findsNWidgets(3));
      await tester.ensureVisible(unlock.last);
      await tester.tap(unlock.last);
      await _pumpUi(tester);

      expect(deviceControl.commands, [
        (door: kDoorReceived, unlock: true, device: _deviceId),
      ]);
      expect(find.text('Unlocked'), findsOneWidget);
      expect(find.text('Lock'), findsOneWidget);

      await _tapText(tester, 'Back to 3D');
      expect(find.text('Manage'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Manage keeps door alerts readable and disables commands offline on narrow screens',
    variant: windows,
    (tester) async {
      final (socket, deviceControl) = await _mountDropbox(
        tester,
        size: const Size(320, 640),
        brightness: Brightness.dark,
        textScale: 1.6,
      );

      socket.status.add({'deviceId': _deviceId, 'connected': true});
      socket.doors.add({..._doorState(), 'REED_RECEIVED': true});
      await _pumpUi(tester);
      await _tapText(tester, 'Manage');
      expect(
        tester
            .widget<Card>(
              find.ancestor(
                of: find.text('Front Porch Box'),
                matching: find.byType(Card),
              ),
            )
            .color,
        const Color(0xFF201F1D),
      );
      await _tapText(tester, 'Doors');

      final alert = find.text('Locked · Door ajar');
      expect(alert, findsOneWidget);
      await tester.ensureVisible(alert);
      await _pumpUi(tester);
      expect(alert.hitTestable(), findsOneWidget);

      socket.status.add({'deviceId': _deviceId, 'connected': false});
      await _pumpUi(tester);
      expect(alert, findsNothing);
      expect(find.text('Offline · Check power or Wi-Fi'), findsOneWidget);

      final buttons = tester.widgetList<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Unlock'),
      );
      expect(buttons, hasLength(3));
      expect(buttons.every((button) => button.onPressed == null), isTrue);
      expect(deviceControl.commands, isEmpty);

      await _tapText(tester, 'Access');
      expect(find.text('Quick Unlock QR'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
