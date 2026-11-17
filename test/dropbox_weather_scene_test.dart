import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parcel_dropbox/widgets/dropbox_weather_scene.dart';

void main() {
  testWidgets('Windows keeps automatic lighting without a Dev mode badge',
      (tester) async {
    late Map<String, Object> environment;
    Future<void> showScene({required bool devMode}) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DropboxWeatherScene(
                simulationEnabled: devMode,
                builder: (_, scene, control, onBackgroundTap) {
                  environment = scene;
                  return control ?? const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

    await showScene(devMode: false);
    final automatic = environment;
    expect(automatic['daylight'], anyOf('day', 'night'));
    final badge = find.byWidgetPredicate((widget) => widget is TextButton);
    expect(badge, findsNothing);

    await showScene(devMode: true);
    expect(find.text('Weather'), findsOneWidget);

    await showScene(devMode: false);
    expect(environment, automatic);
    expect(badge, findsNothing);
  }, variant: const TargetPlatformVariant({TargetPlatform.windows}));

  testWidgets('phone location is requested only after opting in',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final methods = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    const channels = [
      MethodChannel('flutter.baseflow.com/geolocator'),
      MethodChannel('flutter.baseflow.com/geolocator_android'),
    ];
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        return call.method == 'isLocationServiceEnabled' ? true : 0;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: DropboxWeatherScene(
        builder: (_, __, control, ___) => control ?? const SizedBox.shrink(),
      ),
    )));
    await tester.pumpAndSettle();
    expect(methods, isEmpty);
    expect(find.text('Weather'), findsNothing);
    await tester.tap(find.text('Set weather'));
    await tester.pumpAndSettle();
    expect(methods, isEmpty);
    await tester.tap(find.text('Use phone location'));
    await tester.pumpAndSettle();
    expect(methods,
        ['isLocationServiceEnabled', 'checkPermission', 'requestPermission']);
    expect(find.text('Location needed'), findsOneWidget);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('Dev mode cycles daylight and weather directly, then resets',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    late Map<String, Object> environment;
    VoidCallback? backgroundTap;
    Future<void> showScene({required bool devMode}) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DropboxWeatherScene(
                simulationEnabled: devMode,
                builder: (_, scene, control, onBackgroundTap) {
                  environment = scene;
                  backgroundTap = onBackgroundTap;
                  return control ?? const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
    await showScene(devMode: true);
    final automatic = environment;

    const daylightCycle = ['dawn', 'day', 'dusk', 'night'];
    final start = daylightCycle.indexOf(automatic['daylight'] as String);
    for (var i = 1; i <= daylightCycle.length; i++) {
      backgroundTap!();
      await tester.pump();
      expect(environment['daylight'],
          daylightCycle[(start + i) % daylightCycle.length]);
    }

    backgroundTap!();
    await tester.pump();
    final selectedDaylight = environment['daylight'];
    var currentLabel = 'Weather';
    for (final (label, kind) in const [
      ('Clear', 'clear'),
      ('Cloudy', 'clouds'),
      ('Fog', 'fog'),
      ('Rain', 'rain'),
      ('Storm', 'storm'),
      ('Weather', 'unknown'),
    ]) {
      await tester.tap(find.text(currentLabel));
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(environment['weather'], kind);
      expect(environment['flood'], isFalse);
      expect(environment['daylight'], selectedDaylight);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      currentLabel = label;
      await tester.pump(const Duration(milliseconds: 800));
    }

    await tester.tap(find.text('Weather'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(environment, automatic);
    expect(find.text('Weather'), findsOneWidget);

    final weatherButton =
        find.byWidgetPredicate((widget) => widget is TextButton);
    final location = tester.getTopLeft(weatherButton) + const Offset(10, 16);
    Future<void> triggerFlood() async {
      for (var i = 1; i <= 5; i++) {
        await tester.tapAt(location);
        await tester.pump(i == 5 ? null : const Duration(milliseconds: 400));
        expect(environment['flood'], i == 5);
      }
      expect(find.text('Flood'), findsOneWidget);
      expect(environment['weather'], 'storm');
    }

    await triggerFlood();
    expect(tester.widget<TextButton>(weatherButton).enabled, isFalse);
    await tester.tapAt(location);
    final hold = await tester.startGesture(location);
    await tester.pump(const Duration(milliseconds: 700));
    await hold.up();
    await tester.pump(const Duration(milliseconds: 1299));
    expect(environment['flood'], isTrue);
    expect(tester.widget<TextButton>(weatherButton).enabled, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.widget<TextButton>(weatherButton).enabled, isTrue);
    await tester.tapAt(location);
    await tester.pumpAndSettle();
    expect(environment['flood'], isFalse);
    expect(find.text('Rain'), findsOneWidget);
    await tester.longPress(find.text('Rain'));
    await tester.pumpAndSettle();
    await triggerFlood();

    await showScene(devMode: false);
    expect(backgroundTap, isNull);
    expect(environment, automatic);
    expect(find.text('Set weather'), findsOneWidget);
    await showScene(devMode: true);
    expect(environment, automatic);
    expect(find.text('Weather'), findsOneWidget);
    expect(tester.widget<TextButton>(weatherButton).enabled, isTrue);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));
}
