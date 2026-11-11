import 'package:flutter/material.dart';

/// Clean typographic status indicator with semantic color.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
    );
  }
}
