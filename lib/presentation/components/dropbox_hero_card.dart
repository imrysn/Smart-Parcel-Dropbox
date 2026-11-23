import 'package:flutter/material.dart';
import '../../config/user_theme.dart';
import '../../services/dropbox_weather_service.dart';
import '../../widgets/dropbox_model_view.dart';
import '../../widgets/dropbox_weather_scene.dart';

/// Dropbox Hero Card
///
/// Immersive Smart App Hero device card featuring:
/// 1. Reused 3D Three.js model from the Dropbox tab as a real-time background.
/// 2. Framed precisely on the LEFT side showing TOP-HALF VIEW ONLY (upper drop-off door,
///    handle, TFT color display, LED buttons, and optical scanner), cropping lower door
///    and castor wheels out of frame.
/// 3. Rendered at native WebGL resolution (NO post-raster scaling) to guarantee
///    100% razor-sharp rendering with zero blur.
/// 4. Stationary / Non-rotatable view (`IgnorePointer`) preserving the isometric
///    beauty angle while allowing home screen scrolling to pass through smoothly.
/// 5. Dynamic real-time sky/lighting (Dawn, Day, Dusk, Night via `DropboxWeatherScene`).
/// 6. Minimalist Smart Companion telemetry:
///    - Top-right: Weather pill and Battery percentage (UI only, no green dot) close together
///    - Bottom-right: Icon-only live bin counters (Drop-off stored & Pickup staged) without cards
/// 7. 1-Tap navigation to full interactive 3D cabinet controls.
class DropboxHeroCard extends StatefulWidget {
  final double height;
  final String deviceName;
  final int parcelCount;
  final int pickupCount;
  final bool hardwareOnline;
  final bool isLocked;
  final bool parcelDoorOpen;
  final bool pickupDoorOpen;
  final Stream<Map<String, dynamic>?>? doorStateStream;
  final DateTime? latestDelivery;
  final bool simulationEnabled;
  final int batteryPercent;
  final VoidCallback? onTap;
  final VoidCallback? onOpenCabinet;

  const DropboxHeroCard({
    super.key,
    this.height = 175.0,
    this.deviceName = 'Smart Parcel Dropbox',
    this.parcelCount = 0,
    this.pickupCount = 0,
    this.hardwareOnline = true,
    this.isLocked = true,
    this.parcelDoorOpen = false,
    this.pickupDoorOpen = false,
    this.doorStateStream,
    this.latestDelivery,
    this.simulationEnabled = false,
    this.batteryPercent = 98,
    this.onTap,
    this.onOpenCabinet,
  });

  @override
  State<DropboxHeroCard> createState() => _DropboxHeroCardState();
}

class _DropboxHeroCardState extends State<DropboxHeroCard> {
  DropboxWeatherService? _weatherService;
  String _weatherText = '';
  IconData _weatherIcon = Icons.wb_sunny_rounded;

  @override
  void initState() {
    super.initState();
    DropboxWeatherSimulation.addListener(_onSimulationChanged);
    _initDefaultWeather();
    _fetchLiveWeather();
  }

  void _onSimulationChanged() {
    if (!mounted) return;
    final simDaylight = DropboxWeatherSimulation.daylight;
    final simWeather = DropboxWeatherSimulation.weather;
    if (simDaylight != null || simWeather != null) {
      setState(() {
        if (simDaylight != null) {
          _weatherIcon = switch (simDaylight) {
            DropboxDaylight.night => Icons.nights_stay_rounded,
            DropboxDaylight.dusk => Icons.wb_twilight_rounded,
            DropboxDaylight.dawn => Icons.wb_twilight_rounded,
            DropboxDaylight.day => Icons.wb_sunny_rounded,
          };
          _weatherText = switch (simDaylight) {
            DropboxDaylight.night => '24°C',
            DropboxDaylight.dusk => '27°C',
            DropboxDaylight.dawn => '25°C',
            DropboxDaylight.day => '30°C',
          };
        }
        if (simWeather != null) {
          _weatherIcon = switch (simWeather) {
            DropboxWeatherKind.clouds ||
            DropboxWeatherKind.fog =>
              Icons.cloud_outlined,
            DropboxWeatherKind.rain => Icons.water_drop_outlined,
            DropboxWeatherKind.storm => Icons.thunderstorm_outlined,
            _ => _weatherIcon,
          };
        }
      });
    }
  }

  @override
  void dispose() {
    DropboxWeatherSimulation.removeListener(_onSimulationChanged);
    _weatherService?.dispose();
    super.dispose();
  }

  void _initDefaultWeather() {
    final simDaylight = DropboxWeatherSimulation.daylight;
    if (simDaylight != null) {
      _weatherText = switch (simDaylight) {
        DropboxDaylight.night => '24°C',
        DropboxDaylight.dusk => '27°C',
        DropboxDaylight.dawn => '25°C',
        DropboxDaylight.day => '30°C',
      };
      _weatherIcon = switch (simDaylight) {
        DropboxDaylight.night => Icons.nights_stay_rounded,
        DropboxDaylight.dusk => Icons.wb_twilight_rounded,
        DropboxDaylight.dawn => Icons.wb_twilight_rounded,
        DropboxDaylight.day => Icons.wb_sunny_rounded,
      };
      return;
    }
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 18) {
      _weatherText = '28°C';
      _weatherIcon = Icons.wb_sunny_rounded;
    } else {
      _weatherText = '24°C';
      _weatherIcon = Icons.nights_stay_rounded;
    }
  }

  Future<void> _fetchLiveWeather() async {
    if (DropboxWeatherSimulation.daylight != null ||
        DropboxWeatherSimulation.weather != null) {
      return;
    }
    try {
      final service = _weatherService ??= DropboxWeatherService();
      final weather = await service.localWeather(requestPermission: false);
      if (!mounted) return;
      if (DropboxWeatherSimulation.daylight != null ||
          DropboxWeatherSimulation.weather != null) {
        return;
      }
      setState(() {
        _weatherText = '${weather.temperature.round()}°C';
        _weatherIcon = switch (weather.kind) {
          DropboxWeatherKind.clouds ||
          DropboxWeatherKind.fog =>
            Icons.cloud_outlined,
          DropboxWeatherKind.rain => Icons.water_drop_outlined,
          DropboxWeatherKind.storm => Icons.thunderstorm_outlined,
          _ => weather.observedAt.hour >= 6 && weather.observedAt.hour < 18
              ? Icons.wb_sunny_rounded
              : Icons.nights_stay_rounded,
        };
      });
    } catch (_) {
      // Gracefully maintain ambient time-of-day default
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap ?? widget.onOpenCabinet,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth;
                final cardHeight =
                    constraints.maxHeight.isFinite && constraints.maxHeight > 0
                        ? constraints.maxHeight
                        : widget.height;

                // Native sizing without post-raster scaling, tuned for compact 175px height:
                const modelHeight = 295.0;
                final modelWidth = (cardWidth * 1.6).clamp(480.0, 1200.0);
                final cabinetCenterX = cardWidth * 0.25;
                final seamY = cardHeight - 8.0;
                final modelLeft = cabinetCenterX - modelWidth / 2;
                final modelTop = seamY - modelHeight / 2;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // ── 1. Reused 3D Cabinet Model View (Native Sharp Resolution & Real-time Door Sync) ──
                    Positioned(
                      left: modelLeft,
                      top: modelTop,
                      width: modelWidth,
                      height: modelHeight,
                      child: IgnorePointer(
                        child: StreamBuilder<Map<String, dynamic>?>(
                          stream: widget.doorStateStream,
                          builder: (context, doorSnap) {
                            final doorData = doorSnap.data;
                            final bool topDoorOpen = doorData != null &&
                                    (doorData['REED_TOP'] == true ||
                                        doorData['REED_TOP'] == 1 ||
                                        doorData['parcelDoorOpen'] == true) ||
                                widget.parcelDoorOpen;
                            final bool pickupDoorOpen = doorData != null &&
                                    (doorData['REED_PICKUP'] == true ||
                                        doorData['REED_PICKUP'] == 1 ||
                                        doorData['pickupDoorOpen'] == true) ||
                                widget.pickupDoorOpen;
                            final bool receivedDoorOpen = doorData != null &&
                                (doorData['REED_RECEIVED'] == true ||
                                    doorData['REED_RECEIVED'] == 1 ||
                                    doorData['receivedDoorOpen'] == true);
                            final bool anyOpen = topDoorOpen ||
                                pickupDoorOpen ||
                                receivedDoorOpen;

                            return DropboxModelView(
                              simulationEnabled: widget.simulationEnabled,
                              onDoorSelected: (_) {},
                              openDoors: {
                                'top': topDoorOpen,
                                'pickup': pickupDoorOpen,
                                'received': receivedDoorOpen,
                              },
                              parcelCount: widget.parcelCount,
                              hardwareOnline: widget.hardwareOnline,
                              anyDoorUnlocked: anyOpen || !widget.isLocked,
                              latestDelivery: widget.latestDelivery,
                              headerBuilder: (_) => const SizedBox.shrink(),
                            );
                          },
                        ),
                      ),
                    ),

                    // ── 2. Atmospheric Scrim (Subtle Contrast Gradient) ──
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.15),
                              Colors.black.withValues(alpha: 0.50),
                            ],
                            stops: const [0.0, 0.45, 0.72, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // Subtle Top Gradient for Status Contrast
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 44,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.25),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── 3. Right-Aligned Smart IoT Companion Telemetry ──
                    Positioned(
                      top: 12,
                      bottom: 12,
                      left: cardWidth * 0.48,
                      right: 14,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // ── Top-Right Bar: Weather and Battery Percentage Closer Together ──
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Live Weather Pill
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.42),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white
                                        .withValues(alpha: 0.16),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _weatherIcon,
                                      size: 12,
                                      color: Colors.amberAccent,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _weatherText,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 5),

                              // Battery Percentage Pill (UI only, no green dot)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.42),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white
                                        .withValues(alpha: 0.16),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.battery_charging_full_rounded,
                                      size: 12,
                                      color: UserTheme.statusSuccess,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${widget.batteryPercent}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // ── Bottom-Right: Icon-Only Live Bin Counters (No Cards) ──
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Stored Parcel Bin (Drop-off)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inventory_2_rounded,
                                    size: 16,
                                    color: widget.parcelCount > 0
                                        ? UserTheme.primaryOrangeLight
                                        : Colors.white.withValues(alpha: 0.90),
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 6,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${widget.parcelCount}',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: widget.parcelCount > 0
                                          ? UserTheme.primaryOrangeLight
                                          : Colors.white,
                                      shadows: const [
                                        Shadow(
                                          color: Colors.black87,
                                          blurRadius: 6,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 12),

                              // Staged Pickups Bin
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.outbox_rounded,
                                    size: 16,
                                    color: widget.pickupCount > 0
                                        ? Colors.lightBlueAccent
                                        : Colors.white.withValues(alpha: 0.90),
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 6,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${widget.pickupCount}',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: widget.pickupCount > 0
                                          ? Colors.lightBlueAccent
                                          : Colors.white,
                                      shadows: const [
                                        Shadow(
                                          color: Colors.black87,
                                          blurRadius: 6,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
