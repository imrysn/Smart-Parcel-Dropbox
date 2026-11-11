import 'dart:async';
import 'package:flutter/material.dart';
import '../config/user_theme.dart';
import '../services/dropbox_service.dart';
import '../services/service_locator.dart';
import '../widgets/user_ui.dart';
import 'home_screen.dart';

/// Hardware Config Screen
///
/// Shown after successful device registration.
/// Collects only WiFi SSID + Password from the user, then pushes the
/// credentials to the device via Socket.IO (pushHardwareConfig event).
/// Server Host and Port are pre-baked into the firmware — the user
/// never needs to know or configure those values.
class HardwareConfigScreen extends StatefulWidget {
  final String deviceId;
  final bool goToHomeAfter;
  const HardwareConfigScreen({
    super.key,
    required this.deviceId,
    this.goToHomeAfter = false,
  });

  @override
  State<HardwareConfigScreen> createState() => _HardwareConfigScreenState();
}

class _HardwareConfigScreenState extends State<HardwareConfigScreen> {
  final _dropboxService  = getIt<DropboxService>();
  final _ssidController  = TextEditingController();
  final _passController  = TextEditingController();

  StreamSubscription? _appliedSub;
  Timer?              _timeoutTimer;

  bool _sending       = false;
  bool _obscurePass   = true;
  String? _errorMsg;
  String? _successMsg;

  @override
  void initState() {
    super.initState();
    _appliedSub = _dropboxService.hardwareConfigAppliedStream.listen(_onApplied);
    _dropboxService.ensureSocketConnected();
  }

  @override
  void dispose() {
    _appliedSub?.cancel();
    _timeoutTimer?.cancel();
    _ssidController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _onApplied(Map<String, dynamic> data) {
    if (!mounted) return;
    _timeoutTimer?.cancel();
    setState(() {
      _sending    = false;
      _successMsg = 'Done! Your Dropbox is now connecting to your WiFi. '
          'This may take a moment.';
    });
    // Navigate back to Home / Dropbox Management after a moment
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (widget.goToHomeAfter) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      } else {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    });
  }

  Future<void> _sendConfig() async {
    final ssid = _ssidController.text.trim();
    final pass = _passController.text;
    if (ssid.isEmpty) {
      setState(() => _errorMsg = 'Please enter your WiFi network name (SSID).');
      return;
    }
    setState(() {
      _sending    = true;
      _errorMsg   = null;
      _successMsg = null;
    });
    if (!_dropboxService.isSocketConnected) {
      await _dropboxService.ensureSocketConnected();
    }
    if (!_dropboxService.isSocketConnected) {
      if (mounted) {
        setState(() {
          _sending = false;
          _errorMsg = 'Not connected to server yet. Check your internet connection and try again.';
        });
      }
      return;
    }
    _dropboxService.pushHardwareConfig(ssid: ssid, password: pass);
    // 15-second timeout if device doesn't respond
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _sending) {
        setState(() {
          _sending  = false;
          _errorMsg = 'Device did not respond. Make sure it\'s powered on and in range.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? UserTheme.nightBackground : UserTheme.dayBackground,
      appBar: UserTheme.appBarGradient(
        title: 'Connect to WiFi',
        context: context,
      ),
      body: Container(
        decoration: UserUi.pageBackground(context),
        child: SingleChildScrollView(
          padding: UserUi.listPadding(context, top: 20, bottom: 32, maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Success banner
              if (_successMsg != null) _buildSuccess(),
              if (_successMsg == null) ...[
                _buildHeader(),
                const SizedBox(height: 24),
                _buildForm(),
                const SizedBox(height: 24),
                _buildSubmitButton(),
              ],
              if (_errorMsg != null) ...[
                const SizedBox(height: 16),
                _buildError(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary;
    final secondaryText = isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Registration success banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: UserTheme.statusSuccess.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(UserTheme.radiusM),
            border: Border.all(color: UserTheme.statusSuccess.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: UserTheme.statusSuccess, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Registration Successful',
                      style: TextStyle(
                        color: UserTheme.statusSuccess,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Your device is registered. Connect it to your home WiFi below.',
                      style: TextStyle(color: secondaryText, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Connect to Your WiFi',
          style: TextStyle(
            color: primaryText,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your dropbox needs your home WiFi to communicate with the server. Enter your network credentials below.',
          style: TextStyle(color: secondaryText, height: 1.5, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildForm() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary;
    final mutedColor = isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted;
    final secondaryText = isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary;

    return UserUi.surfaceCard(
      context,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          TextField(
            controller: _ssidController,
            style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
            decoration: _inputDeco(
              label: 'WiFi Network Name (SSID)',
              hint: 'e.g. MyHomeWiFi',
              icon: Icons.wifi_rounded,
              isDark: isDark,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passController,
            obscureText: _obscurePass,
            style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
            decoration: _inputDeco(
              label: 'WiFi Password',
              hint: 'Leave blank if open network',
              icon: Icons.lock_outline_rounded,
              isDark: isDark,
            ).copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: mutedColor,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? UserTheme.nightSurface : UserTheme.daySurface,
              borderRadius: BorderRadius.circular(UserTheme.radiusS),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: UserTheme.primaryOrange, size: 17),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Server connection details are pre-configured in the device firmware. You only need to provide your WiFi credentials.',
                    style: TextStyle(color: secondaryText, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return UserUi.premiumButton(
      label: _sending ? 'Sending to device...' : 'Connect Dropbox',
      onTap: _sendConfig,
      isLoading: _sending,
      icon: Icons.send_rounded,
    );
  }

  Widget _buildSuccess() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary;
    final mutedColor = isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted;

    return UserUi.surfaceCard(
      context,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.check_circle_rounded, color: UserTheme.statusSuccess, size: 52),
          const SizedBox(height: 16),
          const Text(
            'Configuration Sent',
            style: TextStyle(
              color: UserTheme.statusSuccess,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _successMsg ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(color: primaryText, height: 1.5, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Text(
            'Returning to Dropbox Management...',
            style: TextStyle(color: mutedColor, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: UserTheme.statusError.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(UserTheme.radiusM),
        border: Border.all(color: UserTheme.statusError.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: UserTheme.statusError, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMsg!,
              style: const TextStyle(color: UserTheme.statusError, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: _sendConfig,
            child: const Text(
              'Retry',
              style: TextStyle(color: UserTheme.statusError, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco({
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
  }) {
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.1);
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
        fontSize: 13,
      ),
      hintText: hint,
      hintStyle: TextStyle(
        color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
        fontSize: 13,
      ),
      prefixIcon: Icon(
        icon,
        size: 20,
        color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
      ),
      filled: true,
      fillColor: isDark ? UserTheme.nightSurface : UserTheme.daySurface,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UserTheme.radiusM),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UserTheme.radiusM),
        borderSide: const BorderSide(color: UserTheme.primaryOrange, width: 1.5),
      ),
    );
  }
}
