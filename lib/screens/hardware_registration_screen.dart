import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/dropbox_service.dart';
import '../services/auth_service.dart';
import '../services/service_locator.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import 'hardware_config_screen.dart';
import 'home_screen.dart';

/// Hardware Registration Screen
///
/// Guides the user through scanning the QR code displayed on the device LCD
/// (or manually entering the code) to register their Smart Parcel Dropbox.
class HardwareRegistrationScreen extends StatefulWidget {
  final bool canSkipToHome;
  const HardwareRegistrationScreen({super.key, this.canSkipToHome = false});

  @override
  State<HardwareRegistrationScreen> createState() =>
      _HardwareRegistrationScreenState();
}

class _HardwareRegistrationScreenState
    extends State<HardwareRegistrationScreen> {
  final _dropboxService = getIt<DropboxService>();
  final _authService    = getIt<AuthService>();
  final _nameController = TextEditingController(text: 'My Smart Parcel Dropbox');
  final _codeController = TextEditingController();

  final MobileScannerController _scannerController = MobileScannerController();
  StreamSubscription? _registeredSub;
  StreamSubscription? _failedSub;
  Timer? _pairingTimeoutTimer;

  bool _processing = false;
  bool _hasCompleted = false;
  bool _showManual = false;
  String? _errorMsg;

  bool get _isMobile {
    if (kIsWeb) return false;
    try { return Platform.isAndroid || Platform.isIOS; }
    catch (_) { return false; }
  }

  @override
  void initState() {
    super.initState();
    _registeredSub = _dropboxService.deviceRegisteredStream.listen(_onRegistered);
    _failedSub     = _dropboxService.deviceRegistrationFailedStream.listen(_onFailed);
    // Ensure WebSocket connects immediately when arriving directly after signup.
    _dropboxService.ensureSocketConnected();
    if (!_isMobile) {
      _showManual = true;
    }
  }

  @override
  void dispose() {
    _pairingTimeoutTimer?.cancel();
    _scannerController.dispose();
    _registeredSub?.cancel();
    _failedSub?.cancel();
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onRegistered(Map<String, dynamic> data) {
    if (!mounted || _hasCompleted) return;
    _hasCompleted = true;
    _pairingTimeoutTimer?.cancel();
    _scannerController.stop();

    final bool alreadyConnected = data['alreadyConnected'] == true;
    final String deviceId =
        (data['deviceId'] ?? (data['dropbox'] is Map ? (data['dropbox'] as Map)['deviceId'] : '') ?? '')
            .toString();

    if (alreadyConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device registered and online! Setup complete.'),
          backgroundColor: UserTheme.statusSuccess,
        ),
      );
      if (widget.canSkipToHome) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      } else {
        Navigator.of(context).pop();
      }
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HardwareConfigScreen(
            deviceId: deviceId,
            goToHomeAfter: widget.canSkipToHome,
          ),
        ),
      );
    }
  }

  void _goToHome() {
    _pairingTimeoutTimer?.cancel();
    _scannerController.stop();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  void _onFailed(Map<String, dynamic> data) {
    if (!mounted || _hasCompleted) return;
    _pairingTimeoutTimer?.cancel();
    final customMsg = data['message']?.toString();
    setState(() {
      _processing = false;
      if (customMsg != null && customMsg.isNotEmpty) {
        _errorMsg = customMsg;
      } else {
        _errorMsg = data['reason'] == 'invalid_or_expired_token'
            ? 'Invalid or expired code. Please refresh the QR on your device.'
            : 'Registration failed. Please try again.';
      }
    });
    if (!_showManual && _isMobile) {
      _scannerController.start();
    }
  }

  Future<void> _submitToken(String token) async {
    if (_processing) return;
    String trimmed = token.trim().toUpperCase();
    if (trimmed.isEmpty) return;

    // Gracefully handle if user only types the 6-digit PIN shown on LCD
    if (trimmed.length == 6 && int.tryParse(trimmed) != null) {
      trimmed = 'SPDB-REG-$trimmed';
    }

    setState(() {
      _processing = true;
      _errorMsg   = null;
    });
    _scannerController.stop();

    final userId = await _authService.currentUserId ?? '';
    if (userId.isEmpty) {
      _onFailed({'message': 'Session expired. Please sign in again.'});
      return;
    }

    final name = _nameController.text.trim().isEmpty
        ? 'My Smart Parcel Dropbox'
        : _nameController.text.trim();

    if (!_dropboxService.isSocketConnected) {
      await _dropboxService.ensureSocketConnected();
    }

    if (_dropboxService.isSocketConnected) {
      _dropboxService.registerDevice(trimmed, userId, name);
      _pairingTimeoutTimer?.cancel();
      _pairingTimeoutTimer = Timer(const Duration(seconds: 12), () {
        if (!mounted || _hasCompleted || !_processing) return;
        _onFailed({
          'message': 'Pairing timed out waiting for server response. Please try again.',
        });
      });
      return;
    }

    // Use authenticated REST pairing when socket handshake hasn't finished yet (e.g. post-signup).
    try {
      final result = await _dropboxService.claimDevice(
        token: trimmed,
        deviceName: name,
      );
      _onRegistered(result);
    } catch (e) {
      _onFailed({'message': e.toString()});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary;
    final secondaryText = isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary;
    final mutedText = isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted;
    final cardColor = isDark ? UserTheme.nightCard : UserTheme.dayCard;
    final surfaceColor = isDark ? UserTheme.nightSurface : UserTheme.daySurface;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);
    final isCameraView = !_processing && !_showManual;
    final scanSize = (MediaQuery.sizeOf(context).shortestSide * 0.6).clamp(170.0, 240.0);

    return Scaffold(
      backgroundColor: isDark ? UserTheme.nightBackground : UserTheme.dayBackground,
      extendBodyBehindAppBar: isCameraView,
      appBar: isCameraView
          ? AppBar(
              backgroundColor: Colors.black.withValues(alpha: 0.35),
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text(
                'Register Dropbox',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
              ),
              centerTitle: true,
              actions: [
                if (widget.canSkipToHome)
                  TextButton(
                    onPressed: _goToHome,
                    child: const Text(
                      'Later',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            )
          : UserTheme.appBarGradient(
              title: 'Register Dropbox',
              context: context,
              actions: [
                if (widget.canSkipToHome)
                  TextButton(
                    onPressed: _goToHome,
                    child: const Text(
                      'Later',
                      style: TextStyle(color: UserTheme.primaryOrange, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
      body: Stack(
        children: [
          // 1. Live camera background
          if (isCameraView)
            _isMobile
                ? MobileScanner(
                    controller: _scannerController,
                    onDetect: (capture) {
                      final barcode = capture.barcodes.firstOrNull;
                      if (barcode?.rawValue != null) _submitToken(barcode!.rawValue!);
                    },
                  )
                : _buildMockScanner(),

          // 2. Scan frame + overlay elements
          if (isCameraView)
            SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: scanSize,
                            height: scanSize,
                            decoration: BoxDecoration(
                              border: Border.all(color: UserTheme.primaryOrange, width: 2.5),
                              borderRadius: BorderRadius.circular(UserTheme.radiusL),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(UserTheme.radiusS),
                            ),
                            child: const Text(
                              'Scan the QR code on the dropbox LCD\nor the primary owner\'s invite screen',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                            ),
                          ),
                          if (_errorMsg != null)
                            Container(
                              margin: const EdgeInsets.only(top: 16),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: UserTheme.statusError.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(UserTheme.radiusS),
                              ),
                              child: Text(
                                _errorMsg!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Device Name & Manual Fallback Button
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: 24,
                        left: UserUi.horizontalGutter(context),
                        right: UserUi.horizontalGutter(context),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            UserUi.surfaceCard(
                              context,
                              padding: const EdgeInsets.all(14),
                              child: _buildNameField(isDark),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: () {
                                _scannerController.stop();
                                setState(() => _showManual = true);
                              },
                              icon: const Icon(Icons.dialpad_rounded, size: 18),
                              label: const Text(
                                'Enter PIN Manually',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: cardColor,
                                foregroundColor: primaryText,
                                elevation: 2,
                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                  side: BorderSide(color: borderColor),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 3. Manual Entry View
          if (!_processing && _showManual)
            Container(
              decoration: UserUi.pageBackground(context),
              child: Center(
                child: SingleChildScrollView(
                  padding: UserUi.listPadding(context, top: 24, bottom: 24, maxWidth: 460),
                  child: UserUi.surfaceCard(
                    context,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.dialpad_rounded, size: 40, color: UserTheme.primaryOrange),
                        const SizedBox(height: 14),
                        Text(
                          'Enter Code Manually',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: primaryText,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Check the dropbox LCD or owner invite for the 6-digit PIN',
                          style: TextStyle(color: secondaryText, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 22),
                        _buildNameField(isDark),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.characters,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 19,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w800,
                            color: primaryText,
                          ),
                          decoration: InputDecoration(
                            hintText: 'e.g. 482913 or SPDB-REG-482913',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              letterSpacing: 1,
                              color: mutedText,
                              fontWeight: FontWeight.w500,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(UserTheme.radiusM),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(UserTheme.radiusM),
                              borderSide: const BorderSide(color: UserTheme.primaryOrange, width: 1.5),
                            ),
                            filled: true,
                            fillColor: surfaceColor,
                            counterText: '',
                          ),
                          onSubmitted: (_) => _submitToken(_codeController.text),
                        ),
                        const SizedBox(height: 22),
                        UserUi.premiumButton(
                          label: 'Register Dropbox',
                          onTap: () => _submitToken(_codeController.text),
                          icon: Icons.check_rounded,
                        ),
                        if (widget.canSkipToHome) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _goToHome,
                            style: TextButton.styleFrom(foregroundColor: secondaryText),
                            child: const Text(
                              'Set up later',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                        if (_isMobile) ...[
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: () {
                              setState(() => _showManual = false);
                              _scannerController.start();
                            },
                            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                            label: const Text('Back to Scanner', style: TextStyle(fontWeight: FontWeight.w600)),
                            style: TextButton.styleFrom(foregroundColor: secondaryText),
                          ),
                        ],
                        if (_errorMsg != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(
                              _errorMsg!,
                              style: const TextStyle(color: UserTheme.statusError, fontSize: 13, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 4. Processing overlay
          if (_processing) _buildLoading(),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: UserUi.surfaceCard(
        context,
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: UserTheme.primaryOrange),
            const SizedBox(height: 20),
            Text(
              'Registering device...',
              style: TextStyle(
                color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameField(bool isDark) {
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.08);
    return TextField(
      controller: _nameController,
      style: TextStyle(
        color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: 'Device Name (optional)',
        labelStyle: TextStyle(
          color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
          fontSize: 13,
        ),
        hintText: 'e.g. Living Room Dropbox',
        hintStyle: TextStyle(
          color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
          fontSize: 13,
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
        prefixIcon: Icon(
          Icons.label_outline_rounded,
          size: 20,
          color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
        ),
      ),
    );
  }

  Widget _buildMockScanner() {
    return Container(
      color: UserTheme.nightBackground,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off_outlined, color: Colors.white.withValues(alpha: 0.5), size: 44),
            const SizedBox(height: 14),
            Text(
              'Camera preview unavailable on this device.\nUse manual PIN entry below to register.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
