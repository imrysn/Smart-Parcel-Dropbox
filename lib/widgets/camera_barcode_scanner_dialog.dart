import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../config/user_theme.dart';

/// Result object returned by CameraBarcodeScannerDialog
class ScannedBarcodeResult {
  final String trackingId;
  final String detectedCourier;

  ScannedBarcodeResult({
    required this.trackingId,
    required this.detectedCourier,
  });
}

/// Live Camera Barcode Scanner Modal Sheet
class CameraBarcodeScannerDialog extends StatefulWidget {
  const CameraBarcodeScannerDialog({super.key});

  static Future<ScannedBarcodeResult?> scan(BuildContext context) {
    return showModalBottomSheet<ScannedBarcodeResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CameraBarcodeScannerDialog(),
    );
  }

  @override
  State<CameraBarcodeScannerDialog> createState() => _CameraBarcodeScannerDialogState();
}

class _CameraBarcodeScannerDialogState extends State<CameraBarcodeScannerDialog> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isTorchOn = false;
  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    _controller.dispose();
    super.dispose();
  }

  String _detectCourier(String rawValue) {
    final upper = rawValue.toUpperCase();
    if (upper.startsWith('SPX') || upper.contains('SHOPEE')) return 'Shopee (SPX)';
    if (upper.startsWith('TT') || upper.startsWith('TKK') || upper.contains('TIKTOK')) return 'TikTok Shop';
    if (upper.startsWith('JT') || upper.startsWith('77') || upper.startsWith('99')) return 'J&T Express';
    if (upper.startsWith('FLS') || upper.startsWith('TH')) return 'Flash Express';
    if (upper.startsWith('NV') || upper.startsWith('NINJA')) return 'NinjaVan';
    if (upper.startsWith('LZD') || upper.startsWith('LX')) return 'Lazada';
    return 'Courier Express';
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isDisposed) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.trim().isNotEmpty) {
        final cleanVal = rawValue.trim();
        HapticFeedback.heavyImpact();
        
        final courier = _detectCourier(cleanVal);
        _controller.stop();
        
        if (mounted) {
          Navigator.of(context).pop(
            ScannedBarcodeResult(
              trackingId: cleanVal,
              detectedCourier: courier,
            ),
          );
        }
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: isDark ? UserTheme.nightBackground : UserTheme.dayBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white30 : Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: UserTheme.primaryOrange.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.qr_code_scanner_rounded, color: UserTheme.primaryOrange, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Waybill Barcode Scanner',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                          ),
                        ),
                        Text(
                          'Point camera at Shopee / TikTok shipping label',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Camera Viewfinder
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: UserTheme.primaryOrange.withOpacity(0.4), width: 2),
              ),
              child: Stack(
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                  ),

                  // Viewfinder Frame Overlay
                  Center(
                    child: Container(
                      width: 260,
                      height: 140,
                      decoration: BoxDecoration(
                        border: Border.all(color: UserTheme.primaryOrange, width: 2.5),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: UserTheme.primaryOrange.withOpacity(0.2),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Controls Bar (Flashlight toggle)
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'torch_btn',
                          backgroundColor: _isTorchOn ? UserTheme.primaryOrange : Colors.black54,
                          onPressed: () async {
                            await _controller.toggleTorch();
                            setState(() => _isTorchOn = !_isTorchOn);
                          },
                          child: Icon(_isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Instructions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Supports 1D Barcodes, QR Codes & Shipping Waybills',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
