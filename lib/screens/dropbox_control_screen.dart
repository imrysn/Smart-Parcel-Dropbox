import 'package:flutter/material.dart';
import 'dart:async';
import '../services/service_locator.dart';
import '../services/websocket_service.dart';
import '../services/auth_service.dart';
import '../services/dropbox_service.dart';
import 'hardware_registration_screen.dart';

// ─── Door type constants matching ESP32 firmware ───────────────────────────
const String kDoorTop      = 'top';      // LOCK_TOP / REED_TOP
const String kDoorPickup   = 'pickup';   // LOCK_PICKUP / REED_PICKUP
const String kDoorReceived = 'received'; // LOCK_RECEIVED / REED_RECEIVED

// ─── Ultrasonic sensor range constants (cm) ────────────────────────────────
// Tune these to match your physical bin depth
const double kBinEmpty  = 30.0; // cm — sensor reading when bin is empty
const double kBinFull   =  5.0; // cm — sensor reading when bin is 100% full

class DropboxControlScreen extends StatefulWidget {
  const DropboxControlScreen({super.key});

  @override
  State<DropboxControlScreen> createState() => _DropboxControlScreenState();
}

class _DropboxControlScreenState extends State<DropboxControlScreen>
    with TickerProviderStateMixin {

  late final WebSocketService _ws;

  // Stream subscriptions
  StreamSubscription<Map<String, dynamic>>? _esp32Sub;
  StreamSubscription<Map<String, dynamic>>? _binSub;
  StreamSubscription<Map<String, dynamic>>? _unregSub;

  // Live state
  bool _esp32Connected = false;

  // Per-door open/close state (local optimistic update)
  final Map<String, bool> _doorOpen = {
    kDoorTop: false,
    kDoorPickup: false,
    kDoorReceived: false,
  };
  final Map<String, bool> _doorProcessing = {
    kDoorTop: false,
    kDoorPickup: false,
    kDoorReceived: false,
  };

  // REED switch state from hardware
  final Map<String, bool?> _reedState = {
    'REED_TOP': null,
    'REED_PICKUP': null,
    'REED_RECEIVED': null,
  };

  // Ultrasonic fill percentages (0.0 – 1.0)
  double? _pickupFill;
  double? _dropoffFill;

  String? _userId;

  // Dropbox registration state
  bool _hasDropbox          = false;
  bool _registrationChecked = false;

  // Pulse animation for ESP32 connected indicator
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _ws = getIt<WebSocketService>();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _init();
  }

  Future<void> _init() async {
    final auth = getIt<AuthService>();
    _userId = await auth.currentUserId;

    // Check if a dropbox is already registered for this user
    if (_userId != null) {
      final dropboxService = getIt<DropboxService>();
      final dropbox = await dropboxService.getUserDropbox(_userId!);
      if (mounted) {
        setState(() {
          _hasDropbox          = dropbox != null;
          _registrationChecked = true;
        });
      }
    } else {
      if (mounted) setState(() => _registrationChecked = true);
    }

    _esp32Sub?.cancel();
    _binSub?.cancel();
    _unregSub?.cancel();

    // Listen for ESP32 connection events
    _esp32Sub = _ws.esp32StatusUpdates.listen((data) {
      if (mounted) {
        setState(() => _esp32Connected = data['connected'] == true);
      }
    });

    // Listen for unregistration confirmation from backend
    _unregSub = getIt<DropboxService>().deviceUnregisteredStream.listen((data) {
      if (data['success'] == true) {
        debugPrint('🗑️ Unregistration confirmed by backend, refreshing UI');
        _init();
      }
    });

    // Listen for bin / sensor updates
    _binSub = _ws.binStatusUpdates.listen((data) {
      if (!mounted) return;
      setState(() {
        // Ultrasonic: convert cm reading → fill %
        final usPickup  = (data['US_PICKUP']  as num?)?.toDouble();
        final usDropoff = (data['US_DROPOFF'] as num?)?.toDouble();
        if (usPickup  != null) _pickupFill  = _cmToFill(usPickup);
        if (usDropoff != null) _dropoffFill = _cmToFill(usDropoff);

        // Reed switches
        if (data.containsKey('REED_TOP'))      _reedState['REED_TOP']      = data['REED_TOP'];
        if (data.containsKey('REED_PICKUP'))   _reedState['REED_PICKUP']   = data['REED_PICKUP'];
        if (data.containsKey('REED_RECEIVED')) _reedState['REED_RECEIVED'] = data['REED_RECEIVED'];
      });
    });

    // ── Query CURRENT state from backend immediately ──────────────────────
    // The esp32Status event fires on connect/disconnect transitions only —
    // calling requestEsp32Status() gets the current state right now, even
    // if the ESP32 was already connected before this screen was opened.
    _ws.requestEsp32Status();
    _ws.requestDoorStatus();
    if (mounted) setState(() {});
  }

  /// Convert ultrasonic distance (cm) to 0..1 fill fraction.
  double _cmToFill(double cm) {
    // Clamp to valid range, then invert (closer = more full)
    final clamped = cm.clamp(kBinFull, kBinEmpty);
    return 1.0 - ((clamped - kBinFull) / (kBinEmpty - kBinFull));
  }

  @override
  void dispose() {
    _esp32Sub?.cancel();
    _binSub?.cancel();
    _unregSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ─── Door control ────────────────────────────────────────────────────────
  void _toggleDoor(String doorType) {
    final isOpen = _doorOpen[doorType]!;
    final action = isOpen ? 'close' : 'open';

    setState(() => _doorProcessing[doorType] = true);

    // Optimistic update
    setState(() => _doorOpen[doorType] = !isOpen);

    // Send to ESP32 via WebSocket relay
    _ws.emitControlDoor(doorType, action);

    // Revert processing flag after brief delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _doorProcessing[doorType] = false);
    });

    final doorName = _doorLabel(doorType);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${isOpen ? 'Closing' : 'Opening'} $doorName...'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isOpen ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  void _showUnregisterConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Dropbox?'),
        content: const Text(
          'This will unregister the device from your account. '
          'You will need to scan the registration QR code again to reconnect it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (_userId != null) {
                debugPrint('🗑️ UI: User triggered unregistration for $_userId');
                getIt<DropboxService>().unregisterDevice(_userId!);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Unregistering device...'),
                    duration: Duration(seconds: 5),
                  ),
                );
              }
            },
            child: const Text('REMOVE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _doorLabel(String doorType) {
    switch (doorType) {
      case kDoorTop:      return 'Parcel Door';
      case kDoorPickup:   return 'Pick Up Door';
      case kDoorReceived: return 'Drop Off Door';
      default:            return doorType;
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Device Management'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── ⚙️ DEVICE SETTINGS (Always Visible) ──────────────────────────
                _buildManagementSection(),
                const SizedBox(height: 20),

                if (_hasDropbox) ...[
                  // ── ESP32 Connection Banner ──────────────────────────────
                  _buildConnectionBanner(),
                  const SizedBox(height: 20),

                  // ── Door Cards ──────────────────────────────────────────
                  _buildDoorCard(
                    doorType: kDoorTop,
                    title: 'Parcel Door',
                    subtitle: 'Courier drop-off entry (Top)',
                    icon: Icons.local_shipping_outlined,
                    reedKey: 'REED_TOP',
                    accentColor: Colors.orange.shade600,
                  ),
                  const SizedBox(height: 14),

                  _buildDoorCard(
                    doorType: kDoorPickup,
                    title: 'Pick Up Door',
                    subtitle: 'Front bottom — owner retrieves parcel',
                    icon: Icons.outbox_outlined,
                    reedKey: 'REED_PICKUP',
                    accentColor: Colors.deepOrange.shade600,
                  ),
                  const SizedBox(height: 14),

                  _buildDoorCard(
                    doorType: kDoorReceived,
                    title: 'Drop Off Door',
                    subtitle: 'Back — owner deposits outgoing parcel',
                    icon: Icons.move_to_inbox_outlined,
                    reedKey: 'REED_RECEIVED',
                    accentColor: Colors.orange.shade400,
                  ),
                  const SizedBox(height: 24),

                  // ── Bin Status ──────────────────────────────────────────
                  Text(
                    'BIN STATUS',
                    style: TextStyle(
                      color: Colors.grey.shade800,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: _buildBinCard(
                          label: 'Pick Up Bin',
                          sublabel: 'US_PICKUP',
                          fill: _pickupFill,
                          color: Colors.deepOrange.shade600,
                          icon: Icons.outbox_outlined,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildBinCard(
                          label: 'Drop Off Bin',
                          sublabel: 'US_DROPOFF',
                          fill: _dropoffFill,
                          color: Colors.orange.shade600,
                          icon: Icons.move_to_inbox_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],

                if (!_hasDropbox && _registrationChecked)
                  _buildEmptyState(),

                const SizedBox(height: 60), 
              ],
            ),
          ),
        ),
      );
    }

  // ─── Management Section (Always Visible) ──────────────────────────────────
  Widget _buildManagementSection() {
    final primaryColor = Theme.of(context).colorScheme.primary;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.settings_suggest_outlined, color: primaryColor),
              const SizedBox(width: 10),
              Text(
                'DEVICE MANAGEMENT',
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_hasDropbox) ...[
            const Text(
              'No smart dropbox registered.',
              style: TextStyle(color: Colors.black54, fontSize: 14),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HardwareRegistrationScreen())
                ).then((_) => _init()),
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('REGISTER NEW DEVICE'),
              ),
            ),
          ] else ...[
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined, color: Colors.black54, size: 20),
                const SizedBox(width: 8),
                const Text('Registered Dropbox', style: TextStyle(fontWeight: FontWeight.w500)),
                const Spacer(),
                _buildStatusIndicator(),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showWiFiConfigDialog,
                    icon: const Icon(Icons.wifi, size: 16),
                    label: const Text('WIFI CONFIG'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showUnregisterConfirmation,
                    icon: const Icon(Icons.delete_forever, size: 16),
                    label: const Text('REMOVE'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _esp32Connected ? Colors.green : Colors.red,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _esp32Connected ? 'Online' : 'Offline',
          style: TextStyle(
            color: _esp32Connected ? Colors.green : Colors.red,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Column(
      children: [
        const SizedBox(height: 40),
        Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(
          'Device Controls Hidden',
          style: TextStyle(color: Colors.grey.shade400, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Register your hardware to see door controls and bin status.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        ),
      ],
    );
  }

  void _showWiFiConfigDialog() {
    final ssidController = TextEditingController();
    final passController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Device WiFi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sending new credentials to your dropbox. Make sure the device is powered on.'),
            const SizedBox(height: 20),
            TextField(
              controller: ssidController,
              decoration: const InputDecoration(labelText: 'WiFi SSID (Name)', prefixIcon: Icon(Icons.wifi)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'WiFi Password', prefixIcon: Icon(Icons.lock_outline)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              final ssid = ssidController.text.trim();
              if (ssid.isNotEmpty) {
                getIt<DropboxService>().pushHardwareConfig(ssid: ssid, password: passController.text);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pushing WiFi config to device...')),
                );
              }
            },
            child: const Text('PUSH CONFIG'),
          ),
        ],
      ),
    );
  }

  // Legacy Banner Removed
  Widget _buildRegistrationBanner() => const SizedBox.shrink();

  // ─── ESP32 Connection Banner ─────────────────────────────────────────────
  Widget _buildConnectionBanner() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: (_esp32Connected ? Colors.green : Colors.red)
              .withOpacity(0.15 * _pulseAnimation.value + 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (_esp32Connected ? Colors.greenAccent : Colors.redAccent)
                .withOpacity(0.5),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _esp32Connected ? Colors.greenAccent : Colors.redAccent,
                boxShadow: [
                  BoxShadow(
                    color: (_esp32Connected ? Colors.green : Colors.red)
                        .withOpacity(0.6 * _pulseAnimation.value),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _esp32Connected ? 'ESP32 Connected' : 'ESP32 Disconnected',
              style: TextStyle(
                color: _esp32Connected ? Colors.greenAccent : Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Door Card ───────────────────────────────────────────────────────────
  Widget _buildDoorCard({
    required String doorType,
    required String title,
    required String subtitle,
    required IconData icon,
    required String reedKey,
    required Color accentColor,
  }) {
    final isOpen       = _doorOpen[doorType]!;
    final isProcessing = _doorProcessing[doorType]!;
    final reedOpen     = _reedState[reedKey]; // null = unknown

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: isOpen ? accentColor.withOpacity(0.5) : Colors.grey.shade200,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: Colors.grey.shade900,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
              // Status pill
              _buildStatusPill(isOpen),
            ],
          ),

          const SizedBox(height: 6),

          // Reed sensor row
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(Icons.sensors, size: 12, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                reedOpen == null
                    ? 'Reed: —'
                    : reedOpen
                        ? 'Reed: OPEN'
                        : 'Reed: CLOSED',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: reedOpen == null
                      ? Colors.grey.shade400
                      : reedOpen
                          ? Colors.orange.shade700
                          : Colors.grey.shade600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Control button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_doorProcessing[doorType]! || !_esp32Connected)
                  ? null
                  : () => _toggleDoor(doorType),
              icon: Icon(
                isOpen ? Icons.lock_outline : Icons.lock_open_outlined,
                size: 18,
              ),
              label: Text(
                isProcessing
                    ? 'PROCESSING...'
                    : !_esp32Connected
                        ? 'ESP32 OFFLINE'
                        : isOpen
                            ? 'CLOSE DOOR'
                            : 'OPEN DOOR',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    !_esp32Connected
                        ? Colors.red.shade50
                        : isOpen
                            ? Colors.red.shade600
                            : accentColor.withOpacity(0.85),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.red.shade700, // Match red banner
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
                disabledBackgroundColor: Colors.red.shade50, // Match red banner bg
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Status Pill ─────────────────────────────────────────────────────────
  Widget _buildStatusPill(bool isOpen) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (isOpen ? Colors.green : Colors.red).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isOpen ? Colors.green : Colors.red),
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
          const SizedBox(width: 5),
          Text(
            isOpen ? 'OPEN' : 'LOCKED',
            style: TextStyle(
              color: isOpen ? Colors.green : Colors.red,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Bin Status Card ─────────────────────────────────────────────────────
  Widget _buildBinCard({
    required String label,
    required String sublabel,
    required double? fill,
    required Color color,
    required IconData icon,
  }) {
    final pct        = fill != null ? (fill * 100).round() : null;
    final fillLabel  = pct == null ? '—' : '$pct%';
    final statusText = pct == null
        ? 'No data'
        : pct == 0
            ? 'Empty'
            : pct <= 25
                ? 'Almost Empty'
                : pct <= 50
                    ? 'Half Full'
                    : pct <= 80
                        ? 'Getting Full'
                        : 'FULL';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                      color: Colors.grey.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(sublabel,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
          const SizedBox(height: 12),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fill ?? 0,
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                pct == null
                    ? Colors.white24
                    : pct >= 85
                        ? Colors.redAccent
                        : pct >= 50
                            ? Colors.orangeAccent
                            : color,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Percentage + label row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                fillLabel,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              Text(
                statusText,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
