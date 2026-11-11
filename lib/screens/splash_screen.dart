import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/database_service.dart';
import '../services/user_service.dart';
import '../services/service_locator.dart';

/// Splash Screen - Fast startup, session check, and optional biometric gate.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final AuthService _authService;
  late final DatabaseService _databaseService;
  late final BiometricService _biometricService;

  bool _biometricLocked = false;
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    _authService = getIt<AuthService>();
    _databaseService = getIt<DatabaseService>();
    _biometricService = getIt.isRegistered<BiometricService>()
        ? getIt<BiometricService>()
        : BiometricService();
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 650)),
      ApiConfig.resolveServerUrl(),
    ]);
    if (!mounted) return;

    final isLoggedIn = await _authService.isLoggedIn;
    if (!isLoggedIn || await _authService.isTokenExpired()) {
      await _authService.signOut();
      if (!mounted) return;
      _navigateToLogin();
      return;
    }

    final userId = await _authService.currentUserId;
    if (userId == null) {
      await _authService.signOut();
      if (!mounted) return;
      _navigateToLogin();
      return;
    }

    // Validate stored JWT with server; tolerate offline/slow startup gracefully,
    // but force logout on explicit 401/404 SessionExpiredException.
    try {
      await _databaseService.getMe(timeout: const Duration(seconds: 4));
    } on SessionExpiredException {
      await _authService.signOut();
      if (!mounted) return;
      _navigateToLogin();
      return;
    } catch (e) {
      debugPrint('Splash session refresh deferred (offline/slow): $e');
    }

    if (!mounted) return;

    // Optional Biometric Lock on Launch (mobile platforms)
    final bioEnabled = await _authService.isBiometricLockEnabled();
    final bioAvailable = bioEnabled && await _biometricService.isBiometricAvailable();
    if (bioAvailable) {
      await _promptBiometrics();
      return;
    }

    _navigateToHome();
  }

  Future<void> _promptBiometrics() async {
    if (!mounted) return;
    setState(() {
      _biometricLocked = true;
      _authenticating = true;
    });

    final ok = await _biometricService.authenticate(
      reason: 'Verify identity to open Smart Parcel Drop Box',
    );
    if (!mounted) return;

    if (ok) {
      _navigateToHome();
    } else {
      setState(() => _authenticating = false);
    }
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _navigateToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary;
    final secondaryText = isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary;
    final mutedText = isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted;

    return Scaffold(
      backgroundColor: isDark ? UserTheme.nightBackground : UserTheme.dayBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: SizedBox(
                        width: double.infinity,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Spacer(),
                              Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  color: UserTheme.primaryOrange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: UserTheme.primaryOrange.withValues(alpha: 0.28),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.inventory_2_rounded,
                                  size: 38,
                                  color: UserTheme.primaryOrange,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Smart Parcel Drop Box',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: primaryText,
                                  letterSpacing: -0.6,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Secure Contactless Deliveries',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: secondaryText,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 36),
                              if (_biometricLocked) ...[
                                Text(
                                  'App Locked',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: primaryText,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                UserUi.premiumButton(
                                  label: _authenticating ? 'Verifying...' : 'Unlock with Biometrics',
                                  onTap: _authenticating ? () {} : _promptBiometrics,
                                  isLoading: _authenticating,
                                  icon: Icons.fingerprint_rounded,
                                ),
                                const SizedBox(height: 10),
                                TextButton(
                                  onPressed: () async {
                                    await _authService.signOut();
                                    if (!mounted) return;
                                    _navigateToLogin();
                                  },
                                  child: Text(
                                    'Sign out',
                                    style: TextStyle(color: secondaryText, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ] else
                                const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    valueColor: AlwaysStoppedAnimation<Color>(UserTheme.primaryOrange),
                                  ),
                                ),
                              const Spacer(),
                              const SizedBox(height: 24),
                              Text(
                                'Cavite State University · Bacoor Campus',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: mutedText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
