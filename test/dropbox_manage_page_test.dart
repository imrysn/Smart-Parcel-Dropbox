import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:smart_parcel_dropbox/config/user_theme.dart';
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

void main() {
  testWidgets(
    'Overhauled Manage page supports dynamic filters, telemetry, QR, and doors on mobile',
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
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
          theme: ThemeData.light(),
          home: const DropboxControlScreen(),
        ),
      );
      await tester.pumpAndSettle();

      socket.status.add({'deviceId': _deviceId, 'connected': true});
      socket.doors.add(_doorState());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();

      expect(find.text('Dropbox'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(of: find.text('Dropbox'), matching: find.byType(Row)).first,
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(find.text('Wi-Fi Setup'), findsOneWidget);
      expect(find.text('Sync Unit'), findsOneWidget);
      final wifiOpacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text('Wi-Fi Setup'),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(wifiOpacity.opacity, 1.0);
      expect(find.text('Front Porch Box'), findsOneWidget);
      expect(find.text('Connected · OfficeWiFi'), findsOneWidget);
      expect(find.text('Door Controls'), findsOneWidget);
      expect(find.text('Storage Bins'), findsOneWidget);
      expect(find.text('Quick Unlock QR'), findsOneWidget);

      // Expanding telemetry reveals live details.
      await tester.tap(find.text('Telemetry · Live'));
      await tester.pumpAndSettle();
      expect(find.text('Unit ID: test-dropbox'), findsOneWidget);

      // Filter pills dynamically isolate sections.
      await tester.tap(find.widgetWithText(InkWell, 'Doors').last);
      await tester.pumpAndSettle();
      expect(find.text('Door Controls'), findsOneWidget);
      expect(find.text('Storage Bins'), findsNothing);

      await tester.ensureVisible(find.text('Access'));
      await tester.tap(find.text('Access'));
      await tester.pumpAndSettle();
      expect(find.text('Quick Unlock QR'), findsOneWidget);
      expect(find.text('Household members'), findsOneWidget);
      expect(find.text('Door Controls'), findsNothing);

      // Generate QR badge inline.
      await tester.tap(find.text('Generate one-time QR'));
      await tester.pumpAndSettle();
      expect(find.text('Scan at Dropbox Camera'), findsOneWidget);

      // Return to Doors and unlock Drop-off Door.
      await tester.ensureVisible(find.text('All'));
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      final unlockButtons = find.text('Unlock');
      expect(unlockButtons, findsNWidgets(3));
      await tester.ensureVisible(unlockButtons.last);
      await tester.tap(unlockButtons.last);
      await tester.pumpAndSettle();

      expect(deviceControl.commands, [
        (door: kDoorReceived, unlock: true, device: _deviceId),
      ]);
      expect(find.text('Lock'), findsOneWidget);

      // Tapping Dropbox toggles back to 3D view and surfaces the live open-door badge on Manage.
      await tester.tap(find.text('Dropbox'));
      await tester.pumpAndSettle();
      expect(find.text('Manage'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(of: find.text('Manage'), matching: find.byType(Row)).first,
          matching: find.text('1 open'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Overhauled Manage page adapts without overflow on narrow phones in dark mode',
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final socket = _Socket();
      getIt.registerSingleton<AuthService>(_Auth());
      getIt.registerSingleton<DropboxService>(_DropboxService());
      getIt.registerSingleton<WebSocketService>(socket);
      getIt.registerSingleton<DeviceControlService>(_DeviceControl());
      addTearDown(getIt.reset);
      addTearDown(socket.status.close);
      addTearDown(socket.doors.close);
      addTearDown(socket.bins.close);

      await tester.pumpWidget(
        MaterialApp(
          theme: UserTheme.getTheme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.35),
            ),
            child: child!,
          ),
          home: const DropboxControlScreen(),
        ),
      );
      await tester.pumpAndSettle();

      socket.status.add({'deviceId': _deviceId, 'connected': true});
      socket.doors.add({..._doorState(), 'REED_RECEIVED': true});
      await tester.pumpAndSettle();

      // Dynamic Manage pill displays the ajar alert before entering Manage view without overflowing.
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.ancestor(of: find.text('Manage'), matching: find.byType(Row)).first,
          matching: find.text('Ajar'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.ancestor(of: find.text('Dropbox'), matching: find.byType(Row)).first,
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(find.text('Ajar'), findsOneWidget);
      expect(find.text('Unlock Door'), findsNWidgets(3));
    },
  );
}

