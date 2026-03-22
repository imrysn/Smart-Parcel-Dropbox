import 'dart:async';
import 'package:flutter/material.dart';
import '../services/dropbox_service.dart';
import '../services/service_locator.dart';

/// Hardware Config Screen
///
/// Shown after successful device registration.
/// Collects only WiFi SSID + Password from the user, then pushes the
/// credentials to the device via Socket.IO (pushHardwareConfig event).
/// Server Host and Port are pre-baked into the firmware — the user
/// never needs to know or configure those values.
class HardwareConfigScreen extends StatefulWidget {
  final String deviceId;
  const HardwareConfigScreen({super.key, required this.deviceId});

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
    // Navigate back to Dropbox Management after a moment
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    });
  }

  void _sendConfig() {
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
    _dropboxService.pushHardwareConfig(ssid: ssid, password: pass);
    // 15-second timeout if device doesn't respond
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
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.grey[50], // Light background
      appBar: AppBar(
        title: const Text(
          'Connect to WiFi',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Success banner
            if (_successMsg != null) _buildSuccess(),
            if (_successMsg == null) ...[
              _buildHeader(),
              const SizedBox(height: 28),
              _buildForm(primaryColor),
              const SizedBox(height: 28),
              _buildSubmitButton(primaryColor),
            ],
            if (_errorMsg != null) ...[
              const SizedBox(height: 16),
              _buildError(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Registration success banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.withOpacity(0.4)),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registration Successful! 🎉',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Your device is registered. Now let\'s connect it to your WiFi.',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          '⚙️  Connect to Your WiFi',
          style: TextStyle(
              color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your dropbox needs your home WiFi to communicate with the server. '
          'Enter your network credentials below.',
          style: TextStyle(color: Colors.black54, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildForm(Color primaryColor) {
    return Column(
      children: [
        // SSID field
        TextField(
          controller: _ssidController,
          style: const TextStyle(color: Colors.black87),
          decoration: _inputDeco(
            label: 'WiFi Network Name (SSID)',
            hint: 'e.g. MyHomeWiFi',
            icon: Icons.wifi,
            primaryColor: primaryColor,
          ),
        ),
        const SizedBox(height: 16),
        // Password field
        TextField(
          controller: _passController,
          obscureText: _obscurePass,
          style: const TextStyle(color: Colors.black87),
          decoration: _inputDeco(
            label: 'WiFi Password',
            hint: 'Leave blank if open network',
            icon: Icons.lock_outline,
            primaryColor: primaryColor,
          ).copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePass ? Icons.visibility_off : Icons.visibility,
                color: Colors.black38,
              ),
              onPressed: () =>
                  setState(() => _obscurePass = !_obscurePass),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Server connection details are pre-configured in the device firmware. '
                  'You only need to provide your WiFi credentials.',
                  style: TextStyle(color: Colors.orange, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton(Color primaryColor) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _sending ? null : _sendConfig,
        icon: _sending
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.send_rounded),
        label: Text(
          _sending ? 'Sending to device…' : 'Connect Dropbox',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: primaryColor.withOpacity(0.6),
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 56),
          const SizedBox(height: 16),
          const Text(
            'Configuration Sent!',
            style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            _successMsg ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black87, height: 1.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'Returning to Dropbox Management…',
            style: TextStyle(color: Colors.black38, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
              child: Text(_errorMsg!,
                  style: const TextStyle(color: Colors.red))),
          TextButton(
            onPressed: _sendConfig,
            child: const Text('Retry',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco({
    required String label,
    required String hint,
    required IconData icon,
    required Color primaryColor,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.black54),
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black26),
      prefixIcon: Icon(icon, color: Colors.black38),
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
    );
  }
}
