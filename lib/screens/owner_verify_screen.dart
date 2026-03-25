import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/websocket_service.dart';

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
        _statusMsg = approved ? 'Access Granted ✓' : 'Access Denied ✗';
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
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.grey[50], // Light background
      appBar: AppBar(
        title: const Text('Verify Owner Access'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Live camera view
          if (!_waiting && !_scanned && !_timedOut && !_manualEntry)
            _isMobile 
                ? MobileScanner(
                    controller: _scannerController,
                    onDetect: _onDetect,
                  )
                : _buildMockScanner(),

          // Scan frame + countdown overlay
          if (!_waiting && !_scanned && !_timedOut && !_manualEntry)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(
                        // Orange primary normally, Red when <= 10s
                        color: _countdown <= 10 ? Colors.redAccent : primaryColor,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Point camera at the QR code\non the dropbox LCD screen',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Feature #5: Countdown pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _countdown <= 10
                          ? Colors.redAccent.withOpacity(0.9)
                          : Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Expires in ${_countdown}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  // Feature #6: Toggle to Manual Entry
                  ElevatedButton.icon(
                    onPressed: () {
                      _scannerController.stop();
                      setState(() => _manualEntry = true);
                    },
                    icon: const Icon(Icons.dialpad, size: 20),
                    label: const Text('Enter PIN Manually', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                  ),
                ],
              ),
            ),

          // Feature #6: Manual PIN Entry View
          if (!_waiting && !_scanned && !_timedOut && _manualEntry)
            Center(
               child: Container(
                 margin: const EdgeInsets.all(32),
                 padding: const EdgeInsets.all(32),
                 decoration: BoxDecoration(
                   color: Colors.white,
                   borderRadius: BorderRadius.circular(24),
                   boxShadow: [
                     BoxShadow(
                       color: Colors.black.withOpacity(0.05),
                       blurRadius: 15,
                       offset: const Offset(0, 5),
                     )
                   ],
                 ),
                 child: Column(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                     Icon(Icons.dialpad, size: 48, color: primaryColor),
                     const SizedBox(height: 16),
                     const Text('Enter Code Manually', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                     const SizedBox(height: 8),
                     const Text('Check the dropbox LCD screen for the full code or PIN', style: TextStyle(color: Colors.black54), textAlign: TextAlign.center),
                     const SizedBox(height: 24),
                     TextField(
                       controller: _pinController,
                       keyboardType: TextInputType.text,
                       textCapitalization: TextCapitalization.characters,
                       textAlign: TextAlign.center,
                       style: const TextStyle(fontSize: 24, letterSpacing: 4, fontWeight: FontWeight.bold, color: Colors.black87),
                       decoration: InputDecoration(
                         hintText: 'e.g. OWN-123456',
                         hintStyle: const TextStyle(fontSize: 16, letterSpacing: 1, color: Colors.black26),
                         border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                         focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryColor, width: 2)),
                         filled: true,
                         fillColor: Colors.grey[50],
                         counterText: '',
                       ),
                       onSubmitted: (_) => _submitPin(),
                     ),
                     const SizedBox(height: 24),
                     Row(
                       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                       children: [
                         TextButton(
                           onPressed: () {
                             setState(() => _manualEntry = false);
                             _scannerController.start();
                           },
                           style: TextButton.styleFrom(foregroundColor: Colors.black54),
                           child: const Text('Back to Scanner'),
                         ),
                         ElevatedButton(
                           onPressed: _submitPin,
                           style: ElevatedButton.styleFrom(
                             backgroundColor: primaryColor,
                             foregroundColor: Colors.white,
                             elevation: 0,
                             padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                           ),
                           child: const Text('Verify', style: TextStyle(fontWeight: FontWeight.bold)),
                         ),
                       ],
                     ),
                     const SizedBox(height: 20),
                     Text(
                       'Expires in ${_countdown}s',
                       style: TextStyle(
                         color: _countdown <= 10 ? Colors.red : Colors.grey,
                         fontWeight: FontWeight.bold,
                         fontSize: 13,
                       ),
                     ),
                   ],
                 ),
               ),
            ),

          // Status / result overlay
          if (_waiting || _scanned || _timedOut)
            Center(
              child: Container(
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                     BoxShadow(
                       color: Colors.black.withOpacity(0.05),
                       blurRadius: 15,
                       offset: const Offset(0, 5),
                     )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_waiting) CircularProgressIndicator(color: primaryColor),

                    if (!_waiting && _statusMsg.isNotEmpty && !_timedOut)
                      Icon(
                        _statusMsg.contains('Granted')
                            ? Icons.check_circle
                            : Icons.cancel,
                        size: 64,
                        color: _statusMsg.contains('Granted')
                            ? Colors.green
                            : Colors.red,
                      ),

                    if (_timedOut)
                      const Icon(Icons.timer_off, size: 64, color: Colors.orange),

                    const SizedBox(height: 20),
                    Text(
                      _statusMsg,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _statusMsg.contains('Granted')
                            ? Colors.green[800]
                            : _statusMsg.contains('Denied')
                                ? Colors.red[800]
                                : Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    if (_timedOut) ...[
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _reset,
                            icon: const Icon(Icons.refresh, size: 20),
                            label: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                               backgroundColor: primaryColor,
                               foregroundColor: Colors.white,
                               elevation: 0,
                               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: TextButton.styleFrom(foregroundColor: Colors.black54),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMockScanner() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off, color: Colors.white54, size: 48),
            SizedBox(height: 16),
            Text(
              'Camera Disabled on Windows\nUse manual entry/serial bypass to demo',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
