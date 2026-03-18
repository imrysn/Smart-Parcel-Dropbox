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
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a 6-digit PIN')),
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
    
    // The server verifies 'token', so we prepend 'OWN-' expected format
    _ws.emitVerifyOwnerQR('OWN-$pin');

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
    // Feature #8: Guard against unsupported platforms (Windows desktop)
    if (!_isMobile) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Verify Owner Access'),
          centerTitle: true,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smartphone, size: 80, color: Colors.white38),
                SizedBox(height: 24),
                Text(
                  'Camera scanning is only available on Android or iOS.\n\n'
                  'Please open the Smart Parcel app on your phone to verify access.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Verify Owner Access'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Live camera view
          if (!_waiting && !_scanned && !_timedOut && !_manualEntry)
            MobileScanner(
              controller: _scannerController,
              onDetect: _onDetect,
            ),

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
                        // Feature #5: frame turns orange in last 10s
                        color: _countdown <= 10 ? Colors.orange : Colors.cyanAccent,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Point camera at the QR code\non the dropbox LCD screen',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  // Feature #5: Countdown pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: _countdown <= 10
                          ? Colors.orange.withOpacity(0.85)
                          : Colors.white12,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Expires in ${_countdown}s',
                      style: TextStyle(
                        color: _countdown <= 10 ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Feature #6: Toggle to Manual Entry
                  TextButton.icon(
                    onPressed: () {
                      _scannerController.stop();
                      setState(() => _manualEntry = true);
                    },
                    icon: const Icon(Icons.dialpad),
                    label: const Text('Enter PIN Manually'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
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
                   borderRadius: BorderRadius.circular(20),
                 ),
                 child: Column(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                     const Icon(Icons.dialpad, size: 48, color: Colors.blueAccent),
                     const SizedBox(height: 16),
                     const Text('Enter 6-Digit PIN', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                     const SizedBox(height: 8),
                     const Text('Check the dropbox LCD screen for the PIN', style: TextStyle(color: Colors.black54), textAlign: TextAlign.center),
                     const SizedBox(height: 24),
                     TextField(
                       controller: _pinController,
                       keyboardType: TextInputType.number,
                       maxLength: 6,
                       textAlign: TextAlign.center,
                       style: const TextStyle(fontSize: 24, letterSpacing: 8),
                       decoration: const InputDecoration(border: OutlineInputBorder()),
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
                           child: const Text('Back to Scanner'),
                         ),
                         ElevatedButton(
                           onPressed: _submitPin,
                           child: const Text('Verify'),
                         ),
                       ],
                     ),
                     const SizedBox(height: 16),
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
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_waiting) const CircularProgressIndicator(),

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

                    const SizedBox(height: 16),
                    Text(
                      _statusMsg,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _statusMsg.contains('Granted')
                            ? Colors.green[800]
                            : _statusMsg.contains('Denied')
                                ? Colors.red[800]
                                : Colors.grey[800],
                      ),
                      textAlign: TextAlign.center,
                    ),

                    if (_timedOut) ...[
                      const SizedBox(height: 20),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _reset,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try Again'),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
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
}
