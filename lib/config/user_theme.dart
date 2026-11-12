import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// User Theme Configuration
/// Modern Minimalist palette anchored on signature orange (#FF9800) with crisp
/// neutral surfaces across Light and Dark modes.
class UserTheme {
  UserTheme._();

  // ─── Brand Signature Accent ────────────────────────────────────────────────

  static const Color primaryOrange = Color(0xFFFF9800);
  static const Color primaryOrangeLight = Color(0xFFFFB74D);
  static const Color primaryOrangeDark = Color(0xFFF57C00);

  static const Color accentAmber = Color(0xFFFFA726);
  static const Color accentAmberLight = Color(0xFFFFB74D);
  static const Color accentAmberDark = Color(0xFFF57C00);

  // Tonal Orange Stops (no hot-pink gradient)
  static const Color sunsetStart = Color(0xFFFF9800);
  static const Color sunsetMid = Color(0xFFF57C00);
  static const Color sunsetEnd = Color(0xFFEF6C00);

  // ─── Light Theme Palette (Modern Alabaster) ────────────────────────────────

  static const Color dayBackground = Color(0xFFF9FAFB);
  static const Color dayCard = Color(0xFFFFFFFF);
  static const Color daySurface = Color(0xFFF3F4F6);

  // Text Colors
  static const Color dayTextPrimary = Color(0xFF111827);
  static const Color dayTextSecondary = Color(0xFF4B5563);
  static const Color dayTextMuted = Color(0xFF9CA3AF);

  // ─── Dark Theme Palette (True Charcoal) ────────────────────────────────────

  static const Color nightBackground = Color(0xFF0A0A0B);
  static const Color nightCard = Color(0xFF141416);
  static const Color nightSurface = Color(0xFF202024);

  static const Color nightTextPrimary = Color(0xFFFAFAFA);
  static const Color nightTextSecondary = Color(0xFFA1A1AA);
  static const Color nightTextMuted = Color(0xFF71717A);

  static const Color statusSuccess = Color(0xFF16A34A);
  static const Color statusWarning = Color(0xFFD97706);
  static const Color statusError = Color(0xFFDC2626);
  static const Color statusInfo = Color(0xFF2563EB);

  // ─── Legacy & Utility Aliases ──────────────────────────────────────────────

  static const Color gradientPink = sunsetEnd;
  static const Color backgroundSurface = daySurface;
  static const Color backgroundCard = dayCard;
  static const Color textPrimary = dayTextPrimary;
  static const Color textSecondary = dayTextSecondary;
  static const Color textMuted = dayTextMuted;

  // ─── Design Tokens ─────────────────────────────────────────────────────────

  static const double radiusS = 12;
  static const double radiusM = 16;
  static const double radiusL = 20;
  static const double radiusXL = 28;

  static LinearGradient get sunsetGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primaryOrange, primaryOrangeDark],
      );

  static LinearGradient get glassGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.10),
          Colors.white.withValues(alpha: 0.03),
        ],
      );

  // ─── Theme Builders ─────────────────────────────────────────────────────

  /// Main theme retrieval method.
  static ThemeData getTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    const Color primary = primaryOrange;
    final Color background = isDark ? nightBackground : dayBackground;
    final Color card = isDark ? nightCard : dayCard;
    final Color textPrimary = isDark ? nightTextPrimary : dayTextPrimary;
    final Color textSecondary = isDark ? nightTextSecondary : dayTextSecondary;
    final Color textMuted = isDark ? nightTextMuted : dayTextMuted;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: primary,
      scaffoldBackgroundColor: background,

      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryOrange,
        brightness: brightness,
        primary: primary,
        secondary: accentAmber,
        surface: card,
        error: statusError,
      ).copyWith(
        surface: card,
        onSurface: textPrimary,
      ),

      // Typography - Plus Jakarta Sans
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        TextTheme(
          displayLarge: TextStyle(fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -1),
          displayMedium: TextStyle(fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.8),
          displaySmall: TextStyle(fontWeight: FontWeight.w700, color: textPrimary, letterSpacing: -0.5),
          headlineLarge: TextStyle(fontWeight: FontWeight.w700, color: textPrimary),
          headlineMedium: TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
          titleLarge: TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
          bodyLarge: TextStyle(color: textPrimary, fontSize: 16),
          bodyMedium: TextStyle(color: textSecondary, fontSize: 14),
          bodySmall: TextStyle(color: textMuted, fontSize: 12),
        ),
      ),

      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isDark ? nightBackground : dayBackground,
        foregroundColor: textPrimary,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),

      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusL),
          side: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusM)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide(color: textMuted.withValues(alpha: 0.25)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide(color: textMuted.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        labelStyle: TextStyle(color: textSecondary),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: card,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  /// Default getter for backward compatibility (defaults to light).
  static ThemeData get theme => getTheme(Brightness.light);

  /// Helper for status indicators.
  static Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
      case 'awaiting_pickup':
        return primaryOrange;
      case 'in_transit':
      case 'ready_for_pickup':
        return statusInfo;
      case 'delivered':
      case 'retrieved':
      case 'done':
        return statusSuccess;
      default:
        return dayTextMuted;
    }
  }

  /// Clean minimalist AppBar matching the page canvas.
  static PreferredSizeWidget appBarGradient({
    required String title,
    List<Widget>? actions,
    bool centerTitle = true,
    PreferredSizeWidget? bottom,
    Widget? leading,
    BuildContext? context,
    Color? backgroundColor,
  }) {
    final bool isDark = context != null && Theme.of(context).brightness == Brightness.dark;

    return AppBar(
      leading: leading,
      centerTitle: centerTitle,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor:
          backgroundColor ?? (isDark ? nightBackground : dayBackground),
      title: Text(
        title,
        style: TextStyle(
          color: isDark ? nightTextPrimary : dayTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      iconTheme: IconThemeData(color: isDark ? nightTextPrimary : dayTextPrimary),
      actions: actions,
      bottom: bottom,
    );
  }
}
