import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// User Theme Configuration
/// Modern Oasis theme with Plus Jakarta Sans and Sunset Gradients.
/// Supports both Light (Warm) and Dark (Midnight Sunset) modes.
class UserTheme {
  UserTheme._();
  
  /// Global theme state notifier
  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
  
  /// Convenience method to cycle through themes
  static void toggleThemeMode() {
    if (themeModeNotifier.value == ThemeMode.light) {
      themeModeNotifier.value = ThemeMode.dark;
    } else if (themeModeNotifier.value == ThemeMode.dark) {
      themeModeNotifier.value = ThemeMode.system;
    } else {
      themeModeNotifier.value = ThemeMode.light;
    }
  }

  // ─── Day Theme Palette (Warm Oasis) ────────────────────────────────────────

  static const Color primaryOrange = Color(0xFFFF9800);
  static const Color primaryOrangeLight = Color(0xFFFFB74D);
  static const Color primaryOrangeDark = Color(0xFFF57C00);

  static const Color accentAmber = Color(0xFFFFA726);
  static const Color accentAmberLight = Color(0xFFFFB74D);
  static const Color accentAmberDark = Color(0xFFFB8C00);

  // Gradient Colors - Sunset
  static const Color sunsetStart = Color(0xFFFF6F00); // Orange 900
  static const Color sunsetMid = Color(0xFFFF9800);   // Orange 500
  static const Color sunsetEnd = Color(0xFFE91E63);   // Pink 500

  // Backgrounds
  static const Color dayBackground = Color(0xFFFFF8F1);
  static const Color dayCard = Color(0xFFFFFFFF);
  static const Color daySurface = Color(0xFFFFF3E0);

  // Text Colors
  static const Color dayTextPrimary = Color(0xFF0F172A);   // Deep Slate
  static const Color dayTextSecondary = Color(0xFF475569); // Slate 600
  static const Color dayTextMuted = Color(0xFF94A3B8);     // Slate 400

  // ─── Night Theme Palette (Midnight Sunset) ───────────────────────────────

  static const Color nightBackground = Color(0xFF0F172A); // Slate 900
  static const Color nightCard = Color(0xFF1E293B);       // Slate 800
  static const Color nightSurface = Color(0xFF334155);    // Slate 700

  static const Color nightTextPrimary = Color(0xFFF8FAFC);
  static const Color nightTextSecondary = Color(0xFFCBD5E1);
  static const Color nightTextMuted = Color(0xFF64748B);

  static const Color statusSuccess = Color(0xFF10B981); // Emerald 500
  static const Color statusWarning = Color(0xFFF59E0B); // Amber 500
  static const Color statusError = Color(0xFFEF4444);   // Red 500
  static const Color statusInfo = Color(0xFF3B82F6);    // Blue 500

  // ─── Legacy & Utility Aliases ──────────────────────────────────────────
  
  static const Color gradientPink = sunsetEnd;
  static const Color backgroundSurface = daySurface;
  static const Color backgroundCard = dayCard;
  static const Color textPrimary = dayTextPrimary;
  static const Color textSecondary = dayTextSecondary;
  static const Color textMuted = dayTextMuted;

  // ─── Design Tokens ──────────────────────────────────────────────────────

  static const double radiusS = 12;
  static const double radiusM = 16;
  static const double radiusL = 24;
  static const double radiusXL = 32;

  static LinearGradient get sunsetGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [sunsetStart, sunsetMid, sunsetEnd],
      );

  static LinearGradient get glassGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.12),
          Colors.white.withOpacity(0.04),
        ],
      );

  // ─── Theme Builders ─────────────────────────────────────────────────────

  /// Main theme retrieval method.
  static ThemeData getTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final Color primary = primaryOrange;
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
            color: isDark ? Colors.white.withOpacity(0.08) : textMuted.withOpacity(0.12),
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
          borderSide: BorderSide(color: textMuted.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide(color: textMuted.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusM),
          borderSide: BorderSide(color: primary, width: 2),
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

  /// Helper for status pills.
  static Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending': return statusWarning;
      case 'in_transit': return statusInfo;
      case 'delivered': return statusSuccess;
      case 'retrieved': return accentAmber;
      default: return dayTextMuted;
    }
  }

  /// Modern Gradient App Bar.
  static PreferredSizeWidget appBarGradient({
    required String title,
    List<Widget>? actions,
    bool centerTitle = true,
    PreferredSizeWidget? bottom,
    Widget? leading,
    BuildContext? context, // Added context to detect theme
  }) {
    final bool isDark = context != null && Theme.of(context).brightness == Brightness.dark;
    
    return AppBar(
      leading: leading,
      centerTitle: centerTitle,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          // Use gradient only for dark mode, solid for light mode as requested
          gradient: isDark ? sunsetGradient : null,
          color: isDark ? null : dayBackground,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDark ? Colors.white : dayTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      iconTheme: IconThemeData(color: isDark ? Colors.white : dayTextPrimary),
      actions: actions,
      bottom: bottom,
    );
  }
}
