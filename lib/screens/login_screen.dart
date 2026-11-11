import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/input_validator.dart';
import 'register_screen.dart';
import 'home_screen.dart';
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
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
                            final navigator = Navigator.of(context);
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              final email = resetEmailController.text.trim();
                              await _databaseService.requestPasswordReset(email);
                              if (context.mounted) {
                                navigator.pop();
                                navigator.push(
                                  MaterialPageRoute(builder: (_) => PasswordResetScreen(email: email)),
                                );
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('If your account exists, a reset code has been sent.'),
                                    backgroundColor: UserTheme.statusSuccess,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(e.toString()),
                                    backgroundColor: UserTheme.statusError,
                                    behavior: SnackBarBehavior.floating,
                                  ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary;
    final secondaryText = isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary;
    final mutedText = isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    final gutter = UserUi.horizontalGutter(context);

    return Scaffold(
      backgroundColor: isDark ? UserTheme.nightBackground : UserTheme.dayBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 48).clamp(0.0, double.infinity),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: SizedBox(
                      width: double.infinity,
                      child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Minimalist Brand Mark & Greeting
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: UserTheme.primaryOrange,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.inventory_2_rounded,
                          size: 26,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Welcome back',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: primaryText,
                        letterSpacing: -0.7,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to manage deliveries and your dropbox.',
                      style: TextStyle(
                        fontSize: 14,
                        color: secondaryText,
                      ),
                    ),
                    const SizedBox(height: 28),

                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                      validator: InputValidator.validateEmail,
                    ),
                    const SizedBox(height: 14),
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
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    UserUi.premiumButton(
                      label: 'Sign in',
                      onTap: _login,
                      isLoading: _isLoading,
                      icon: Icons.login_rounded,
                    ),

                    if (kDebugMode) ...[
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(child: Divider(color: borderColor)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'Debug quick fill',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: mutedText,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: borderColor)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          _emailController.text = 'imrays23@gmail.com';
                          _passwordController.text = 'password123';
                        },
                        icon: const Icon(Icons.person_outline_rounded, size: 16, color: UserTheme.primaryOrange),
                        label: Text(
                          'Fill demo account',
                          style: TextStyle(
                            color: primaryText,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          side: BorderSide(color: borderColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(UserTheme.radiusM),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Server: ${ApiConfig.serverUrl}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: mutedText),
                      ),
                    ],

                    const SizedBox(height: 20),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'New here? ',
                          style: TextStyle(color: secondaryText, fontSize: 13),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const RegisterScreen(),
                              ),
                            );
                          },
                          child: const Text(
                            'Create account',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
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
