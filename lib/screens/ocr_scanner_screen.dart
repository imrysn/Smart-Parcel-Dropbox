import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';

/// AI OCR Scanner Screen (Phase 9: AI Logistics Vision)
///
/// Uses Google ML Kit to recognize tracking numbers from labels
/// when the physical hardware scanner is unavailable or fails.
class OcrScannerScreen extends StatefulWidget {
  const OcrScannerScreen({super.key});

  @override
  State<OcrScannerScreen> createState() => _OcrScannerScreenState();
}

class _OcrScannerScreenState extends State<OcrScannerScreen> {
  CameraController? _cameraController;
  final TextRecognizer _textRecognizer = TextRecognizer();
  bool _isProcessing = false;
  String _lastDetectedText = "";

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _cameraController = CameraController(
      cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
    );

    await _cameraController?.initialize();
    if (mounted) {
      setState(() {});
      _startImageStream();
    }
  }

  void _startImageStream() {
    _cameraController?.startImageStream((image) async {
      if (_isProcessing || !mounted) return;
      _isProcessing = true;

      try {
        // Concatenate plane bytes using typed_data (no dart:ui WriteBuffer needed)
        int totalBytes = 0;
        for (final plane in image.planes) {
          totalBytes += plane.bytes.length;
        }
        final bytes = Uint8List(totalBytes);
        int offset = 0;
        for (final plane in image.planes) {
          bytes.setRange(offset, offset + plane.bytes.length, plane.bytes);
          offset += plane.bytes.length;
        }

        final inputImageMetadata = InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        );

        final inputImage = InputImage.fromBytes(
          bytes: bytes,
          metadata: inputImageMetadata,
        );

        final recognizedText = await _textRecognizer.processImage(inputImage);
        if (mounted) _processText(recognizedText.text);
      } catch (e) {
        debugPrint("OCR Error: $e");
      } finally {
        _isProcessing = false;
      }
    });
  }

  void _processText(String text) {
    // Regex for common tracking ID patterns (10–20 uppercase alphanumeric chars)
    // Covers Shopee (SHP...), Lazada (LZDH...), J&T (PH-JNT-...), and digit-only IDs
    final regExp = RegExp(r'[A-Z0-9]{10,20}');
    final matches = regExp.allMatches(text);

    for (final match in matches) {
      final code = match.group(0);
      if (code != null && code.length >= 10) {
        if (mounted) {
          setState(() => _lastDetectedText = code);
        }
        break; // Use the first confident match; let the user confirm or rescan
      }
    }
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream().catchError((_) {});
    _cameraController?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: UserTheme.primaryOrange),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Full-screen camera feed
          Positioned.fill(child: CameraPreview(_cameraController!)),

          // 2. Dimmed overlay with transparent scan window
          Positioned.fill(
            child: CustomPaint(painter: _ScanOverlayPainter()),
          ),

          // 3. Scan frame label
          const Positioned(
            top: 110,
            left: 0,
            right: 0,
            child: Text(
              'Point at tracking label',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                letterSpacing: 1.2,
              ),
            ),
          ),

          // 4. Close button
          Positioned(
            top: 50,
            left: 16,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // 5. Detection result card (slides up from bottom)
          if (_lastDetectedText.isNotEmpty)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: UserUi.glassCard(
                context,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle,
                            color: UserTheme.primaryOrange, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'TRACKING ID DETECTED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            color: UserTheme.primaryOrange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _lastDetectedText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('RESCAN'),
                            onPressed: () =>
                                setState(() => _lastDetectedText = ""),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('USE THIS'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: UserTheme.primaryOrange,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () =>
                                Navigator.pop(context, _lastDetectedText),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Custom painter for the scanning overlay — dims the background
/// and cuts out a transparent tracking-label-sized window in the center.
class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const windowW = 300.0;
    const windowH = 140.0;
    final left   = (size.width  - windowW) / 2;
    final top    = (size.height - windowH) / 2 - 20;
    final window = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, windowW, windowH),
      const Radius.circular(16),
    );

    // Dimmed mask
    final maskPaint = Paint()..color = Colors.black54;
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(window),
      ),
      maskPaint,
    );

    // Orange border
    final borderPaint = Paint()
      ..color = UserTheme.primaryOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRRect(window, borderPaint);

    // Corner tick marks
    const tickLen = 20.0;
    final tickPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Top-left
    canvas.drawLine(Offset(left, top + tickLen), Offset(left, top), tickPaint);
    canvas.drawLine(Offset(left, top), Offset(left + tickLen, top), tickPaint);
    // Top-right
    canvas.drawLine(Offset(left + windowW - tickLen, top),
        Offset(left + windowW, top), tickPaint);
    canvas.drawLine(Offset(left + windowW, top),
        Offset(left + windowW, top + tickLen), tickPaint);
    // Bottom-left
    canvas.drawLine(Offset(left, top + windowH - tickLen),
        Offset(left, top + windowH), tickPaint);
    canvas.drawLine(Offset(left, top + windowH),
        Offset(left + tickLen, top + windowH), tickPaint);
    // Bottom-right
    canvas.drawLine(Offset(left + windowW - tickLen, top + windowH),
        Offset(left + windowW, top + windowH), tickPaint);
    canvas.drawLine(Offset(left + windowW, top + windowH - tickLen),
        Offset(left + windowW, top + windowH), tickPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
