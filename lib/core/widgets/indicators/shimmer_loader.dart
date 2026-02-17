import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Shimmer loading component for skeleton screens
/// 
/// Provides animated loading placeholders with:
/// - Configurable width and height
/// - Named constructors for common use cases (card, text)
/// - Smooth shimmer animation
/// 
/// Example:
/// ```dart
/// ShimmerLoader.card()  // Full-width card loader
/// ShimmerLoader.text(width: 120)  // Text placeholder
/// ```
class ShimmerLoader extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  const ShimmerLoader({
    super.key,
    this.width,
    this.height = 20,
    this.borderRadius,
  });

  const ShimmerLoader.card({
    super.key,
    this.width = double.infinity,
    this.height = 120,
  }) : borderRadius = const BorderRadius.all(Radius.circular(12));

  const ShimmerLoader.text({
    super.key,
    this.width = 100,
    this.height = 16,
  }) : borderRadius = const BorderRadius.all(Radius.circular(4));

  const ShimmerLoader.circle({
    super.key,
    double size = 50,
  })  : width = size,
        height = size,
        borderRadius = null;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius ?? BorderRadius.circular(8),
          shape: borderRadius == null && width == height
              ? BoxShape.circle
              : BoxShape.rectangle,
        ),
      ),
    );
  }
}

/// Shimmer loader specifically for tracking cards
class TrackingCardShimmer extends StatelessWidget {
  const TrackingCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                ShimmerLoader.text(width: 120),
                ShimmerLoader.text(width: 80),
              ],
            ),
            const SizedBox(height: 12),
            const ShimmerLoader.text(width: 200),
            const SizedBox(height: 8),
            const ShimmerLoader.text(width: 150),
          ],
        ),
      ),
    );
  }
}

/// Shimmer loader for profile header
class ProfileHeaderShimmer extends StatelessWidget {
  const ProfileHeaderShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        ShimmerLoader.circle(size: 100),
        SizedBox(height: 16),
        ShimmerLoader.text(width: 150, height: 24),
        SizedBox(height: 8),
        ShimmerLoader.text(width: 200, height: 16),
      ],
    );
  }
}
