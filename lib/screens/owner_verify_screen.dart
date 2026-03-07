import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/websocket_service.dart';

/// Owner Verification Screen
///
/// Opens a full-screen camera scanner. The user scans the one-time QR
/// displayed on the hardware LCD. The token is sent to the backend, which
/// validates it and relays the result to the ESP32.
class OwnerVerifyScreen extends StatefulWidget {
  const OwnerVerifyScreen({super.key});

  @override
  State<OwnerVerifyScreen> createState() => _OwnerVerifyScreenState();
}

class _OwnerVerifyScreenState extends State<OwnerVerifyScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final WebSocketService _ws = WebSocketService();

  bool _scanned  = false;   // prevents double-processing
  bool _waiting  = false;   // shows spinner while waiting for server ack
  bool _timedOut = false;   // ack never arrived
  String _statusMsg = '';
  StreamSubscription<Map<String, dynamic>>? _ackSub;
  Timer? _ackTimer;         // FIX: timeout if ownerVerifyAck never arrives

  @override
  void initState() {
    super.initState();
    _ackSub = _ws.ownerVerifyAck.listen((data) {
      _ackTimer?.cancel();
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
  }

  @override
  void dispose() {
    _ackTimer?.cancel();
    _ackSub?.cancel();
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned || _waiting) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final token = barcode.rawValue!;
    if (!token.startsWith('OWN-')) return;   // ignore non-owner QR codes

    setState(() {
      _scanned   = true;
      _waiting   = true;
      _timedOut  = false;
      _statusMsg = 'Verifying...';
    });
    _scannerController.stop();
    _ws.emitVerifyOwnerQR(token);

    // FIX: If backend never sends ownerVerifyAck (token expired, network drop)
    // show a recoverable error after 10 seconds instead of hanging forever.
    _ackTimer = Timer(const Duration(seconds: 65), () {
      if (!mounted || !_waiting) return;
      setState(() {
        _waiting  = false;
        _timedOut = true;
        _statusMsg = 'No response from server.\nThe QR may have expired.';
      });
    });
  }

  void _reset() {
    _ackTimer?.cancel();
    setState(() {
      _scanned   = false;
      _waiting   = false;
      _timedOut  = false;
      _statusMsg = '';
    });
    _scannerController.start();
  }

  @override
  Widget build(BuildContext context) {
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
          // Live camera view (only when not processing)
          if (!_waiting && !_scanned)
            MobileScanner(
              controller: _scannerController,
              onDetect: _onDetect,
            ),

          // Scan frame overlay
          if (!_waiting && !_scanned)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.cyanAccent, width: 3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Point camera at the QR code\non the dropbox LCD screen',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),

          // Status / result overlay
          if (_waiting || _scanned)
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
                    // Spinner while waiting
                    if (_waiting)
                      const CircularProgressIndicator(),

                    // Result icon
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

                    // Timeout icon
                    if (_timedOut)
                      const Icon(Icons.wifi_off, size: 64, color: Colors.orange),

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

                    // FIX: Offer retry if timed out, so user is never stuck
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
  }}
