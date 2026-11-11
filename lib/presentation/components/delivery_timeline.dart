import 'package:flutter/material.dart';
import '../../config/user_theme.dart';

/// Minimal segmented progress track for delivery and pickup flows.
class DeliveryTimeline extends StatelessWidget {
  final int stageIndex;
  final bool isPickup;

  const DeliveryTimeline({
    super.key,
    required this.stageIndex,
    this.isPickup = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stages = isPickup
        ? const ['Scheduled', 'In Box', 'Picked Up']
        : const ['Registered', 'In Transit', 'In Box', 'Collected'];
    final clampedIndex = stageIndex.clamp(0, stages.length - 1);
    final isComplete = clampedIndex == stages.length - 1;
    final activeColor = isComplete ? UserTheme.statusSuccess : UserTheme.primaryOrange;
    final inactiveTrack = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(stages.length, (index) {
            final isReached = index <= clampedIndex;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index < stages.length - 1 ? 6 : 0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 4,
                  decoration: BoxDecoration(
                    color: isReached ? activeColor : inactiveTrack,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(stages.length, (index) {
            final isCurrent = index == clampedIndex;
            final isReached = index <= clampedIndex;
            return Text(
              stages[index],
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                color: isCurrent
                    ? activeColor
                    : (isReached
                        ? (isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary)
                        : (isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted)),
              ),
            );
          }),
        ),
      ],
    );
  }
}
