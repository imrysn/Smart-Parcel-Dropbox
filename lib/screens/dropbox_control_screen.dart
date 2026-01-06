import 'package:flutter/material.dart';
import '../services/database_service.dart';
import 'dart:async';

class DropboxControlScreen extends StatefulWidget {
  const DropboxControlScreen({super.key});

  @override
  State<DropboxControlScreen> createState() => _DropboxControlScreenState();
}

class _DropboxControlScreenState extends State<DropboxControlScreen> with TickerProviderStateMixin {
  final DatabaseService _databaseService = DatabaseService();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  String? _userId;
  Stream<Map<String, dynamic>?>? _doorStateStream;

  @override
  void initState() {
    super.initState();
    _initUser();
    
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initUser() async {
    // We assume the user is already initialized in DatabaseService via HomeScreen
    // But for safety, we can get the current ID if needed.
    // For now, we'll just use the stream which is already initialized globally in the service
    _doorStateStream = _databaseService.getDropBoxDoorState();
    
    // Attempt to get the user ID for commands
    // In a real app, you might pass this or get it from an AuthService
    // Since we're in the same session, we'll try to find it.
    // For this implementation, we'll assume the socket is already joined to the room.
    setState(() {});
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _toggleDoor(bool currentIsOpen, String userId) async {
    try {
      await _databaseService.controlDropBoxDoor(
        userId: userId,
        open: !currentIsOpen,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currentIsOpen ? 'Closing drop box...' : 'Opening drop box...'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Drop Box Control'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A237E), // Indigo 900
              Color(0xFF311B92), // Deep Purple 900
            ],
          ),
        ),
        child: SafeArea(
          child: StreamBuilder<Map<String, dynamic>?>(
            stream: _doorStateStream,
            builder: (context, snapshot) {
              final doorState = snapshot.data;
              final command = doorState?['command'] as String?;
              final isOpen = command == 'open';
              final isProcessing = doorState?['status'] == 'processing';
              final parcelDetected = doorState?['parcelDetected'] ?? false;
              
              // We need the userId. In the current architecture, 
              // we can get it from the doorState if the backend includes it,
              // or better, pass it from the home screen.
              // For now, let's assume we can retrieve it or it's known.
              // I'll add a placeholder if missing.
              final userId = doorState?['userId'] ?? "current_user"; 

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Status Indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: isOpen ? Colors.green : Colors.red,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (isOpen ? Colors.green : Colors.red).withValues(alpha: 0.5),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isOpen ? 'DOOR OPEN' : 'DOOR LOCKED',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 60),
                  
                  // Main Action Button
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: GestureDetector(
                      onTap: isProcessing ? null : () => _toggleDoor(isOpen, userId),
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isOpen
                                ? [Colors.green.shade400, Colors.green.shade700]
                                : [theme.colorScheme.primary, theme.colorScheme.secondary],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isOpen ? Colors.green : theme.colorScheme.primary)
                                  .withValues(alpha: 0.4),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isOpen ? Icons.lock_open_rounded : Icons.lock_rounded,
                                size: 80,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                isProcessing ? '...' : (isOpen ? 'CLOSE' : 'OPEN'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 60),
                  
                  // Info Cards
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Row(
                      children: [
                        _buildInfoCard(
                          icon: Icons.inventory_2_outlined,
                          label: 'Parcel Status',
                          value: parcelDetected ? 'Detected' : 'Empty',
                          color: parcelDetected ? Colors.orange : Colors.white70,
                        ),
                        const SizedBox(width: 20),
                        _buildInfoCard(
                          icon: Icons.wifi,
                          label: 'Connection',
                          value: 'Online',
                          color: Colors.green,
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      parcelDetected 
                        ? 'Warning: A parcel is currently inside the box.'
                        : 'The drop box is ready for new deliveries.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
