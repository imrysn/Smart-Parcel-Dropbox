import 'dart:async';

import 'package:flutter/material.dart';
import '../config/dev_mode.dart';
import '../widgets/startup_intro.dart';
import '../widgets/user_ui.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/database_service.dart';
import '../services/secure_storage_service.dart';
import '../services/user_service.dart';
import '../services/service_locator.dart';

/// Splash Screen - Fast startup, session check, and optional biometric gate.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _introPreference = 'startup_intro_v1';
  static const _titleDuration = Duration(milliseconds: 280);

  late final AuthService _authService;
  late final DatabaseService _databaseService;
  late final BiometricService _biometricService;
  final _preferences = SecureStorageService();
  final _introFinished = Completer<void>();
  Future<void> _titleReady = Future<void>.value();

  bool _biometricLocked = false;
  bool _authenticating = false;
  bool _checkingIntro = true;
  bool _introChecked = false;
  bool _showIntro = false;
  bool _revealTitle = false;
  bool _startupPending = true;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_introChecked) return;
    _introChecked = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _checkingIntro = false;
      _introFinished.complete();
    } else {
      unawaited(_prepareIntro());
    }
  }

  Future<void> _prepareIntro() async {
    const preferenceTimeout = Duration(milliseconds: 350);
    final (seen, devModePreference) = await (
      _preferences
          .getPreference(_introPreference)
          .timeout(preferenceTimeout, onTimeout: () => 'true'),
      _preferences
          .getPreference(DevMode.preferenceKey)
          .timeout(preferenceTimeout, onTimeout: () => 'false'),
    ).wait;
    if (!mounted) return;
    final playIntro =
        (seen != 'true' || DevMode.isEnabled(devModePreference)) &&
        !MediaQuery.disableAnimationsOf(context);
    setState(() {
      _checkingIntro = false;
      _showIntro = playIntro;
    });
    if (!playIntro) _introFinished.complete();
  }

  void _finishIntro(bool played) {
    if (!_showIntro) return;
    if (played) _titleReady = Future<void>.delayed(_titleDuration);
    setState(() {
      _showIntro = false;
      _revealTitle = played;
    });
    unawaited(_preferences.savePreference(_introPreference, 'true'));
    _introFinished.complete();
  }

  @override
  void dispose() {
    if (!_introFinished.isCompleted) _introFinished.complete();
    super.dispose();
  }

  Future<void> _checkAuthState() async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;

    final isLoggedIn = await _authService.isLoggedIn;
    if (!isLoggedIn || await _authService.isTokenExpired()) {
      await _authService.signOut();
      if (!mounted) return;
      await _completeStartup(signedIn: false);
      return;
    }

    final userId = await _authService.currentUserId;
    if (userId == null) {
      await _authService.signOut();
      if (!mounted) return;
      await _completeStartup(signedIn: false);
      return;
    }

    // Validate stored JWT with server; tolerate offline/slow startup gracefully,
    // but force logout on explicit 401/404 SessionExpiredException.
    try {
      await _databaseService.getMe(timeout: const Duration(seconds: 4));
    } on SessionExpiredException {
      await _authService.signOut();
      if (!mounted) return;
      await _completeStartup(signedIn: false);
      return;
    } catch (e) {
      debugPrint('Splash session refresh deferred (offline/slow): $e');
    }

    if (!mounted) return;

    // Optional Biometric Lock on Launch (mobile platforms)
    final bioEnabled = await _authService.isBiometricLockEnabled();
    final bioAvailable =
        bioEnabled && await _biometricService.isBiometricAvailable();
    await _completeStartup(signedIn: true, promptBiometrics: bioAvailable);
  }

  Future<void> _completeStartup({
    required bool signedIn,
    bool promptBiometrics = false,
  }) async {
    if (!mounted) return;
    setState(() => _startupPending = false);
    await _introFinished.future;
    await _titleReady;
    if (!mounted) return;
    if (promptBiometrics) {
      await _promptBiometrics();
    } else if (signedIn) {
      _navigateToHome();
    } else {
      _navigateToLogin();
    }
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
    if (_showIntro) return StartupIntro(onFinished: _finishIntro);
    if (_checkingIntro) {
      return const Scaffold(backgroundColor: StartupIntro.background);
    }

    final colors = UserUi.dashboardColors(context);
    final showEndCard = _revealTitle && !_biometricLocked;
    final animate = showEndCard && !MediaQuery.disableAnimationsOf(context);
    final title = Text(
      StartupIntro.title,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: colors.foreground,
        fontSize: 27,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1.18,
      ),
    );
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cabinetHeight = (constraints.maxHeight * 0.36).clamp(
              120.0,
              264.0,
            );

            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    minHeight: constraints.maxHeight,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox.shrink(),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!showEndCard) ...[
                                _buildCabinetPreview(
                                  height: cabinetHeight,
                                  accent: colors.accent,
                                  shadow: colors.foreground,
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (animate)
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: 1),
                                  duration: _titleDuration,
                                  curve: Curves.easeOutCubic,
                                  child: title,
                                  builder: (context, value, child) => Opacity(
                                    opacity: value,
                                    child: Transform.translate(
                                      offset: Offset(0, 6 * (1 - value)),
                                      child: child,
                                    ),
                                  ),
                                )
                              else
                                title,
                              if (!showEndCard) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Secure Contactless Deliveries',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colors.secondary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                              if (_biometricLocked) ...[
                                const SizedBox(height: 24),
                                _buildUnlockActions(context),
                              ] else if (_startupPending) ...[
                                const SizedBox(height: 24),
                                _buildStartupStatus(context),
                              ],
                            ],
                          ),
                          if (showEndCard)
                            const SizedBox.shrink()
                          else
                            Padding(
                              padding: const EdgeInsets.only(top: 24),
                              child: Text(
                                'Cavite State University · Bacoor Campus',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.secondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
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

  Widget _buildCabinetPreview({
    required double height,
    required Color accent,
    required Color shadow,
  }) {
    return SizedBox(
      width: height * 1.14,
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 0.62,
                  colors: [
                    accent.withValues(alpha: 0.14),
                    accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: height * 0.05,
            child: Container(
              width: height * 0.44,
              height: height * 0.04,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height),
                boxShadow: [
                  BoxShadow(
                    color: shadow.withValues(alpha: 0.18),
                    blurRadius: 14,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          Image.asset(
            'assets/dropbox/smart-parcel-dropbox.png',
            width: height * 0.875,
            height: height,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStartupStatus(BuildContext context) {
    final colors = UserUi.dashboardColors(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!MediaQuery.disableAnimationsOf(context)) ...[
          ExcludeSemantics(
            child: SizedBox(
              width: 76,
              child: LinearProgressIndicator(
                minHeight: 3,
                borderRadius: BorderRadius.circular(3),
                backgroundColor: colors.border,
                color: colors.accent,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          'Starting up…',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.secondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildUnlockActions(BuildContext context) {
    final colors = UserUi.dashboardColors(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'App Locked',
          style: TextStyle(
            color: colors.foreground,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        UserUi.premiumButton(
          label: _authenticating ? 'Verifying...' : 'Unlock with Biometrics',
          onTap: _authenticating ? () {} : _promptBiometrics,
          isLoading: _authenticating,
          icon: Icons.fingerprint_rounded,
          color: colors.foreground,
          textColor: colors.surface,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () async {
            await _authService.signOut();
            if (!mounted) return;
            _navigateToLogin();
          },
          style: TextButton.styleFrom(foregroundColor: colors.secondary),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}
