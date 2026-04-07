import 'package:flutter/material.dart';

class AnimatedScannerOverlay extends StatefulWidget {
  final Color color;
  final double size;

  const AnimatedScannerOverlay({
    super.key,
    required this.color,
    this.size = 240.0,
  });

  @override
  State<AnimatedScannerOverlay> createState() => _AnimatedScannerOverlayState();
}

class _AnimatedScannerOverlayState extends State<AnimatedScannerOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.0, end: widget.size - 4).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        children: [
          // Corner brackets
          CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _ScannerBracketsPainter(color: widget.color),
          ),
          
          // Animated scanning line
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Positioned(
                top: _animation.value,
                left: 0,
                right: 0,
                child: Container(
                  height: 3.0,
                  decoration: BoxDecoration(
                    color: widget.color,
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withOpacity(0.6),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ScannerBracketsPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double bracketLength;

  _ScannerBracketsPainter({
    required this.color,
    this.strokeWidth = 4.0,
    this.bracketLength = 30.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final double w = size.width;
    final double h = size.height;

    // Top-Left
    canvas.drawLine(const Offset(0, 0), Offset(bracketLength, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(0, bracketLength), paint);

    // Top-Right
    canvas.drawLine(Offset(w, 0), Offset(w - bracketLength, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, bracketLength), paint);

    // Bottom-Left
    canvas.drawLine(Offset(0, h), Offset(bracketLength, h), paint);
    canvas.drawLine(Offset(0, h), Offset(0, h - bracketLength), paint);

    // Bottom-Right
    canvas.drawLine(Offset(w, h), Offset(w - bracketLength, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - bracketLength), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
