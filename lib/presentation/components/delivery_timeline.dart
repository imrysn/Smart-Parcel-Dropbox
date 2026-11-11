import 'package:flutter/material.dart';
import '../../config/user_theme.dart';

/// Standalone single-responsibility component for 4-Stage Delivery Timelines.
class DeliveryTimeline extends StatelessWidget {
  final int stageIndex; // 0: Registered, 1: In Transit, 2: Delivered in Box, 3: Collected

  const DeliveryTimeline({
    super.key,
    required this.stageIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stages = ['Registered', 'In Transit', 'In Box', 'Collected'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(stages.length, (index) {
            final isCompleted = index <= stageIndex;
            final isCurrent = index == stageIndex;

            return Expanded(
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCompleted
                          ? UserTheme.primaryOrange
                          : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                color: UserTheme.primaryOrange.withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              )
                            ]
                          : null,
                    ),
                    child: Center(
                      child: isCompleted
                          ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                    ),
                  ),
                  if (index < stages.length - 1)
                    Expanded(
                      child: Container(
                        height: 3,
                        color: index < stageIndex
                            ? UserTheme.primaryOrange
                            : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(stages.length, (index) {
            final isCurrent = index == stageIndex;
            return Text(
              stages[index],
              style: TextStyle(
                fontSize: 10,
                fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w500,
                color: isCurrent
                    ? UserTheme.primaryOrange
                    : (isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
              ),
            );
          }),
        ),
      ],
    );
  }
}
