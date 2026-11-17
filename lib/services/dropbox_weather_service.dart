import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

enum DropboxDaylight { day, dawn, dusk, night }

enum DropboxWeatherKind {
  clear('Clear'),
  clouds('Cloudy'),
  fog('Fog'),
  rain('Rain'),
  storm('Thunderstorms'),
  unknown('Conditions unavailable');

  const DropboxWeatherKind(this.label);
  final String label;

  static DropboxWeatherKind fromCode(int code) => switch (code) {
        0 || 1 => clear,
        2 || 3 => clouds,
        45 || 48 => fog,
        51 ||
        53 ||
        55 ||
        56 ||
        57 ||
        61 ||
        63 ||
        65 ||
        66 ||
        67 ||
        80 ||
        81 ||
        82 =>
          rain,
        95 || 96 || 97 || 99 => storm,
        _ => unknown,
      };
}

typedef _SunTimes = ({DateTime start, DateTime? sunrise, DateTime? sunset});

class DropboxWeather {
  DropboxWeather.fromJson(Map<String, dynamic> data)
      : _offset = Duration(seconds: data['utc_offset_seconds'] as int),
        _sunTimes = _readSunTimes(data['daily']) {
    final current = data['current'] as Map<String, dynamic>;
    observedAt = _utcTime(current['time'])!;
    temperature = (current['temperature_2m'] as num).toDouble();
    if (!temperature.isFinite) {
      throw const FormatException('Invalid temperature');
    }
    kind = DropboxWeatherKind.fromCode(current['weather_code'] as int);
    _wasDay = current['is_day'] == 1;
  }

  static const freshness = Duration(minutes: 40);
  static const _twilight = Duration(minutes: 18);
  final Duration _offset;
  final List<_SunTimes> _sunTimes;
  late final DateTime observedAt;
  late final double temperature;
  late final DropboxWeatherKind kind;
  late final bool _wasDay;

  bool isFreshAt(DateTime now) => now.difference(observedAt) <= freshness;

  DateTime locationTime(DateTime time) => time.toUtc().add(_offset);

  static DropboxDaylight fromClock(DateTime local) =>
      local.hour >= 6 && local.hour < 18
          ? DropboxDaylight.day
          : DropboxDaylight.night;

  DropboxDaylight daylightAt(DateTime now) {
    for (var index = 0; index < _sunTimes.length; index++) {
      final day = _sunTimes[index];
      final next = index + 1 < _sunTimes.length
          ? _sunTimes[index + 1].start
          : day.start.add(const Duration(days: 1));
      if (now.isBefore(day.start) || !now.isBefore(next)) continue;
      final sunrise = day.sunrise;
      final sunset = day.sunset;
      if (sunrise == null || sunset == null || !sunrise.isBefore(sunset)) {
        return _wasDay ? DropboxDaylight.day : DropboxDaylight.night;
      }
      if (now.difference(sunrise).abs() < _twilight) {
        return DropboxDaylight.dawn;
      }
      if (now.difference(sunset).abs() < _twilight) return DropboxDaylight.dusk;
      return now.isBefore(sunrise) || !now.isBefore(sunset)
          ? DropboxDaylight.night
          : DropboxDaylight.day;
    }
    return isFreshAt(now)
        ? (_wasDay ? DropboxDaylight.day : DropboxDaylight.night)
        : fromClock(locationTime(now));
  }

  static DateTime? _utcTime(Object? value) => value is int && value > 0
      ? DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true)
      : null;

  static List<_SunTimes> _readSunTimes(Object? data) {
    if (data is! Map<String, dynamic>) return [];
    final dates = data['time'];
    final rise = data['sunrise'];
    final set = data['sunset'];
    if (dates is! List ||
        rise is! List ||
        set is! List ||
        dates.length != rise.length ||
        dates.length != set.length) {
      return [];
    }
    return [
      for (var i = 0; i < dates.length; i++)
        if (_utcTime(dates[i]) case final DateTime start)
          (start: start, sunrise: _utcTime(rise[i]), sunset: _utcTime(set[i])),
    ];
  }
}

enum DropboxLocationProblem { disabled, denied, blocked }

class DropboxWeatherService {
  DropboxWeatherService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Future<DropboxWeather> localWeather({required bool requestPermission}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw DropboxLocationProblem.disabled;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw DropboxLocationProblem.blocked;
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw DropboxLocationProblem.denied;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return weatherAt(
        latitude: position.latitude, longitude: position.longitude);
  }

  Future<DropboxWeather> weatherAt({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toStringAsFixed(2),
      'longitude': longitude.toStringAsFixed(2),
      'current': 'temperature_2m,weather_code,is_day',
      'daily': 'sunrise,sunset',
      'timezone': 'auto',
      'timeformat': 'unixtime',
      'forecast_days': '3',
    });
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw http.ClientException('Weather currently unavailable', uri);
    }
    return DropboxWeather.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  void dispose() => _client.close();
}
