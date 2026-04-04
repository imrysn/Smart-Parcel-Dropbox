import 'package:flutter/material.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/input_validator.dart';
import 'register_screen.dart';
import 'home_screen.dart';
import 'admin/admin_dashboard_screen.dart';
import 'password_reset_screen.dart';

/// Login Screen - User authentication with Email/Password and Google Sign-In
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  final DatabaseService _databaseService = DatabaseService();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = await _authService.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) {
        await _navigateAfterLogin(user);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: UserTheme.statusError,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _navigateAfterLogin(Map<String, dynamic> user) async {
    if (!mounted) return;

    final role = user['role'];

    if (role == 'admin') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  void _showForgotPasswordDialog() {
    final TextEditingController resetEmailController = TextEditingController();
    final GlobalKey<FormState> resetFormKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        bool isDialogLoading = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UserTheme.radiusL)),
              title: const Text('Reset Password'),
              content: Form(
                key: resetFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Enter your email address and we\'ll send you a verification code to reset your password.',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: resetEmailController,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !isDialogLoading,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: InputValidator.validateEmail,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isDialogLoading ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                SizedBox(
                  width: 120,
                  height: 48,
                  child: UserUi.premiumButton(
                    label: isDialogLoading ? '...' : 'Send',
                    onTap: isDialogLoading
                        ? () {}
                        : () async {
                            if (!resetFormKey.currentState!.validate()) return;
                            setDialogState(() => isDialogLoading = true);
                            try {
                              final email = resetEmailController.text.trim();
                              final exists = await _databaseService.checkEmailExists(email);
                              if (!exists) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('This email is not registered.'),
                                      backgroundColor: UserTheme.statusError,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                                setDialogState(() => isDialogLoading = false);
                                return;
                              }
                              await _databaseService.requestPasswordReset(email);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (context) => PasswordResetScreen(email: email)),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Reset code sent!'),
                                    backgroundColor: UserTheme.statusSuccess,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e'), backgroundColor: UserTheme.statusError),
                                );
                              }
                              setDialogState(() => isDialogLoading = false);
                            }
                          },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? UserTheme.nightBackground : UserTheme.dayBackground,
      // Prevent Scaffold from resizing — the SingleChildScrollView handles keyboard avoidance.
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Fixed, stable header height based on the physical screen — never squishes.
          final double screenHeight = constraints.maxHeight;
          final double headerHeight = screenHeight * 0.45;

          return SingleChildScrollView(
            // Allows dragging down to dismiss keyboard.
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              // Ensures the Column always fills the visible screen when keyboard is hidden.
              constraints: BoxConstraints(minHeight: screenHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ─── Sunset Header ─────────────────────────────────────────
                  SizedBox(
                    height: headerHeight,
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: UserTheme.sunsetGradient),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Decorative circle — top-right
                          Positioned(
                            top: -64,
                            right: -64,
                            child: Container(
                              width: 256,
                              height: 256,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          // Decorative circle — bottom-left
                          Positioned(
                            bottom: -32,
                            left: -32,
                            child: Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          // Branding content — safe area aware
                          SafeArea(
                            bottom: false,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  UserUi.glassCard(
                                    context,
                                    blur: 16,
                                    borderRadius: UserTheme.radiusXL,
                                    padding: const EdgeInsets.all(28),
                                    color: Colors.white.withOpacity(0.15),
                                    child: const Icon(
                                      Icons.inventory_2_rounded,
                                      size: 64,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  const Text(
                                    'SPD',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: 6,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Smart Parcel\nDrop Box',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      height: 1,
                                      letterSpacing: -1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ─── Form Card ─────────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    // minHeight fills the rest of the screen; grows naturally with the form.
                    constraints: BoxConstraints(minHeight: screenHeight - headerHeight),
                    decoration: BoxDecoration(
                      color: isDark ? UserTheme.nightBackground : UserTheme.dayBackground,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(UserTheme.radiusXL),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(28, 32, 28, 48),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          UserUi.sectionTitle(
                            context,
                            'Welcome Back',
                            subtitle: 'Sign in to continue managing your parcels',
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email Address',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            validator: InputValidator.validateEmail,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_open_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () =>
                                    setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            validator: (value) =>
                                value == null || value.isEmpty ? 'Please enter password' : null,
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _isLoading ? null : _showForgotPasswordDialog,
                              child: const Text('Forgot Password?'),
                            ),
                          ),
                          const SizedBox(height: 24),
                          _isLoading
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      color: UserTheme.primaryOrange))
                              : UserUi.premiumButton(
                                  label: 'SIGN IN',
                                  onTap: _login,
                                  icon: Icons.login_rounded,
                                ),
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'New here? ',
                                style: TextStyle(
                                  color: isDark
                                      ? UserTheme.nightTextMuted
                                      : UserTheme.dayTextMuted,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (context) => const RegisterScreen()),
                                  );
                                },
                                child: const Text('Create Account'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
