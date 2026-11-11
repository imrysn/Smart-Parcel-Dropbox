import 'package:flutter/material.dart';
import '../../config/user_theme.dart';

/// Single-responsibility component for Telemetry Barometer Card.
class TelemetryBarometerCard extends StatelessWidget {
  final String wifiRssi;
  final String batteryVoltage;
  final String internalTemp;

  const TelemetryBarometerCard({
    super.key,
    required this.wifiRssi,
    required this.batteryVoltage,
    required this.internalTemp,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        borderRadius: BorderRadius.circular(UserTheme.radiusL),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : UserTheme.dayTextMuted.withOpacity(0.12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _telemetryItem(
            context,
            icon: Icons.wifi,
            label: 'Wi-Fi Signal',
            value: wifiRssi,
            color: const Color(0xFF10B981),
          ),
          Container(width: 1, height: 32, color: isDark ? Colors.white10 : Colors.black12),
          _telemetryItem(
            context,
            icon: Icons.battery_charging_full_rounded,
            label: 'Battery',
            value: batteryVoltage,
            color: UserTheme.accentAmberDark,
          ),
          Container(width: 1, height: 32, color: isDark ? Colors.white10 : Colors.black12),
          _telemetryItem(
            context,
            icon: Icons.thermostat_rounded,
            label: 'Internal Temp',
            value: internalTemp,
            color: UserTheme.primaryOrange,
          ),
        ],
      ),
    );
  }

  Widget _telemetryItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
          ),
        ),
      ],
    );
  }
}
