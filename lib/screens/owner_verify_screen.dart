import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../config/user_theme.dart';
import '../services/websocket_service.dart';
import '../widgets/user_ui.dart';

/// Owner Verification Screen
///
/// Opens a full-screen camera scanner. The user scans the one-time QR
/// displayed on the hardware LCD. The token is sent to the backend, which
/// validates it and relays the result to the ESP32.
///
/// Feature #5: Live 60s countdown timer.
/// Feature #8: Platform guard — shows an error on Windows desktop.
class OwnerVerifyScreen extends StatefulWidget {
  const OwnerVerifyScreen({super.key});

  @override
  State<OwnerVerifyScreen> createState() => _OwnerVerifyScreenState();
}

class _OwnerVerifyScreenState extends State<OwnerVerifyScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final WebSocketService _ws = WebSocketService();

  bool _scanned  = false;
  bool _waiting  = false;
  bool _timedOut = false;
  String _statusMsg = '';
  StreamSubscription<Map<String, dynamic>>? _ackSub;
  Timer? _ackTimer;

  // Feature #6: Manual PIN entry state
  bool _manualEntry = false;
  final TextEditingController _pinController = TextEditingController();

  // Feature #5: countdown state
  int  _countdown   = 60;
  Timer? _countdownTimer;

  /// True if this platform supports camera scanning
  bool get _isMobile {
    if (kIsWeb) return false;
    try { return Platform.isAndroid || Platform.isIOS; }
    catch (_) { return false; }
  }

  @override
  void initState() {
    super.initState();
    _ackSub = _ws.ownerVerifyAck.listen((data) {
      _ackTimer?.cancel();
      _countdownTimer?.cancel();
      final approved = data['approved'] == true;
      if (!mounted) return;
      setState(() {
        _waiting   = false;
        _timedOut  = false;
        _statusMsg = approved ? 'Access Granted' : 'Access Denied';
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).pop(approved);
      });
    });

    // Feature #5: start countdown as soon as screen opens
    if (_isMobile) _startCountdown();
  }

  void _startCountdown() {
    _countdown = 60;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _countdown = (_countdown - 1).clamp(0, 60);
      });
      if (_countdown == 0) {
        t.cancel();
        if (!_scanned) {
          setState(() {
            _timedOut = true;
            _statusMsg = 'QR code expired.\nReturn to the dropbox to try again.';
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _ackTimer?.cancel();
    _countdownTimer?.cancel();
    _ackSub?.cancel();
    _scannerController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned || _waiting) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final token = barcode.rawValue!;
    if (!token.startsWith('OWN-')) return;

    _countdownTimer?.cancel();
    setState(() {
      _scanned   = true;
      _waiting   = true;
      _timedOut  = false;
      _statusMsg = 'Verifying...';
    });
    _scannerController.stop();
    _ws.emitVerifyOwnerQR(token);

    _ackTimer = Timer(const Duration(seconds: 65), () {
      if (!mounted || !_waiting) return;
      setState(() {
        _waiting  = false;
        _timedOut = true;
        _statusMsg = 'No response from server.\nThe QR may have expired.';
      });
    });
  }

  void _submitPin() {
    String pin = _pinController.text.trim().toUpperCase();
    
    // Auto-fix if they just typed the 6 numbers
    if (pin.length == 6 && int.tryParse(pin) != null) {
      pin = 'OWN-$pin';
    }

    if (!pin.startsWith('OWN-') || pin.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 6-digit PIN or full CODE')),
      );
      return;
    }

    _countdownTimer?.cancel();
    setState(() {
      _scanned   = true;
      _waiting   = true;
      _timedOut  = false;
      _statusMsg = 'Verifying...';
    });
    
    // The server verifies 'token', so we send the exact formatted pin
    _ws.emitVerifyOwnerQR(pin);

    _ackTimer = Timer(const Duration(seconds: 65), () {
      if (!mounted || !_waiting) return;
      setState(() {
        _waiting  = false;
        _timedOut = true;
        _statusMsg = 'No response from server.\nThe PIN may have expired.';
      });
    });
  }

  void _reset() {
    _ackTimer?.cancel();
    _pinController.clear();
    setState(() {
      _scanned   = false;
      _waiting   = false;
      _timedOut  = false;
      _statusMsg = '';
      _manualEntry = false;
    });
    _scannerController.start();
    _startCountdown();
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
    final isCameraView = !_waiting && !_scanned && !_timedOut && !_manualEntry;
    final scanSize = (MediaQuery.sizeOf(context).shortestSide * 0.6).clamp(170.0, 240.0);

    return Scaffold(
      backgroundColor: isDark ? UserTheme.nightBackground : UserTheme.dayBackground,
      appBar: UserTheme.appBarGradient(
        title: 'Verify Owner Access',
        context: context,
      ),
      body: Stack(
        children: [
          // Live camera view
          if (isCameraView)
            _isMobile
                ? MobileScanner(
                    controller: _scannerController,
                    onDetect: _onDetect,
                  )
                : _buildMockScanner(),

          // Scan frame + countdown overlay
          if (isCameraView)
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: scanSize,
                      height: scanSize,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _countdown <= 10 ? UserTheme.statusError : UserTheme.primaryOrange,
                          width: 2.5,
                        ),
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
                        'Point camera at the QR code\non the dropbox LCD screen',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _countdown <= 10
                            ? UserTheme.statusError.withValues(alpha: 0.9)
                            : Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Expires in ${_countdown}s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    ElevatedButton.icon(
                      onPressed: () {
                        _scannerController.stop();
                        setState(() => _manualEntry = true);
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

          // Manual PIN Entry View
          if (!_waiting && !_scanned && !_timedOut && _manualEntry)
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
                          'Check the dropbox LCD screen for the verification PIN',
                          style: TextStyle(color: secondaryText, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: _pinController,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.characters,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w800,
                            color: primaryText,
                          ),
                          decoration: InputDecoration(
                            hintText: 'e.g. OWN-123456',
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
                          onSubmitted: (_) => _submitPin(),
                        ),
                        const SizedBox(height: 22),
                        UserUi.premiumButton(
                          label: 'Verify Access',
                          onTap: _submitPin,
                          icon: Icons.verified_user_rounded,
                        ),
                        if (_isMobile) ...[
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: () {
                              setState(() => _manualEntry = false);
                              _scannerController.start();
                            },
                            icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                            label: const Text('Back to Scanner', style: TextStyle(fontWeight: FontWeight.w600)),
                            style: TextButton.styleFrom(foregroundColor: secondaryText),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          'Expires in ${_countdown}s',
                          style: TextStyle(
                            color: _countdown <= 10 ? UserTheme.statusError : mutedText,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Status / result overlay
          if (_waiting || _scanned || _timedOut)
            Container(
              decoration: UserUi.pageBackground(context),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: EdgeInsets.all(UserUi.horizontalGutter(context)),
                    child: UserUi.surfaceCard(
                      context,
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_waiting)
                            const CircularProgressIndicator(color: UserTheme.primaryOrange),

                          if (!_waiting && _statusMsg.isNotEmpty && !_timedOut)
                            Icon(
                              _statusMsg.contains('Granted')
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              size: 56,
                              color: _statusMsg.contains('Granted')
                                  ? UserTheme.statusSuccess
                                  : UserTheme.statusError,
                            ),

                          if (_timedOut)
                            const Icon(Icons.timer_off_rounded, size: 56, color: UserTheme.primaryOrange),

                          const SizedBox(height: 18),
                          Text(
                            _statusMsg,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: _statusMsg.contains('Granted')
                                  ? UserTheme.statusSuccess
                                  : _statusMsg.contains('Denied')
                                      ? UserTheme.statusError
                                      : primaryText,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          if (_timedOut) ...[
                            const SizedBox(height: 22),
                            UserUi.premiumButton(
                              label: 'Try Again',
                              onTap: _reset,
                              icon: Icons.refresh_rounded,
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              style: TextButton.styleFrom(foregroundColor: secondaryText),
                              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
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
              'Camera preview unavailable on this device.\nUse manual PIN entry below to verify.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
