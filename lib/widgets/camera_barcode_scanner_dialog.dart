import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import 'smart_scanner_view.dart';

/// Result object returned by [CameraBarcodeScannerDialog].
class ScannedBarcodeResult {
  final String trackingId;
  final String detectedCourier;

  ScannedBarcodeResult({
    required this.trackingId,
    required this.detectedCourier,
  });
}

/// Live Camera Barcode Scanner Modal Sheet with desktop/manual fallback.
class CameraBarcodeScannerDialog extends StatefulWidget {
  const CameraBarcodeScannerDialog({super.key});

  static Future<ScannedBarcodeResult?> scan(BuildContext context) {
    return UserUi.showDashboardSheet<ScannedBarcodeResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const CameraBarcodeScannerDialog(),
    );
  }

  @override
  State<CameraBarcodeScannerDialog> createState() =>
      _CameraBarcodeScannerDialogState();
}

class _CameraBarcodeScannerDialogState
    extends State<CameraBarcodeScannerDialog> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final TextEditingController _manualController = TextEditingController();
  bool _manualMode = !SmartScannerView.isCameraSupportedPlatform;
  bool _hasReturned = false;

  @override
  void dispose() {
    _controller.dispose();
    _manualController.dispose();
    super.dispose();
  }

  String _detectCourier(String rawValue) {
    final upper = rawValue.toUpperCase();
    if (upper.startsWith('SPX') || upper.contains('SHOPEE')) {
      return 'Shopee (SPX)';
    }
    if (upper.startsWith('TT') ||
        upper.startsWith('TKK') ||
        upper.contains('TIKTOK')) {
      return 'TikTok Shop';
    }
    if (upper.startsWith('JT') ||
        upper.startsWith('77') ||
        upper.startsWith('99')) {
      return 'J&T Express';
    }
    if (upper.startsWith('FLS') || upper.startsWith('TH')) {
      return 'Flash Express';
    }
    if (upper.startsWith('NV') || upper.contains('NINJA')) return 'NinjaVan';
    if (upper.startsWith('LZD') || upper.startsWith('LX')) return 'Lazada';
    return 'Courier Express';
  }

  void _completeWithCode(String rawValue) {
    final cleanVal = rawValue.trim();
    if (cleanVal.isEmpty || _hasReturned) return;
    _hasReturned = true;
    try {
      _controller.stop();
    } catch (_) {}
    if (mounted) {
      Navigator.of(context).pop(
        ScannedBarcodeResult(
          trackingId: cleanVal,
          detectedCourier: _detectCourier(cleanVal),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = UserUi.dashboardColors(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SizedBox(
      height: _manualMode ? null : MediaQuery.sizeOf(context).height * 0.78,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Waybill barcode scanner',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            _manualMode
                                ? 'Type or paste the tracking barcode'
                                : 'Align courier shipping label inside frame',
                            style: TextStyle(
                                fontSize: 12, color: colors.secondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_manualMode)
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _manualController,
                          autofocus: true,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Tracking ID / Waybill',
                            hintText: 'e.g. SPXPH123456789',
                            prefixIcon: Icon(Icons.tag_rounded),
                          ),
                          onSubmitted: _completeWithCode,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () =>
                              _completeWithCode(_manualController.text),
                          child: const Text('Use barcode'),
                        ),
                        if (SmartScannerView.isCameraSupportedPlatform) ...[
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _manualMode = false),
                            icon: const Icon(Icons.qr_code_scanner_rounded,
                                size: 18),
                            label: const Text('Use camera instead'),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(UserTheme.radiusL),
                      child: SmartScannerView(
                        controller: _controller,
                        isSquare: false,
                        showCameraSwitch: true,
                        verticalCenterFraction: 0.44,
                        instructionText:
                            'Supports 1D courier barcodes & QR shipping waybills',
                        onCodeScanned: _completeWithCode,
                        manualFallbackLabel: 'Type Code',
                        onManualFallback: () {
                          setState(() => _manualMode = true);
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
