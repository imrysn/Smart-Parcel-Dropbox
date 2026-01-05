import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'admin/admin_dashboard_screen.dart';

/// Splash Screen - Professional delivery animation with offline support
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  final AuthService _authService = AuthService();
  final DatabaseService _databaseService = DatabaseService();

  late Animation<double> _fadeAnimation;
  late Animation<double> _deliveryAnimation;
  late Animation<double> _boxAnimation;
  late Animation<double> _checkAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _startAnimations();
    _checkAuthState();
  }

  void _initAnimations() {
    // Main animation controller for the delivery sequence
    _mainController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat();

    // Fade in controller
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Pulse controller for loading indicator
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    // Animations
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeIn));

    _deliveryAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
      ),
    );

    _boxAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.4, 0.7, curve: Curves.easeOut),
      ),
    );

    _checkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _mainController,
        curve: const Interval(0.7, 1.0, curve: Curves.elasticOut),
      ),
    );

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _startAnimations() {
    _fadeController.forward();
  }

  Future<void> _checkAuthState() async {
    await Future.delayed(const Duration(milliseconds: 2000));

    if (!mounted) return;

    // Check if user is logged in (has JWT token)
    final isLoggedIn = await _authService.isLoggedIn;

    if (isLoggedIn) {
      try {
        final userId = await _authService.currentUserId;
        
        if (userId == null) {
          // Token exists but no user ID - corrupted state
          await _authService.signOut();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
          return;
        }

        // Get user data from MongoDB
        final data = await _databaseService.getUserData(userId);
        
        if (data == null) {
          // User not found in MongoDB - sign out
          await _authService.signOut();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
          return;
        }

        final role = data['role'];

        if (!mounted) return;

        if (role == 'admin') {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      } catch (e) {
        debugPrint('Error checking auth state: $e');
        if (!mounted) return;
        await _authService.signOut();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    _mainController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFFF6F00), // Orange 900
              Color(0xFFF4511E), // Deep Orange 600
              Color(0xFFE91E63), // Pink 500
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),

                // Animated delivery illustration
                SizedBox(
                  height: 280,
                  width: double.infinity,
                  child: AnimatedBuilder(
                    animation: _mainController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: DeliveryAnimationPainter(
                          deliveryProgress: _deliveryAnimation.value,
                          boxProgress: _boxAnimation.value,
                          checkProgress: _checkAnimation.value,
                        ),
                        child: Container(),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 50),

                // App title with elegant styling
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Smart Parcel Drop Box',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                          shadows: [
                            Shadow(
                              blurRadius: 20,
                              color: Colors.black.withOpacity(0.3),
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Secure Contactless Deliveries',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.95),
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildFeatureBadge(Icons.lock_outline, 'Secure'),
                          _buildFeatureBadge(Icons.speed, 'Fast'),
                          _buildFeatureBadge(Icons.contactless, 'Contactless'),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 50),

                // Animated loading indicator
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Column(
                      children: [
                        Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            width: 50,
                            height: 50,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white.withOpacity(0.9),
                              ),
                              strokeWidth: 3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Loading...',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const Spacer(),

                // Footer
                Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: Column(
                    children: [
                      Text(
                        'Cavite State University',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Bacoor Campus',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 11,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the delivery animation - 100% offline
class DeliveryAnimationPainter extends CustomPainter {
  final double deliveryProgress;
  final double boxProgress;
  final double checkProgress;

  DeliveryAnimationPainter({
    required this.deliveryProgress,
    required this.boxProgress,
    required this.checkProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Draw drop box (stationary)
    _drawDropBox(canvas, centerX, centerY + 20);

    // Draw delivery person with package (moving)
    final deliveryX = centerX - 150 + (deliveryProgress * 120);
    _drawDeliveryPerson(canvas, deliveryX, centerY);

    // Draw package going into box
    if (boxProgress > 0) {
      final packageY = centerY - 30 + (boxProgress * 80);
      _drawPackage(canvas, centerX, packageY, boxProgress);
    }

    // Draw check mark when complete
    if (checkProgress > 0) {
      _drawCheckMark(canvas, centerX, centerY - 60, checkProgress);
    }
  }

  void _drawDropBox(Canvas canvas, double x, double y) {
    final boxPaint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.grey[800]!, Colors.grey[900]!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(x - 50, y - 60, 100, 120));

    final boxRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, y), width: 100, height: 120),
      const Radius.circular(12),
    );
    canvas.drawRRect(boxRect, boxPaint);

    // Box outline
    final outlinePaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(boxRect, outlinePaint);

    // Scanner screen
    final screenPaint = Paint()..color = Colors.blue.withOpacity(0.8);
    final screenRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, y - 35), width: 70, height: 40),
      const Radius.circular(6),
    );
    canvas.drawRRect(screenRect, screenPaint);

    // QR icon
    final qrPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(x, y - 35), width: 20, height: 20),
      qrPaint,
    );

    // Drop slot
    final slotPaint = Paint()..color = Colors.black54;
    final slotRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, y + 25), width: 70, height: 50),
      const Radius.circular(8),
    );
    canvas.drawRRect(slotRect, slotPaint);

    // Arrow down
    final arrowPaint = Paint()
      ..color = Colors.white54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final arrowPath = Path()
      ..moveTo(x, y + 15)
      ..lineTo(x, y + 35)
      ..moveTo(x, y + 35)
      ..lineTo(x - 8, y + 27)
      ..moveTo(x, y + 35)
      ..lineTo(x + 8, y + 27);
    canvas.drawPath(arrowPath, arrowPaint);

    // Lock icon at bottom
    final lockPaint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(x, y + 55), 3, lockPaint);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(x, y + 60), width: 8, height: 8),
      lockPaint,
    );
  }

  void _drawDeliveryPerson(Canvas canvas, double x, double y) {
    // Motorcycle wheels
    final wheelPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawCircle(Offset(x + 20, y + 50), 12, wheelPaint);
    canvas.drawCircle(Offset(x + 70, y + 50), 12, wheelPaint);

    // Motorcycle body
    final bikePaint = Paint()
      ..color = Colors.red[700]!
      ..style = PaintingStyle.fill;

    final bikePath = Path()
      ..moveTo(x + 20, y + 40)
      ..lineTo(x + 70, y + 40)
      ..lineTo(x + 75, y + 50)
      ..lineTo(x + 15, y + 50)
      ..close();
    canvas.drawPath(bikePath, bikePaint);

    // Top box (delivery box)
    final topBoxPaint = Paint()..color = Colors.orange[700]!;
    final topBoxRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y + 10, 35, 25),
      const Radius.circular(6),
    );
    canvas.drawRRect(topBoxRect, topBoxPaint);

    // Package icon on box
    final packageIconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(x + 17.5, y + 22.5),
        width: 15,
        height: 12,
      ),
      packageIconPaint,
    );

    // Rider head
    final headPaint = Paint()..color = Colors.brown[300]!;
    canvas.drawCircle(Offset(x + 60, y + 5), 12, headPaint);

    // Rider body
    final bodyPaint = Paint()..color = Colors.blue[800]!;
    final bodyPath = Path()
      ..moveTo(x + 60, y + 17)
      ..lineTo(x + 60, y + 40)
      ..lineTo(x + 50, y + 45)
      ..moveTo(x + 60, y + 25)
      ..lineTo(x + 75, y + 35);

    canvas.drawPath(
      bodyPath,
      bodyPaint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );

    // Speed lines
    final speedPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(x - 15 - (i * 10), y + 20 + (i * 8)),
        Offset(x - 25 - (i * 10), y + 20 + (i * 8)),
        speedPaint,
      );
    }
  }

  void _drawPackage(Canvas canvas, double x, double y, double progress) {
    final packagePaint = Paint()..color = Colors.brown[400]!;

    final packageRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(x, y),
        width: 35 * (1 + progress * 0.2),
        height: 35 * (1 + progress * 0.2),
      ),
      const Radius.circular(6),
    );

    // Package shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3 * progress)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRRect(packageRect.shift(const Offset(0, 5)), shadowPaint);

    // Package
    canvas.drawRRect(packageRect, packagePaint);

    // Tape
    final tapePaint = Paint()
      ..color = Colors.brown[200]!
      ..strokeWidth = 4;
    canvas.drawLine(Offset(x - 18, y), Offset(x + 18, y), tapePaint);
    canvas.drawLine(Offset(x, y - 18), Offset(x, y + 18), tapePaint);

    // Barcode
    final barcodePaint = Paint()..color = Colors.white;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(x + 10, y + 10), width: 12, height: 8),
      barcodePaint,
    );
  }

  void _drawCheckMark(Canvas canvas, double x, double y, double progress) {
    // Ensure progress is at least a very small value to avoid assertion errors
    final safeProgress = progress.clamp(0.001, 1.0);

    final circlePaint = Paint()
      ..color = Colors.greenAccent.withOpacity(safeProgress)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(x, y), 30 * safeProgress, circlePaint);

    final checkPaint = Paint()
      ..color = Colors.white.withOpacity(safeProgress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final checkPath = Path()
      ..moveTo(x - 12, y)
      ..lineTo(x - 4, y + 8)
      ..lineTo(x + 12, y - 8);

    canvas.drawPath(checkPath, checkPaint);
  }

  @override
  bool shouldRepaint(DeliveryAnimationPainter oldDelegate) {
    return oldDelegate.deliveryProgress != deliveryProgress ||
        oldDelegate.boxProgress != boxProgress ||
        oldDelegate.checkProgress != checkProgress;
  }
}
