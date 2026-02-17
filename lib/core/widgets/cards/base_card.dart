import 'package:flutter/material.dart';

/// Base card widget with consistent styling across the app
/// 
/// This component provides a reusable card foundation with:
/// - Consistent padding, margin, and border radius
/// - Optional gradient backgrounds
/// - Optional tap handling with InkWell
/// - Configurable elevation and colors
/// 
/// Example:
/// ```dart
/// BaseCard(
///   onTap: () => print('Tapped'),
///   child: Text('Card content'),
/// )
/// ```
class BaseCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final double? elevation;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Border? border;

  const BaseCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.backgroundColor,
    this.elevation = 2,
    this.borderRadius,
    this.onTap,
    this.gradient,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(12);
    
    Widget cardContent = Container(
      decoration: gradient != null
          ? BoxDecoration(
              gradient: gradient,
              borderRadius: effectiveBorderRadius,
              border: border,
            )
          : border != null
              ? BoxDecoration(
                  border: border,
                  borderRadius: effectiveBorderRadius,
                )
              : null,
      child: Padding(
        padding: padding!,
        child: child,
      ),
    );

    final card = Card(
      margin: margin,
      elevation: elevation,
      color: gradient != null ? Colors.transparent : backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: effectiveBorderRadius,
      ),
      child: cardContent,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: effectiveBorderRadius,
        child: card,
      );
    }

    return card;
  }
}
