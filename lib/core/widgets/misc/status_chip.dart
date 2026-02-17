import 'package:flutter/material.dart';

/// Enum for different chip types with semantic meaning
enum ChipType { 
  success,  // Green - for completed/successful states
  warning,  // Orange - for pending/in-progress states
  error,    // Red - for failed/error states
  info,     // Blue - for informational states
  neutral   // Grey - for inactive/default states
}

/// Status chip component for displaying status badges
/// 
/// Provides a consistent way to show status information with:
/// - Color-coded types (success, warning, error, info, neutral)
/// - Optional icon support
/// - Rounded corners with semi-transparent background
/// 
/// Example:
/// ```dart
/// StatusChip(
///   label: 'Delivered',
///   type: ChipType.success,
///   icon: Icons.check_circle,
/// )
/// ```
class StatusChip extends StatelessWidget {
  final String label;
  final ChipType type;
  final IconData? icon;
  final double? fontSize;

  const StatusChip({
    super.key,
    required this.label,
    this.type = ChipType.neutral,
    this.icon,
    this.fontSize = 13,
  });

  Color _getColor() {
    switch (type) {
      case ChipType.success:
        return Colors.green;
      case ChipType.warning:
        return Colors.orange;
      case ChipType.error:
        return Colors.red;
      case ChipType.info:
        return Colors.blue;
      case ChipType.neutral:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );
  }
}
