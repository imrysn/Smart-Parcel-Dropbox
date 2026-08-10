import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/dropbox_service.dart';
import '../services/auth_service.dart';
import '../services/service_locator.dart';
import '../config/user_theme.dart';
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

  final MobileScannerController _scannerController = MobileScannerController();
  StreamSubscription? _registeredSub;
  StreamSubscription? _failedSub;

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
    _scannerController.dispose();
    _registeredSub?.cancel();
    _failedSub?.cancel();
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onRegistered(Map<String, dynamic> data) {
    if (!mounted) return;
    _scannerController.stop();
    
    final bool alreadyConnected = data['alreadyConnected'] == true;

    if (alreadyConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device registered and online! Setup complete.'),
          backgroundColor: Colors.green,
        ),
      );
      // Go back to home or dashboard
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HardwareConfigScreen(deviceId: data['deviceId'] ?? ''),
        ),
      );
    }
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
    final userId = await _authService.currentUserId ?? '';
    final name   = _nameController.text.trim().isEmpty
        ? 'My Smart Parcel Dropbox'
        : _nameController.text.trim();
    _dropboxService.registerDevice(trimmed, userId, name);
    _scannerController.stop();
  }

  void _resetScanner() {
    setState(() {
      _processing = false;
      _errorMsg = null;
      _showManual = false;
      _nameController.text = 'My Smart Parcel Dropbox';
    });
    _scannerController.start();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = UserTheme.primaryOrange;

    return Scaffold(
      backgroundColor: Colors.grey[50], // Match OwnerVerify light background
      extendBodyBehindAppBar: true,     // Let scanner fill full screen
      appBar: AppBar(
        backgroundColor: Colors.transparent, // Floating glassy app bar
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Register Dropbox', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // 1. Live camera background
          if (!_processing && !_showManual)
            _isMobile 
                ? MobileScanner(
                    controller: _scannerController,
                    onDetect: (capture) {
                      final barcode = capture.barcodes.firstOrNull;
                      if (barcode?.rawValue != null) _submitToken(barcode!.rawValue!);
                    },
                  )
                : _buildMockScanner(),

          // 2. Scan frame + overlay elements (Same reticle as Verify Owner)
          if (!_processing && !_showManual)
            SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 240,
                            height: 240,
                            decoration: BoxDecoration(
                              border: Border.all(color: primaryColor, width: 3),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, spreadRadius: 2),
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
                          if (_errorMsg != null)
                            Container(
                              margin: const EdgeInsets.only(top: 16),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _errorMsg!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 14),
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
                      padding: const EdgeInsets.only(bottom: 40, left: 24, right: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                              ],
                            ),
                            child: _buildNameField(primaryColor),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () {
                              _scannerController.stop();
                              setState(() => _showManual = true);
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
                  ),
                ],
              ),
            ),

          // 3. Manual Entry View
          if (!_processing && _showManual)
            Center(
               child: SingleChildScrollView(
                 child: Container(
                   margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
                   padding: const EdgeInsets.all(24),
                   decoration: BoxDecoration(
                     color: Colors.white,
                     borderRadius: BorderRadius.circular(24),
                     boxShadow: [
                       BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))
                     ],
                   ),
                   child: Column(
                     mainAxisSize: MainAxisSize.min,
                     children: [
                     Icon(Icons.dialpad, size: 48, color: primaryColor),
                     const SizedBox(height: 16),
                     const Text('Enter Code Manually', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
                     const SizedBox(height: 8),
                     const Text('Check the dropbox LCD for the registration PIN', style: TextStyle(color: Colors.black54), textAlign: TextAlign.center),
                     const SizedBox(height: 24),
                     _buildNameField(primaryColor),
                     const SizedBox(height: 16),
                     TextField(
                       controller: _codeController,
                       keyboardType: TextInputType.text,
                       textCapitalization: TextCapitalization.characters,
                       textAlign: TextAlign.center,
                       style: const TextStyle(fontSize: 20, letterSpacing: 3, fontWeight: FontWeight.bold, color: Colors.black87),
                       decoration: InputDecoration(
                         hintText: 'e.g. SPDB-REG-123',
                         hintStyle: const TextStyle(fontSize: 14, letterSpacing: 1, color: Colors.black26),
                         border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                         focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: primaryColor, width: 2)),
                         filled: true,
                         fillColor: Colors.grey[50],
                         counterText: '',
                       ),
                       onSubmitted: (_) => _submitToken(_codeController.text),
                     ),
                     const SizedBox(height: 24),
                     Row(
                       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                       children: [
                         TextButton(
                           onPressed: () {
                             setState(() => _showManual = false);
                             _scannerController.start();
                           },
                           style: TextButton.styleFrom(foregroundColor: Colors.black54),
                           child: const Text('Back to Scanner'),
                         ),
                         ElevatedButton(
                           onPressed: () => _submitToken(_codeController.text),
                           style: ElevatedButton.styleFrom(
                             backgroundColor: primaryColor,
                             foregroundColor: Colors.white,
                             elevation: 0,
                             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                           ),
                           child: const Text('Register', style: TextStyle(fontWeight: FontWeight.bold)),
                         ),
                       ],
                     ),
                     if (_errorMsg != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(_errorMsg!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                        )
                   ],
                 ),
               ),
               ),
            ),

          // 4. Processing overlay
          if (_processing) _buildLoading(primaryColor),
        ],
      ),
    );
  }

  Widget _buildLoading(Color primaryColor) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(UserTheme.radiusL),
          boxShadow: [
            BoxShadow(
              color: UserTheme.primaryOrange.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primaryColor),
            const SizedBox(height: 24),
            const Text(
              'Registering device…',
              style: TextStyle(
                color: UserTheme.textPrimary, 
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
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

}
