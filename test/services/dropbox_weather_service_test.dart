import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_parcel_dropbox/services/dropbox_weather_service.dart';

void main() {
  int epoch(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;
  final observed = DateTime.utc(2026, 11, 17, 2, 15);
  final localMidnight = DateTime.utc(2026, 11, 16, 16);
  final sunrise = DateTime.utc(2026, 11, 16, 22);
  final sunset = DateTime.utc(2026, 11, 17, 9, 30);

  Map<String, Object> payload(int code) => {
        'utc_offset_seconds': 28800,
        'current': {
          'time': epoch(observed),
          'weather_code': code,
          'temperature_2m': 28.7,
          'is_day': 1,
        },
        'daily': {
          'time': [epoch(localMidnight)],
          'sunrise': [epoch(sunrise)],
          'sunset': [epoch(sunset)],
        },
      };

  test(
      'uses local sunrise and sunset across UTC midnight and marks stale weather',
      () {
    final weather = DropboxWeather.fromJson(payload(63));
    expect(weather.kind, DropboxWeatherKind.rain);
    expect(weather.daylightAt(DateTime.utc(2026, 11, 16, 17)),
        DropboxDaylight.night);
    expect(weather.daylightAt(sunrise), DropboxDaylight.dawn);
    expect(weather.daylightAt(observed), DropboxDaylight.day);
    expect(weather.daylightAt(sunset), DropboxDaylight.dusk);
    expect(weather.daylightAt(sunset.add(const Duration(hours: 1))),
        DropboxDaylight.night);
    expect(
        weather.isFreshAt(observed.add(const Duration(minutes: 15))), isTrue);
    expect(weather.isFreshAt(observed.add(const Duration(hours: 1))), isFalse);
    expect(weather.locationTime(observed).hour, 10);
  });

  test('rounds phone coordinates and requests current weather and daylight',
      () async {
    final service = DropboxWeatherService(client: MockClient((request) async {
      expect(request.url.host, 'api.open-meteo.com');
      expect(request.url.queryParameters, containsPair('latitude', '14.60'));
      expect(request.url.queryParameters, containsPair('longitude', '120.98'));
      expect(request.url.queryParameters,
          containsPair('current', 'temperature_2m,weather_code,is_day'));
      expect(
          request.url.queryParameters, containsPair('daily', 'sunrise,sunset'));
      expect(request.url.queryParameters, containsPair('timezone', 'auto'));
      return http.Response(jsonEncode(payload(95)), 200);
    }));
    addTearDown(service.dispose);
    final weather =
        await service.weatherAt(latitude: 14.59951, longitude: 120.98422);
    expect(weather.kind, DropboxWeatherKind.storm);
    expect(weather.temperature, 28.7);
  });

  test('uses the device clock before location is available', () {
    expect(DropboxWeather.fromClock(DateTime(2026, 11, 17, 5, 59)),
        DropboxDaylight.night);
    expect(DropboxWeather.fromClock(DateTime(2026, 11, 17, 6)),
        DropboxDaylight.day);
    expect(DropboxWeather.fromClock(DateTime(2026, 11, 17, 18)),
        DropboxDaylight.night);
  });

  test('snow conditions keep temperature and daylight without a visual effect',
      () {
    final weather = DropboxWeather.fromJson(payload(73));
    expect(weather.kind, DropboxWeatherKind.unknown);
    expect(weather.temperature, 28.7);
    expect(weather.daylightAt(observed), DropboxDaylight.day);
  });
}
