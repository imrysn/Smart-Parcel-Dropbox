import 'package:flutter/material.dart';
import '../../config/user_theme.dart';

/// Single-responsibility component for Emergency Lockdown Switch Card.
class EmergencyLockdownCard extends StatelessWidget {
  final bool isLockdownActive;
  final ValueChanged<bool> onToggle;

  const EmergencyLockdownCard({
    super.key,
    required this.isLockdownActive,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dangerColor = const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isLockdownActive ? dangerColor.withOpacity(0.12) : (isDark ? UserTheme.nightCard : UserTheme.dayCard),
        borderRadius: BorderRadius.circular(UserTheme.radiusL),
        border: Border.all(
          color: isLockdownActive ? dangerColor : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isLockdownActive ? Icons.gpp_bad_rounded : Icons.shield_outlined,
            color: isLockdownActive ? dangerColor : UserTheme.statusSuccess,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLockdownActive ? 'EMERGENCY LOCKDOWN ACTIVE' : 'Master System Security',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isLockdownActive ? dangerColor : (isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary),
                  ),
                ),
                Text(
                  isLockdownActive ? 'All solenoids physically disabled' : 'Dropbox nominal & threat protection live',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: isLockdownActive,
            activeColor: dangerColor,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}
