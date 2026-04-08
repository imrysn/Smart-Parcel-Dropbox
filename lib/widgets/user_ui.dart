import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import '../config/user_theme.dart';

/// Shared layout and surface styles for the user (mobile) app.
/// Colors and Design Tokens come from [UserTheme].
class UserUi {
  UserUi._();

  static const double sS = 8.0;
  static const double sM = 16.0;
  static const double sL = 24.0;
  static const double sXL = 32.0;

  /// Theme-aware page background.
  static BoxDecoration pageBackground(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: isDark ? UserTheme.nightBackground : UserTheme.dayBackground,
    );
  }

  /// Premium "Glass" Surface.
  static Widget glassCard(
    BuildContext context, {
    required Widget child,
    double blur = 24.0,
    double borderRadius = 28.0,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    Color? color,
    Border? border,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          // 1. Large soft ambient shadow
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
          // 2. Sharp contact shadow for depth
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.5 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color ?? (isDark ? Colors.white.withOpacity(0.03) : Colors.white.withOpacity(0.75)),
              borderRadius: BorderRadius.circular(borderRadius),
              // --- Edge Lighting Effect ---
              border: border ?? Border.all(
                color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withValues(alpha: 0.5),
                width: 0.8,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  isDark ? Colors.white.withOpacity(0.04) : Colors.white.withOpacity(0.2),
                  Colors.transparent,
                ],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  /// Solid Surface Card Widget.
  static Widget surfaceCard(BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry? padding,
    Color? color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? (isDark ? UserTheme.nightCard : UserTheme.dayCard),
        borderRadius: BorderRadius.circular(UserTheme.radiusL),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : UserTheme.dayTextMuted.withOpacity(0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  /// Premium Button with optional color support.
  static Widget premiumButton({
    required String label,
    required VoidCallback onTap,
    IconData? icon,
    bool fullWidth = true,
    Color? color,
    Color textColor = Colors.white,
    double fontSize = 16,
  }) {
    return Container(
      width: fullWidth ? double.infinity : null,
      decoration: BoxDecoration(
        gradient: color == null ? UserTheme.sunsetGradient : null,
        color: color,
        borderRadius: BorderRadius.circular(UserTheme.radiusM),
        boxShadow: [
          BoxShadow(
            color: (color ?? UserTheme.sunsetMid).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(UserTheme.radiusM),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w900,
                    fontSize: fontSize,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Modern Section Title.
  static Widget sectionTitle(BuildContext context, String title, {String? subtitle}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: -0.5,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Refined Status Pill.
  static Widget statusPill({
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(UserTheme.radiusXL),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Premium Empty State.
  static Widget emptyState(BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(sXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(sXL),
              decoration: BoxDecoration(
                color: (isDark ? UserTheme.nightCard : UserTheme.daySurface).withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 64, color: UserTheme.primaryOrange.withOpacity(0.8)),
            ),
            const SizedBox(height: sL),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: sS),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Shared Input Decoration for premium forms.
  static InputDecoration inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    required BuildContext context,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = UserTheme.primaryOrange;
    
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: primaryColor, size: 20),
      labelStyle: TextStyle(
        color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
      ),
      filled: true,
      fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UserTheme.radiusM),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UserTheme.radiusM),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UserTheme.radiusM),
        borderSide: BorderSide(color: primaryColor.withOpacity(0.5), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  /// Shimmer skeleton placeholder for a card row.
  static Widget shimmerCard(BuildContext context, {double height = 88}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8E8E8);
    final highlightColor = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Container(
        height: height,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(UserTheme.radiusL),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(height: 14, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6))),
                  const SizedBox(height: 8),
                  Container(height: 11, width: 160, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6))),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Container(width: 56, height: 22, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20))),
          ],
        ),
      ),
    );
  }

  /// Renders [count] shimmer skeleton cards stacked vertically.
  static Widget shimmerList(BuildContext context, {int count = 4, double cardHeight = 88}) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: count,
      itemBuilder: (_, __) => shimmerCard(context, height: cardHeight),
    );
  }
}
