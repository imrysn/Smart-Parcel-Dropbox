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
    double blur = 12.0,
    double borderRadius = 20.0,
    EdgeInsetsGeometry? padding,
    Color? color,
    Border? border,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? (isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.85)),
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ?? Border.all(
          color: isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.05),
          width: 0.5,
        ),
      ),
      child: child,
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

  /// Premium Button with optional color, custom padding, and loading support.
  static Widget premiumButton({
    required String label,
    required VoidCallback onTap,
    IconData? icon,
    bool fullWidth = true,
    Color? color,
    Color textColor = Colors.white,
    double fontSize = 16,
    EdgeInsetsGeometry? padding,
    bool isLoading = false,
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
          onTap: isLoading ? null : () {
            HapticFeedback.mediumImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(UserTheme.radiusM),
          child: Padding(
            padding: padding ?? const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading) ...[
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(textColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else if (icon != null) ...[
                  Icon(icon, color: textColor, size: 18),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                      fontSize: fontSize,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

  /// Carrier Badge Widget (Shopee, Lazada, J&T, TikTok, Amazon, FedEx, DHL, etc.)
  static Widget carrierBadge(String platform) {
    final name = platform.trim();
    Color bg = const Color(0xFFE2E8F0);
    Color fg = const Color(0xFF334155);
    IconData icon = Icons.local_shipping_outlined;

    if (name.toLowerCase().contains('shopee')) {
      bg = const Color(0xFFFFF3E0);
      fg = const Color(0xFFEE4D2D);
      icon = Icons.shopping_bag_outlined;
    } else if (name.toLowerCase().contains('lazada')) {
      bg = const Color(0xFFE0F2FE);
      fg = const Color(0xFF0284C7);
      icon = Icons.storefront_outlined;
    } else if (name.toLowerCase().contains('tiktok')) {
      bg = const Color(0xFFF1F5F9);
      fg = const Color(0xFF0F172A);
      icon = Icons.video_library_outlined;
    } else if (name.toLowerCase().contains('j&t') || name.toLowerCase().contains('jt')) {
      bg = const Color(0xFFFFE4E6);
      fg = const Color(0xFFE11D48);
      icon = Icons.directions_bus_outlined;
    } else if (name.toLowerCase().contains('amazon')) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFD97706);
      icon = Icons.inventory_2_outlined;
    } else if (name.toLowerCase().contains('fedex')) {
      bg = const Color(0xFFF3E8FF);
      fg = const Color(0xFF7E22CE);
      icon = Icons.flight_takeoff_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            name.isEmpty ? 'Parcel' : name,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  /// Live Hardware / App Pulsing Status Indicator Badge
  static Widget pulsingStatusBadge({required bool isOnline, String? label}) {
    final color = isOnline ? UserTheme.statusSuccess : UserTheme.statusWarning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label ?? (isOnline ? 'BOX ONLINE' : 'OFFLINE'),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Interactive Delivery Timeline Widget (0: Pending, 1: In Transit, 2: Delivered/In Box, 3: Collected)
  static Widget deliveryTimeline({required int stageIndex, required BuildContext context}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = UserTheme.primaryOrange;
    final inactiveColor = isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.12);

    final stages = [
      {'label': 'Registered', 'icon': Icons.edit_note_outlined},
      {'label': 'In Transit', 'icon': Icons.local_shipping_outlined},
      {'label': 'In Box', 'icon': Icons.all_inbox_outlined},
      {'label': 'Collected', 'icon': Icons.verified_outlined},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: List.generate(stages.length, (i) {
          final isCompleted = i <= stageIndex;
          final isCurrent = i == stageIndex;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCompleted ? activeColor : inactiveColor,
                          boxShadow: isCurrent
                              ? [
                                  BoxShadow(
                                    color: activeColor.withOpacity(0.4),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  )
                                ]
                              : null,
                        ),
                        child: Icon(
                          stages[i]['icon'] as IconData,
                          size: 14,
                          color: isCompleted ? Colors.white : (isDark ? Colors.white54 : Colors.black38),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stages[i]['label'] as String,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                          color: isCompleted
                              ? (isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary)
                              : (isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < stages.length - 1)
                  Container(
                    height: 2,
                    width: 12,
                    margin: const EdgeInsets.only(bottom: 16),
                    color: i < stageIndex ? activeColor : inactiveColor,
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  /// Quick Action Power Tile
  static Widget quickActionTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = iconColor ?? UserTheme.primaryOrange;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(UserTheme.radiusL),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
            borderRadius: BorderRadius.circular(UserTheme.radiusL),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.08) : UserTheme.dayTextMuted.withOpacity(0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: primary, size: 22),
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Modern Stat Counter Card (Total In-Box, In-Transit, Pickups)
  static Widget statCounterCard({
    required BuildContext context,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        borderRadius: BorderRadius.circular(UserTheme.radiusL),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : UserTheme.dayTextMuted.withOpacity(0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Dynamic QR Code Digital Badge Card for Scanning by physical MH-ET Hardware Scanner
  static Widget qrAccessBadgeCard({
    required BuildContext context,
    required String qrToken,
    required VoidCallback onRefresh,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = UserTheme.primaryOrange;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFFFF7ED), const Color(0xFFFFEDD5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(UserTheme.radiusXL),
        border: Border.all(color: primary.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.qr_code_scanner_rounded, color: primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'QR Access Badge',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                color: primary,
                onPressed: onRefresh,
                tooltip: 'Refresh Digital QR Token',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.qr_code_2_rounded, size: 64, color: Colors.black),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hold QR up to Scanner',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Scan this QR code using the MH-ET scanner on your physical Dropbox to unlock doors.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


