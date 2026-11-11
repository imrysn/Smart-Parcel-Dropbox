import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../config/user_theme.dart';

/// Unified, standard-compliant camera QR/barcode scanner view.
///
/// Features:
/// - Dimmed translucent scrim with rounded cutout synced pixel-for-pixel with `scanWindow`
/// - Crisp L-shaped corner brackets + animated scan laser beam
/// - Integrated flashlight & camera-switch controls driven by [MobileScannerState]
/// - Permission / unsupported hardware error UI + optional manual entry fallback
/// - Single-shot lock & continuous per-code deduplication cooldown
class SmartScannerView extends StatefulWidget {
  final MobileScannerController? controller;
  final void Function(String rawValue) onCodeScanned;
  final bool Function(String rawValue)? validateCode;
  final bool isSquare;
  final bool continuous;
  final String instructionText;
  final Color accentColor;
  final double verticalCenterFraction;
  final double bottomReservedHeight;
  final List<Widget> topWidgets;
  final Widget? bottomWidget;
  final VoidCallback? onManualFallback;
  final String manualFallbackLabel;
  final bool showCameraSwitch;

  const SmartScannerView({
    super.key,
    this.controller,
    required this.onCodeScanned,
    this.validateCode,
    this.isSquare = true,
    this.continuous = false,
    required this.instructionText,
    this.accentColor = UserTheme.primaryOrange,
    this.verticalCenterFraction = 0.44,
    this.bottomReservedHeight = 0.0,
    this.topWidgets = const [],
    this.bottomWidget,
    this.onManualFallback,
    this.manualFallbackLabel = 'Enter Code Manually',
    this.showCameraSwitch = false,
  });

  /// True on mobile platforms supported cleanly by `mobile_scanner`.
  static bool get isCameraSupportedPlatform {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  @override
  State<SmartScannerView> createState() => _SmartScannerViewState();
}

class _SmartScannerViewState extends State<SmartScannerView>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _controller;
  late final bool _ownsController;
  late final AnimationController _beamController;

  bool _singleShotTriggered = false;
  bool _isDisposed = false;
  final Map<String, DateTime> _recentScans = <String, DateTime>{};
  static const Duration _continuousCooldown = Duration(milliseconds: 1800);

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        MobileScannerController(
          detectionSpeed: widget.continuous
              ? DetectionSpeed.normal
              : DetectionSpeed.noDuplicates,
        );
    _controller.addListener(_onControllerStateChanged);

    _beamController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  void _onControllerStateChanged() {
    // Allow re-scanning cleanly whenever a parent stops & restarts the controller.
    if (!_controller.value.isRunning && _singleShotTriggered) {
      _singleShotTriggered = false;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _controller.removeListener(_onControllerStateChanged);
    _beamController.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_isDisposed) return;
    if (!widget.continuous && _singleShotTriggered) return;

    for (final barcode in capture.barcodes) {
      final cleanVal = barcode.rawValue?.trim() ?? '';
      if (cleanVal.isEmpty) continue;
      if (widget.validateCode != null && !widget.validateCode!(cleanVal)) {
        continue;
      }

      if (widget.continuous) {
        final now = DateTime.now();
        final prev = _recentScans[cleanVal];
        if (prev != null && now.difference(prev) < _continuousCooldown) {
          continue;
        }
        _recentScans[cleanVal] = now;
        _recentScans.removeWhere((_, ts) => now.difference(ts) > const Duration(seconds: 10));
      } else {
        _singleShotTriggered = true;
      }

      HapticFeedback.mediumImpact();
      widget.onCodeScanned(cleanVal);
      break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!SmartScannerView.isCameraSupportedPlatform) {
      return _buildUnsupportedOrError(
        icon: Icons.videocam_off_outlined,
        title: 'Camera Unavailable',
        subtitle: 'Live camera scanning is not supported on this device.',
        canRetry: false,
      );
    }

    final topInset = MediaQuery.paddingOf(context).top;

    return LayoutBuilder(
      builder: (context, constraints) {
        final layoutSize = constraints.biggest;
        final footerClearance =
            widget.bottomReservedHeight > 0
                ? widget.bottomReservedHeight
                : (widget.bottomWidget != null ? 92.0 : 0.0);
        const controlsClearance = 108.0;
        final safeTop = topInset + 16.0;
        final usableHeight = math.max(
          160.0,
          layoutSize.height - safeTop - controlsClearance - footerClearance,
        );

        final double cutoutWidth;
        final double cutoutHeight;

        if (widget.isSquare) {
          final maxSquare = math.min(layoutSize.width * 0.68, usableHeight * 0.72);
          final side = maxSquare.clamp(140.0, 260.0);
          cutoutWidth = side;
          cutoutHeight = side;
        } else {
          cutoutWidth = (layoutSize.width * 0.78).clamp(200.0, 340.0);
          cutoutHeight = math
              .min(cutoutWidth * 0.48, usableHeight * 0.65)
              .clamp(96.0, 165.0);
        }

        final minY = safeTop + cutoutHeight / 2;
        final maxY = math.max(
          minY,
          layoutSize.height - footerClearance - controlsClearance - cutoutHeight / 2,
        );
        final centerY =
            (layoutSize.height * widget.verticalCenterFraction).clamp(minY, maxY);

        final scanWindow = Rect.fromCenter(
          center: Offset(layoutSize.width / 2, centerY),
          width: cutoutWidth,
          height: cutoutHeight,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              scanWindow: scanWindow,
              onDetect: _handleDetect,
              placeholderBuilder: (context, _) => Container(
                color: Colors.black,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: UserTheme.primaryOrange,
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Starting camera...',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              errorBuilder: (context, error, _) {
                final isDenied =
                    error.errorCode == MobileScannerErrorCode.permissionDenied;
                return _buildUnsupportedOrError(
                  icon: isDenied
                      ? Icons.no_photography_rounded
                      : Icons.videocam_off_rounded,
                  title: isDenied
                      ? 'Camera Permission Required'
                      : 'Camera Unavailable',
                  subtitle: isDenied
                      ? 'Enable camera access in your device settings to scan codes.'
                      : (error.errorDetails?.message ??
                          'Could not open the camera preview.'),
                  canRetry: true,
                );
              },
            ),

            // Dimmed scrim cutout + animated corner-bracket reticle
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _beamController,
                builder: (context, _) => CustomPaint(
                  size: layoutSize,
                  painter: _ScannerOverlayPainter(
                    scanWindow: scanWindow,
                    accentColor: widget.accentColor,
                    beamProgress: _beamController.value,
                  ),
                ),
              ),
            ),

            // Top badges (e.g., countdown timer) anchored above scan frame
            if (widget.topWidgets.isNotEmpty)
              Positioned(
                left: 20,
                right: 20,
                bottom: layoutSize.height - scanWindow.top + 14,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: widget.topWidgets,
                ),
              ),

            // Instruction label + quick camera controls anchored below scan frame
            Positioned(
              left: 16,
              right: 16,
              top: scanWindow.bottom + 14,
              bottom: footerClearance + 6,
              child: Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.instructionText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildCameraControlRow(),
                    ],
                  ),
                ),
              ),
            ),

            // Optional caller-supplied footer controls
            if (widget.bottomWidget != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: widget.bottomWidget!,
              ),
          ],
        );
      },
    );
  }

  Widget _buildCameraControlRow() {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _controller,
      builder: (context, state, _) {
        final hasTorch = state.torchState != TorchState.unavailable;
        final torchOn = state.torchState == TorchState.on;
        final canSwitch =
            widget.showCameraSwitch && (state.availableCameras ?? 0) > 1;
        final hasManual = widget.onManualFallback != null;

        if (!hasTorch && !canSwitch && !hasManual) {
          return const SizedBox.shrink();
        }

        return Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (hasTorch)
              _CameraActionPill(
                icon: torchOn
                    ? Icons.flashlight_on_rounded
                    : Icons.flashlight_off_rounded,
                label: torchOn ? 'Flash On' : 'Flash',
                active: torchOn,
                accentColor: widget.accentColor,
                onTap: () async {
                  try {
                    await _controller.toggleTorch();
                  } catch (_) {}
                },
              ),
            if (canSwitch)
              _CameraActionPill(
                icon: Icons.cameraswitch_rounded,
                label: 'Flip',
                accentColor: widget.accentColor,
                onTap: () async {
                  try {
                    await _controller.switchCamera();
                  } catch (_) {}
                },
              ),
            if (hasManual)
              _CameraActionPill(
                icon: Icons.dialpad_rounded,
                label: widget.manualFallbackLabel,
                accentColor: widget.accentColor,
                onTap: widget.onManualFallback!,
              ),
          ],
        );
      },
    );
  }

  Widget _buildUnsupportedOrError({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool canRetry,
  }) {
    return Container(
      color: UserTheme.nightBackground,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 36,
                  color: widget.accentColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              if (canRetry || widget.onManualFallback != null) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    if (canRetry)
                      OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            await _controller.stop();
                            await _controller.start();
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 17),
                        label: const Text('Retry Camera'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    if (widget.onManualFallback != null)
                      ElevatedButton.icon(
                        onPressed: widget.onManualFallback,
                        icon: const Icon(Icons.dialpad_rounded, size: 17),
                        label: Text(widget.manualFallbackLabel),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color accentColor;
  final VoidCallback onTap;

  const _CameraActionPill({
    required this.icon,
    required this.label,
    this.active = false,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? accentColor.withValues(alpha: 0.92)
          : Colors.black.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: active
                  ? accentColor
                  : Colors.white.withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 17),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Rect scanWindow;
  final Color accentColor;
  final double beamProgress;

  const _ScannerOverlayPainter({
    required this.scanWindow,
    required this.accentColor,
    required this.beamProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const cornerRadius = 18.0;
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()
      ..addRRect(
        RRect.fromRectAndRadius(scanWindow, const Radius.circular(cornerRadius)),
      );
    final scrimPath = Path.combine(PathOperation.difference, outer, inner);

    // 1. Darkened translucent scrim outside the cutout
    canvas.drawPath(
      scrimPath,
      Paint()..color = Colors.black.withValues(alpha: 0.56),
    );

    // 2. Subtle inner hairline border around cutout
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanWindow, const Radius.circular(cornerRadius)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // 3. Animated laser beam clipped inside the cutout
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(scanWindow, const Radius.circular(cornerRadius)),
    );
    final beamY = scanWindow.top +
        14 +
        (scanWindow.height - 28) * Curves.easeInOut.transform(beamProgress);
    final beamRect = Rect.fromLTWH(scanWindow.left + 12, beamY - 1.2, scanWindow.width - 24, 2.4);
    final beamPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          accentColor.withValues(alpha: 0.0),
          accentColor.withValues(alpha: 0.9),
          accentColor.withValues(alpha: 0.0),
        ],
      ).createShader(beamRect);
    canvas.drawRect(beamRect, beamPaint);
    canvas.restore();

    // 4. L-shaped corner brackets
    final bracketPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    const arm = 24.0;
    const r = cornerRadius;
    final l = scanWindow.left;
    final t = scanWindow.top;
    final ri = scanWindow.right;
    final b = scanWindow.bottom;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(l, t + arm)
        ..lineTo(l, t + r)
        ..arcToPoint(Offset(l + r, t), radius: const Radius.circular(r))
        ..lineTo(l + arm, t),
      bracketPaint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(ri - arm, t)
        ..lineTo(ri - r, t)
        ..arcToPoint(Offset(ri, t + r), radius: const Radius.circular(r))
        ..lineTo(ri, t + arm),
      bracketPaint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(ri, b - arm)
        ..lineTo(ri, b - r)
        ..arcToPoint(Offset(ri - r, b), radius: const Radius.circular(r))
        ..lineTo(ri - arm, b),
      bracketPaint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(l + arm, b)
        ..lineTo(l + r, b)
        ..arcToPoint(Offset(l, b - r), radius: const Radius.circular(r))
        ..lineTo(l, b - arm),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.beamProgress != beamProgress;
  }
}
