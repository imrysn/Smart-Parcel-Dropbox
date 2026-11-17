import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:geolocator/geolocator.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../config/user_theme.dart';
import '../services/dropbox_weather_service.dart';
import '../services/secure_storage_service.dart';

typedef DropboxSceneBuilder = Widget Function(
  BuildContext context,
  Map<String, Object> environment,
  Widget? weatherControl,
  VoidCallback? onBackgroundTap,
);

class DropboxWeatherScene extends StatefulWidget {
  const DropboxWeatherScene({
    super.key,
    required this.builder,
    this.simulationEnabled = false,
  });

  final DropboxSceneBuilder builder;
  final bool simulationEnabled;

  @override
  State<DropboxWeatherScene> createState() => _DropboxWeatherSceneState();
}

enum _WeatherAction { enable, refresh, disable, appSettings, locationSettings }

class _DropboxWeatherSceneState extends State<DropboxWeatherScene>
    with WidgetsBindingObserver {
  static const _preference = 'dropbox_phone_weather';
  static const _refreshInterval = Duration(minutes: 15);
  static const _retryInterval = Duration(minutes: 5);
  static const _floodTapWindow = Duration(seconds: 3);
  static const _floodButtonCooldown = Duration(seconds: 2);

  final _storage = SecureStorageService();
  DropboxWeatherService? _service;
  DropboxWeather? _weather;
  DropboxLocationProblem? _locationProblem;
  DateTime? _refreshAfter;
  Timer? _clock;
  bool _enabled = false;
  bool _loading = false;
  bool _weatherUnavailable = false;
  int _generation = 0;
  DropboxDaylight? _simulatedDaylight;
  DropboxWeatherKind? _simulatedWeather;
  Timer? _weatherTapTimer;
  Timer? _floodButtonLock;
  int _weatherTapCount = 0;
  bool _floodActive = false;

  bool get _simulationActive =>
      widget.simulationEnabled &&
      (_simulatedDaylight != null || _simulatedWeather != null || _floodActive);

  bool get _supportsWeather =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
    if (_supportsWeather) unawaited(_restorePreference());
  }

  @override
  void didUpdateWidget(DropboxWeatherScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.simulationEnabled && !widget.simulationEnabled) {
      _simulatedDaylight = null;
      _simulatedWeather = null;
      _floodActive = false;
      _clearWeatherTapSequence();
      _floodButtonLock?.cancel();
      _floodButtonLock = null;
    }
  }

  Future<void> _restorePreference() async {
    final saved = await _storage.getPreference(_preference);
    if (!mounted || _generation != 0 || saved != 'true') return;
    setState(() => _enabled = true);
    unawaited(_refresh());
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      setState(() {});
      unawaited(_refreshIfDue());
    });
  }

  Future<void> _refreshIfDue() async {
    final after = _refreshAfter;
    if (_locationProblem != null ||
        (after != null && DateTime.now().isBefore(after))) {
      return;
    }
    await _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startClock();
      setState(() {});
      if (_locationProblem != null) {
        unawaited(_refresh());
      } else {
        unawaited(_refreshIfDue());
      }
    } else {
      _clock?.cancel();
      _clearWeatherTapSequence();
    }
  }

  Future<void> _refresh({bool requestPermission = false}) async {
    if (!_enabled || _loading) return;
    final service = _service ??= DropboxWeatherService();
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final weather =
          await service.localWeather(requestPermission: requestPermission);
      if (!mounted || generation != _generation) return;
      setState(() {
        _weather = weather;
        _locationProblem = null;
        _weatherUnavailable = false;
        _refreshAfter = DateTime.now().add(_refreshInterval);
      });
    } on DropboxLocationProblem catch (problem) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _locationProblem = problem;
        _weather = null;
        _weatherUnavailable = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _locationProblem = null;
        _weatherUnavailable = true;
        _refreshAfter = DateTime.now().add(_retryInterval);
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _clearWeatherTapSequence();
    _floodButtonLock?.cancel();
    _service?.dispose();
    super.dispose();
  }

  Future<void> _showWeather() async {
    final weather = _weather;
    final problem = _locationProblem;
    final action = await showModalBottomSheet<_WeatherAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return PointerInterceptor(
          intercepting: defaultTargetPlatform == TargetPlatform.iOS,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Local weather', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(switch (problem) {
                    DropboxLocationProblem.disabled =>
                      'Turn on location services to get local weather.',
                    DropboxLocationProblem.denied =>
                      'Allow location access to get local weather.',
                    DropboxLocationProblem.blocked =>
                      'Allow location access in your phone settings.',
                    null when _weatherUnavailable =>
                      'Weather is temporarily unavailable. Try again when you have internet.',
                    _ =>
                      'Approximate location is sent to Open-Meteo while the Dropbox tab is open.',
                  }),
                  if (weather != null) ...[
                    const SizedBox(height: 12),
                    Text(
                        '${weather.temperature.round()} °C · ${weather.kind.label}'),
                    Text(
                        'Conditions as of ${TimeOfDay.fromDateTime(weather.locationTime(weather.observedAt)).format(context)} local time'),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.pop(
                            context,
                            switch (problem) {
                              DropboxLocationProblem.disabled =>
                                _WeatherAction.locationSettings,
                              DropboxLocationProblem.blocked =>
                                _WeatherAction.appSettings,
                              DropboxLocationProblem.denied =>
                                _WeatherAction.enable,
                              _ => _enabled
                                  ? _WeatherAction.refresh
                                  : _WeatherAction.enable,
                            }),
                    child: Text(switch (problem) {
                      DropboxLocationProblem.disabled => 'Location settings',
                      DropboxLocationProblem.blocked => 'App settings',
                      DropboxLocationProblem.denied => 'Allow phone location',
                      _ => _enabled ? 'Refresh weather' : 'Use phone location',
                    }),
                  ),
                  if (_enabled)
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(context, _WeatherAction.disable),
                      child: const Text('Turn off local weather'),
                    ),
                  SelectableText(
                    'Weather data by Open-Meteo (CC BY 4.0)\nhttps://open-meteo.com/en/licence',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    switch (action) {
      case _WeatherAction.enable:
        _generation++;
        setState(() => _enabled = true);
        unawaited(_storage.savePreference(_preference, 'true'));
        await _refresh(requestPermission: true);
      case _WeatherAction.refresh:
        await _refresh();
      case _WeatherAction.disable:
        _generation++;
        _service?.dispose();
        _service = null;
        setState(() {
          _enabled = _loading = _weatherUnavailable = false;
          _weather = null;
          _locationProblem = null;
          _refreshAfter = null;
        });
        await _storage.savePreference(_preference, 'false');
      case _WeatherAction.appSettings:
        await Geolocator.openAppSettings();
      case _WeatherAction.locationSettings:
        await Geolocator.openLocationSettings();
      case null:
        break;
    }
  }

  DropboxDaylight _automaticDaylight(DateTime now) =>
      _weather?.daylightAt(now) ?? DropboxWeather.fromClock(now);

  void _cycleDaylight() {
    if (!widget.simulationEnabled) return;
    _clearWeatherTapSequence();
    final current = _simulatedDaylight ?? _automaticDaylight(DateTime.now());
    setState(() {
      _simulatedDaylight = switch (current) {
        DropboxDaylight.dawn => DropboxDaylight.day,
        DropboxDaylight.day => DropboxDaylight.dusk,
        DropboxDaylight.dusk => DropboxDaylight.night,
        DropboxDaylight.night => DropboxDaylight.dawn,
      };
    });
  }

  ButtonStyle _controlStyle(ColorScheme colors) {
    final surface = colors.surface.withValues(
      alpha: UserTheme.floatingSurfaceOpacity,
    );
    return TextButton.styleFrom(
      foregroundColor: colors.onSurface,
      backgroundColor: surface,
      disabledForegroundColor: colors.onSurface.withValues(alpha: 0.7),
      disabledBackgroundColor: surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  void _clearWeatherTapSequence() {
    _weatherTapTimer?.cancel();
    _weatherTapTimer = null;
    _weatherTapCount = 0;
  }

  void _cycleWeather() {
    if (!widget.simulationEnabled || _floodButtonLock != null) return;
    if (_floodActive) {
      setState(() => _floodActive = false);
      return;
    }
    _weatherTapTimer ??= Timer(_floodTapWindow, _clearWeatherTapSequence);
    if (++_weatherTapCount == 5) {
      _clearWeatherTapSequence();
      setState(() {
        _floodActive = true;
        _floodButtonLock = Timer(_floodButtonCooldown, () {
          setState(() => _floodButtonLock = null);
        });
      });
      return;
    }
    setState(() {
      _simulatedWeather = switch (_simulatedWeather) {
        null || DropboxWeatherKind.unknown => DropboxWeatherKind.clear,
        DropboxWeatherKind.clear => DropboxWeatherKind.clouds,
        DropboxWeatherKind.clouds => DropboxWeatherKind.fog,
        DropboxWeatherKind.fog => DropboxWeatherKind.rain,
        DropboxWeatherKind.rain => DropboxWeatherKind.storm,
        DropboxWeatherKind.storm => null,
      };
    });
  }

  void _resetSimulation() {
    if (_floodButtonLock != null) return;
    _clearWeatherTapSequence();
    setState(() {
      _simulatedDaylight = null;
      _simulatedWeather = null;
      _floodActive = false;
    });
  }

  Widget _buildWeatherToggle(ColorScheme colors, IconData icon) => Tooltip(
        message: 'Change weather. Hold to reset to automatic.',
        triggerMode: TooltipTriggerMode.manual,
        child: Semantics(
          value: !_floodActive && _simulatedWeather == null
              ? 'Automatic weather'
              : null,
          customSemanticsActions: {
            const CustomSemanticsAction(label: 'Change time of day'):
                _cycleDaylight,
            if (_simulationActive && _floodButtonLock == null)
              const CustomSemanticsAction(label: 'Reset to automatic'):
                  _resetSimulation,
          },
          child: SizedBox(
            width: 110,
            child: TextButton.icon(
              onPressed: _floodButtonLock == null ? _cycleWeather : null,
              onLongPress: _simulationActive && _floodButtonLock == null
                  ? _resetSimulation
                  : null,
              style: _controlStyle(colors),
              icon: Icon(_floodActive ? Icons.waves : icon, size: 17),
              label: Text(
                _floodActive
                    ? 'Flood'
                    : _simulatedWeather == DropboxWeatherKind.storm
                        ? 'Storm'
                        : _simulatedWeather?.label ?? 'Weather',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final canSimulate = widget.simulationEnabled;
    final flood = canSimulate && _floodActive;
    final daylight =
        (canSimulate ? _simulatedDaylight : null) ?? _automaticDaylight(now);
    final active = _weather?.isFreshAt(now) == true ? _weather : null;
    final kind = flood
        ? DropboxWeatherKind.storm
        : (canSimulate ? _simulatedWeather : null) ??
            active?.kind ??
            DropboxWeatherKind.unknown;
    final environment = <String, Object>{
      'daylight': daylight.name,
      'weather': kind.name,
      'flood': flood,
      'motion': !MediaQuery.disableAnimationsOf(context),
    };
    final colors = Theme.of(context).colorScheme;
    final IconData icon = switch (kind) {
      DropboxWeatherKind.clouds ||
      DropboxWeatherKind.fog =>
        Icons.cloud_outlined,
      DropboxWeatherKind.rain => Icons.water_drop_outlined,
      DropboxWeatherKind.storm => Icons.thunderstorm_outlined,
      _ => daylight == DropboxDaylight.night
          ? Icons.nights_stay_outlined
          : Icons.wb_sunny_outlined,
    };
    if (canSimulate) {
      return widget.builder(context, environment,
          _buildWeatherToggle(colors, icon), _cycleDaylight);
    }
    if (!_supportsWeather) {
      return widget.builder(context, environment, null, null);
    }

    final label = switch (active) {
      final DropboxWeather conditions => '${conditions.temperature.round()}°',
      _ when _loading => 'Updating',
      _ when !_enabled => 'Set weather',
      _ when _locationProblem != null => 'Location needed',
      _ when _weatherUnavailable => 'Weather unavailable',
      _ => 'Local weather',
    };
    final control = TextButton.icon(
      onPressed: _showWeather,
      style: _controlStyle(colors),
      icon: Icon(icon, size: 17),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    return widget.builder(
        context,
        environment,
        Semantics(
          label: active == null
              ? 'Local weather'
              : 'Local weather, ${active.kind.label}',
          child: control,
        ),
        null);
  }
}
