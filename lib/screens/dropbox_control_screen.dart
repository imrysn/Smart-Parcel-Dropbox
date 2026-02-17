import 'package:flutter/material.dart';
import '../services/database_service.dart';
import 'dart:async';

class DropboxControlScreen extends StatefulWidget {
  const DropboxControlScreen({super.key});

  @override
  State<DropboxControlScreen> createState() => _DropboxControlScreenState();
}

class _DropboxControlScreenState extends State<DropboxControlScreen>
    with TickerProviderStateMixin {
  final DatabaseService _databaseService = DatabaseService();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  String? _userId;
  Stream<Map<String, dynamic>?>? _doorStateStream;

  // Local state tracking for independent door control
  // This allows doors to work independently until backend is updated
  bool _localParcelDoorOpen = false;
  bool _localUserDoorOpen = false;
  DateTime? _lastParcelDoorUpdate;
  DateTime? _lastUserDoorUpdate;

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

  Future<void> _toggleDoor(
      bool currentIsOpen, String userId, String doorType) async {
    try {
      // Update local state immediately for responsive UI
      setState(() {
        if (doorType == 'parcel') {
          _localParcelDoorOpen = !currentIsOpen;
          _lastParcelDoorUpdate = DateTime.now();
        } else {
          _localUserDoorOpen = !currentIsOpen;
          _lastUserDoorUpdate = DateTime.now();
        }
      });

      await _databaseService.controlDropBoxDoor(
        userId: userId,
        open: !currentIsOpen,
        doorType: doorType,
      );
      if (mounted) {
        final doorName = doorType == 'parcel' ? 'Parcel Door' : 'User Door';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currentIsOpen
                ? 'Closing $doorName...'
                : 'Opening $doorName...'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // Revert local state on error
      setState(() {
        if (doorType == 'parcel') {
          _localParcelDoorOpen = currentIsOpen;
        } else {
          _localUserDoorOpen = currentIsOpen;
        }
      });

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
              final isProcessing = doorState?['status'] == 'processing';
              final parcelDetected = doorState?['parcelDetected'] ?? false;

              // Smart door state logic:
              // 1. If backend provides separate door states, use them
              // 2. Otherwise, use local state (for independent control)
              final backendParcelDoorOpen = doorState?['parcelDoorOpen'];
              final backendUserDoorOpen = doorState?['userDoorOpen'];

              final parcelDoorOpen =
                  backendParcelDoorOpen ?? _localParcelDoorOpen;
              final userDoorOpen = backendUserDoorOpen ?? _localUserDoorOpen;

              // We need the userId. In the current architecture,
              // we can get it from the doorState if the backend includes it,
              // or better, pass it from the home screen.
              // For now, let's assume we can retrieve it or it's known.
              // I'll add a placeholder if missing.
              final userId = doorState?['userId'] ?? "current_user";

              debugPrint('🚪 Door State Update:');
              debugPrint(
                  '  Parcel Door: ${parcelDoorOpen ? "OPEN" : "LOCKED"} (local: $_localParcelDoorOpen, backend: $backendParcelDoorOpen)');
              debugPrint(
                  '  User Door: ${userDoorOpen ? "OPEN" : "LOCKED"} (local: $_localUserDoorOpen, backend: $backendUserDoorOpen)');
              debugPrint('  Processing: $isProcessing');

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const SizedBox(height: 20),

                    // Title
                    const Text(
                      'Drop Box Control',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'Manage both doors independently',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Parcel Door Control (Top Door - for couriers)
                    _buildDoorControlCard(
                      title: 'Parcel Entrance Door',
                      subtitle: 'For courier deliveries (Top)',
                      icon: Icons.local_shipping_outlined,
                      isOpen: parcelDoorOpen,
                      isProcessing: isProcessing,
                      onToggle: () =>
                          _toggleDoor(parcelDoorOpen, userId, 'parcel'),
                      theme: theme,
                      accentColor: Colors.orange,
                    ),

                    const SizedBox(height: 20),

                    // User Door Control (Bottom Door - for retrieval)
                    _buildDoorControlCard(
                      title: 'User Retrieval Door',
                      subtitle: 'For parcel pickup (Bottom)',
                      icon: Icons.person_outline,
                      isOpen: userDoorOpen,
                      isProcessing: isProcessing,
                      onToggle: () => _toggleDoor(userDoorOpen, userId, 'user'),
                      theme: theme,
                      accentColor: Colors.blue,
                    ),

                    const SizedBox(height: 30),

                    // Info Cards
                    Row(
                      children: [
                        _buildInfoCard(
                          icon: Icons.inventory_2_outlined,
                          label: 'Parcel Status',
                          value: parcelDetected ? 'Detected' : 'Empty',
                          color:
                              parcelDetected ? Colors.orange : Colors.white70,
                        ),
                        const SizedBox(width: 16),
                        _buildInfoCard(
                          icon: Icons.wifi,
                          label: 'Connection',
                          value: 'Online',
                          color: Colors.green,
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Info Message
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              parcelDetected
                                  ? 'Warning: A parcel is currently inside the box.'
                                  : 'Both doors can be controlled independently for secure parcel management.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDoorControlCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isOpen,
    required bool isProcessing,
    required VoidCallback onToggle,
    required ThemeData theme,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOpen
              ? accentColor.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.2),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: accentColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Status Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (isOpen ? Colors.green : Colors.red)
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isOpen ? Colors.green : Colors.red,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isOpen ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOpen ? 'OPEN' : 'LOCKED',
                      style: TextStyle(
                        color: isOpen ? Colors.green : Colors.red,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Control Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isProcessing ? null : onToggle,
              style: ElevatedButton.styleFrom(
                backgroundColor: isOpen ? Colors.red.shade600 : accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: isOpen ? 4 : 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isOpen ? Icons.lock_outline : Icons.lock_open_outlined,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isProcessing
                        ? 'Processing...'
                        : (isOpen ? 'CLOSE DOOR' : 'OPEN DOOR'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
