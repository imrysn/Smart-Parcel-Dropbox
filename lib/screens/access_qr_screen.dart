import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/crypto_service.dart';
import '../services/service_locator.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';

/// Access QR Screen (Phase 5: Mobile Offline Token Engine)
/// 
/// Displays a rotating, time-based cryptographic token as a QR code.
/// This allowed the hardware (ESP32) to verify the owner even if the 
/// hardware is offline, by checking the HMAC-SHA256 signature.
class AccessQrScreen extends StatefulWidget {
  const AccessQrScreen({super.key});

  @override
  State<AccessQrScreen> createState() => _AccessQrScreenState();
}

class _AccessQrScreenState extends State<AccessQrScreen> {
  final _crypto = getIt<CryptoService>();
  String? _token;
  int _secondsLeft = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refreshToken();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        final now = DateTime.now();
        _secondsLeft = 60 - (now.second % 60);
        if (_secondsLeft == 60) {
          _refreshToken();
        }
      });
    });
  }

  Future<void> _refreshToken() async {
    final newToken = await _crypto.generateRotatingToken();
    if (mounted) {
      setState(() {
        _token = newToken;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Secure Access Token', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: Container(
        width: double.infinity,
        decoration: UserUi.pageBackground(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: UserUi.glassCard(
                context,
                padding: const EdgeInsets.all(32),
                borderRadius: 32,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'OFFLINE ACCESS QR',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        fontSize: 12,
                        color: UserTheme.primaryOrange,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_token != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: QrImageView(
                          data: _token!,
                          version: QrVersions.auto,
                          size: 240.0,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Colors.black,
                          ),
                        ),
                      )
                    else
                      const SizedBox(
                        height: 240,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.timer_outlined, size: 18, color: UserTheme.primaryOrange),
                        const SizedBox(width: 8),
                        Text(
                          'Rotates in $_secondsLeft seconds',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                'Show this code to the box\'s barcode scanner to unlock. This token is cryptographically signed and works without Internet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
