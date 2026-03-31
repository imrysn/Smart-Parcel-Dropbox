import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/dropbox_service.dart';
import '../services/auth_service.dart';
import '../services/service_locator.dart';
import 'hardware_config_screen.dart';

/// Hardware Registration Screen
///
/// Guides the user through scanning the QR code displayed on the device LCD
/// (or manually entering the code) to register their Smart Parcel Dropbox.
class HardwareRegistrationScreen extends StatefulWidget {
  const HardwareRegistrationScreen({super.key});

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

  MobileScannerController? _scannerController;
  StreamSubscription? _registeredSub;
  StreamSubscription? _failedSub;

  bool _scanning     = false;
  bool _processing   = false;
  bool _showManual   = false;
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
    if (!_isMobile) {
      _showManual = true;
    }
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _registeredSub?.cancel();
    _failedSub?.cancel();
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onRegistered(Map<String, dynamic> data) {
    if (!mounted) return;
    _scannerController?.stop();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HardwareConfigScreen(deviceId: data['deviceId'] ?? ''),
      ),
    );
  }

  void _onFailed(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() {
      _processing = false;
      _errorMsg = data['reason'] == 'invalid_or_expired_token'
          ? 'Invalid or expired code. Please refresh the QR on your device.'
          : 'Registration failed. Please try again.';
    });
  }

  Future<void> _submitToken(String token) async {
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
    final userId = await _authService.currentUserId ?? '';
    final name   = _nameController.text.trim().isEmpty
        ? 'My Smart Parcel Dropbox'
        : _nameController.text.trim();
    _dropboxService.registerDevice(trimmed, userId, name);
    _scannerController?.stop();
  }

  void _startScanner() {
    setState(() {
      _scanning  = true;
      _errorMsg  = null;
    });
    if (_isMobile) {
      _scannerController = MobileScannerController();
    }
  }

  void _stopScanner() {
    _scannerController?.dispose();
    _scannerController = null;
    setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Register Dropbox',
        ),
      ),
      body: _processing
          ? _buildLoading(primaryColor)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _buildInstructions(primaryColor),
                  const SizedBox(height: 28),
                  _buildNameField(primaryColor),
                  const SizedBox(height: 24),
                  if (!_scanning) _buildActions(primaryColor),
                  if (_scanning) _buildScanner(),
                  const SizedBox(height: 20),
                  if (_showManual && !_scanning) _buildManualEntry(primaryColor),
                  if (_errorMsg != null) _buildError(),
                ],
              ),
            ),
    );
  }

  Widget _buildLoading(Color primaryColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: primaryColor),
          const SizedBox(height: 20),
          const Text(
            'Registering device…',
            style: TextStyle(color: Colors.black54, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructions(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📦 How to Register',
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          _Step(n: '1', text: 'Power on your Smart Parcel Dropbox.', color: primaryColor),
          _Step(n: '2', text: 'Press BTN1 on the device to enter Registration Mode.', color: primaryColor),
          _Step(n: '3', text: 'A QR code and a 6-digit code will appear on the LCD screen.', color: primaryColor),
          _Step(
            n: '4', 
            text: _isMobile 
                ? 'Tap "Scan QR Code" below and scan the code shown on the device.'
                : 'Enter the 6-digit code shown on the device below.', 
            color: primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildNameField(Color primaryColor) {
    return TextField(
      controller: _nameController,
      style: const TextStyle(color: Colors.black87),
      decoration: InputDecoration(
        labelText: 'Device Name (optional)',
        labelStyle: const TextStyle(color: Colors.black54),
        hintText: 'e.g. Living Room Dropbox',
        hintStyle: const TextStyle(color: Colors.black38),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor),
        ),
        prefixIcon: const Icon(Icons.label_outline, color: Colors.black38),
      ),
    );
  }

  Widget _buildActions(Color primaryColor) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: _startScanner,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text(
              'Scan QR Code',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => setState(() => _showManual = !_showManual),
          child: Text(
            _showManual ? 'Hide manual entry' : '— or enter code manually —',
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      ],
    );
  }

  Widget _buildScanner() {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 280,
            child: _isMobile && _scannerController != null
                ? MobileScanner(
                    controller: _scannerController!,
                    onDetect: (capture) {
                      final barcode = capture.barcodes.firstOrNull;
                      if (barcode?.rawValue != null) {
                        _submitToken(barcode!.rawValue!);
                      }
                    },
                  )
                : _buildMockScanner(),
          ),
        ),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: _stopScanner,
          icon: const Icon(Icons.close, color: Colors.red),
          label: const Text('Cancel Scan',
              style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  Widget _buildMockScanner() {
    return Container(
      color: Colors.black87,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off, color: Colors.white54, size: 48),
            SizedBox(height: 16),
            Text(
              'Camera Disabled on Windows\nUse manual entry to demo registration',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualEntry(Color primaryColor) {
    return Column(
      children: [
        TextField(
          controller: _codeController,
          style: const TextStyle(
              color: Colors.black87, letterSpacing: 4, fontSize: 18),
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: 'Code shown on device LCD',
            labelStyle: const TextStyle(color: Colors.black54),
            hintText: 'e.g. SPDB-REG-482913',
            hintStyle: const TextStyle(
                color: Colors.black26, letterSpacing: 1, fontSize: 14),
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: primaryColor),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () => _submitToken(_codeController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor.withOpacity(0.1),
              foregroundColor: primaryColor,
              elevation: 0,
              side: BorderSide(color: primaryColor),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'Submit Code',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMsg!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

/// Numbered step widget for the instruction card.
class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text, required this.color});
  final String n;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(n,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: Colors.black87, height: 1.4))),
        ],
      ),
    );
  }
}
