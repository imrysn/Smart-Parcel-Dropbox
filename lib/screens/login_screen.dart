import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/api_config.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/input_validator.dart';
import 'register_screen.dart';
import 'home_screen.dart';
import 'password_reset_screen.dart';

/// Email and password sign-in.
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
    if (_isLoading || !_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = await _authService.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) {
        TextInput.finishAutofillContext();
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
    final resetFormKey = GlobalKey<FormState>();
    var email = _emailController.text;
    var isDialogLoading = false;

    UserUi.showDashboardDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final colors = UserUi.dashboardColors(context);
            return AlertDialog(
              title: const Text('Reset password'),
              scrollable: true,
              content: Form(
                key: resetFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Enter your email address and we\'ll send you a verification code to reset your password.',
                      style: TextStyle(
                        fontSize: 14,
                        color: colors.secondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      initialValue: email,
                      onChanged: (value) => email = value,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !isDialogLoading,
                      decoration:
                          const InputDecoration(labelText: 'Email address'),
                      validator: InputValidator.validateEmail,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isDialogLoading
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isDialogLoading
                      ? null
                      : () async {
                          if (!resetFormKey.currentState!.validate()) return;
                          setDialogState(() => isDialogLoading = true);
                          final navigator = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            final resetEmail = email.trim();
                            await _databaseService
                                .requestPasswordReset(resetEmail);
                            if (context.mounted) {
                              navigator.pop();
                              navigator.push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        PasswordResetScreen(email: resetEmail)),
                              );
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'If your account exists, a reset code has been sent.'),
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
                              setDialogState(() => isDialogLoading = false);
                            }
                          }
                        },
                  child: Text(isDialogLoading ? 'Sending…' : 'Send code'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBrandHeader(BuildContext context) {
    final colors = UserUi.dashboardColors(context);
    final compact = MediaQuery.sizeOf(context).width < 390;
    final artworkWidth = compact ? 104.0 : 134.0;
    return UserUi.dashboardCard(
      context,
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.72, 0.10),
            radius: 1.05,
            colors: [colors.accent.withValues(alpha: 0.16), colors.surface],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: Text(
                    'Smart Parcel\nDropbox',
                    semanticsLabel: 'Smart Parcel Dropbox',
                    style: TextStyle(
                      fontSize: compact ? 24 : 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      height: 1.16,
                      color: colors.foreground,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Trim the faint line at the top of the bundled cabinet render.
              ClipRect(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  widthFactor: 1,
                  heightFactor: 0.96,
                  child: Image.asset(
                    'assets/dropbox/smart-parcel-dropbox.png',
                    width: artworkWidth,
                    height: artworkWidth * 8 / 7,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    final colors = UserUi.dashboardColors(context);
    return UserUi.dashboardCard(
      context,
      child: Theme(
        data: Theme.of(context).copyWith(
            inputDecorationTheme: UserUi.dashboardInputTheme(context)),
        child: AutofillGroup(
          onDisposeAction: AutofillContextAction.cancel,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Welcome back',
                    style: TextStyle(
                      color: colors.foreground,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.55,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(labelText: 'Email address'),
                  validator: InputValidator.validateEmail,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      tooltip:
                          _obscurePassword ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Please enter password'
                      : null,
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    style: TextButton.styleFrom(foregroundColor: colors.accent),
                    onPressed: _isLoading ? null : _showForgotPasswordDialog,
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: 4),
                FilledButton(
                  style: UserUi.dashboardFilledStyle(context),
                  onPressed: _isLoading ? null : _login,
                  child: Text(_isLoading ? 'Signing in…' : 'Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDebugTools(BuildContext context) {
    final colors = UserUi.dashboardColors(context);
    return ExpansionTile(
      title: const Text('Developer tools', style: TextStyle(fontSize: 13)),
      textColor: colors.foreground,
      collapsedTextColor: colors.secondary,
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          style: UserUi.dashboardOutlineStyle(context),
          onPressed: () {
            _emailController.text = 'imrays23@gmail.com';
            _passwordController.text = 'password123';
          },
          child: const Text('Fill demo account'),
        ),
        const SizedBox(height: 8),
        Text(
          'Server: ${ApiConfig.serverUrl}',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.secondary, fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = UserUi.dashboardColors(context);
    const verticalPadding = 24.0;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.symmetric(
              horizontal: UserUi.horizontalGutter(context),
              vertical: verticalPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 2 * verticalPadding)
                    .clamp(0.0, double.infinity),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildBrandHeader(context),
                      const SizedBox(height: 14),
                      _buildLoginForm(context),
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'New here?',
                            style: TextStyle(
                                color: colors.secondary, fontSize: 13),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                                foregroundColor: colors.accent),
                            onPressed: _isLoading
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => const RegisterScreen(),
                                      ),
                                    ),
                            child: const Text('Create account'),
                          ),
                        ],
                      ),
                      if (kDebugMode) _buildDebugTools(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
