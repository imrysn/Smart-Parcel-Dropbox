import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../services/service_locator.dart';
import '../services/websocket_service.dart';
import '../services/auth_service.dart';
import '../services/dropbox_service.dart';
import '../services/biometric_service.dart';
import 'hardware_registration_screen.dart';
import '../presentation/components/emergency_lockdown_card.dart';
import '../presentation/components/qr_access_badge_card.dart';

// ─── Door type constants matching ESP32 firmware ───────────────────────────
const String kDoorTop      = 'top';      // LOCK_TOP / REED_TOP
const String kDoorPickup   = 'pickup';   // LOCK_PICKUP / REED_PICKUP
const String kDoorReceived = 'received'; // LOCK_RECEIVED / REED_RECEIVED

// ─── Ultrasonic sensor range constants (cm) ────────────────────────────────
const double kBinEmpty  = 30.0;
const double kBinFull   =  5.0;

class DropboxControlScreen extends StatefulWidget {
  const DropboxControlScreen({super.key});

  @override
  State<DropboxControlScreen> createState() => _DropboxControlScreenState();
}

class _DropboxControlScreenState extends State<DropboxControlScreen>
    with TickerProviderStateMixin {

  late final WebSocketService _ws;
  final BiometricService _biometricService = BiometricService();
  StreamSubscription<Map<String, dynamic>>? _esp32Sub;
  StreamSubscription<Map<String, dynamic>>? _binSub;
  StreamSubscription<Map<String, dynamic>>? _unregSub;

  bool _esp32Connected = false;
  final Map<String, bool> _doorOpen = {kDoorTop: false, kDoorPickup: false, kDoorReceived: false};
  final Map<String, bool> _doorProcessing = {kDoorTop: false, kDoorPickup: false, kDoorReceived: false};
  final Map<String, bool?> _reedState = {'REED_TOP': null, 'REED_PICKUP': null, 'REED_RECEIVED': null};
  double? _pickupFill;
  double? _dropoffFill;
  int _logicalPickupCount = 0;
  int _logicalDropoffCount = 0;
  String? _userId;
  bool _hasDropbox = false;
  bool _registrationChecked = false;
  int _registeredUserCount = 0; // how many users share this device
  bool _isLockdownActive = false;
  String _currentOtp = '849204';
  int _otpSecondsLeft = 840; // 14 mins

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _ws = getIt<WebSocketService>();
    _pulseController = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _init();
  }

  Future<void> _init() async {
    final auth = getIt<AuthService>();
    _userId = await auth.currentUserId;
    if (_userId != null) {
      final dropboxService = getIt<DropboxService>();
      final dropbox = await dropboxService.getUserDropbox(_userId!);
      if (mounted) setState(() {
        _hasDropbox = dropbox != null;
        _registrationChecked = true;
        if (dropbox != null) {
          _registeredUserCount = dropbox.registeredUserCount;
          _logicalPickupCount = (dropbox as dynamic).pickupCount ?? 0;
          _logicalDropoffCount = (dropbox as dynamic).dropoffCount ?? 0;
          // Pre-fill percentages based on initial logical counts (10% per parcel)
          _pickupFill = (_logicalPickupCount / 10).clamp(0.0, 1.0);
          _dropoffFill = (_logicalDropoffCount / 10).clamp(0.0, 1.0);
        }
      });
    } else {
      if (mounted) setState(() => _registrationChecked = true);
    }
    _esp32Sub?.cancel(); _binSub?.cancel(); _unregSub?.cancel();
    _esp32Sub = _ws.esp32StatusUpdates.listen((data) { if (mounted) setState(() => _esp32Connected = data['connected'] == true); });
    _unregSub = getIt<DropboxService>().deviceUnregisteredStream.listen((data) { if (data['success'] == true) _init(); });
    _binSub = _ws.binStatusUpdates.listen((data) {
      if (!mounted) return;
      setState(() {
        final usPickup = (data['US_PICKUP'] as num?)?.toDouble();
        final usDropoff = (data['US_DROPOFF'] as num?)?.toDouble();
        
        // Use logical counts if provided by backend, else fall back to sensor
        if (data.containsKey('logicalPickupCount')) {
          _logicalPickupCount = data['logicalPickupCount'];
          _pickupFill = (_logicalPickupCount / 10).clamp(0.0, 1.0);
        } else if (usPickup != null) {
          _pickupFill = _cmToFill(usPickup);
        }
        
        if (data.containsKey('logicalDropoffCount')) {
          _logicalDropoffCount = data['logicalDropoffCount'];
          _dropoffFill = (_logicalDropoffCount / 10).clamp(0.0, 1.0);
        } else if (usDropoff != null) {
          _dropoffFill = _cmToFill(usDropoff);
        }

        if (data.containsKey('REED_TOP')) _reedState['REED_TOP'] = data['REED_TOP'];
        if (data.containsKey('REED_PICKUP')) _reedState['REED_PICKUP'] = data['REED_PICKUP'];
        if (data.containsKey('REED_RECEIVED')) _reedState['REED_RECEIVED'] = data['REED_RECEIVED'];
      });
    });
    _ws.requestEsp32Status(); _ws.requestDoorStatus();
  }

  double _cmToFill(double cm) {
    final clamped = cm.clamp(kBinFull, kBinEmpty);
    return 1.0 - ((clamped - kBinFull) / (kBinEmpty - kBinFull));
  }

  @override
  void dispose() {
    _esp32Sub?.cancel(); _binSub?.cancel(); _unregSub?.cancel();
    _pulseController.dispose(); super.dispose();
  }

  void _showOfflineError() {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: const [
          Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
          SizedBox(width: 12),
          Expanded(child: Text('Hardware Disconnected. Provide power or check WiFi.', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: UserTheme.statusError,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  /// Gate door actions behind biometric (Android) or a confirmation modal (Windows/Desktop).
  Future<void> _requestDoorAuth(String doorType) async {
    if (!_esp32Connected) {
      _showOfflineError();
      return;
    }

    final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    if (isDesktop) {
      // Windows / demo: show a styled confirmation dialog instead of biometrics
      final confirmed = await _showDesktopConfirmation(doorType);
      if (confirmed == true) _toggleDoor(doorType);
      return;
    }

    // Android/iOS: attempt biometric auth
    final biometricAvailable = await _biometricService.isBiometricAvailable();
    if (biometricAvailable) {
      final authed = await _biometricService.authenticate(
        reason: 'Confirm to ${_doorOpen[doorType]! ? 'secure' : 'unlock'} ${_doorLabel(doorType)}',
      );
      if (authed) {
        _toggleDoor(doorType);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Row(children: [
              Icon(Icons.fingerprint, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text('Biometric verification failed.', style: TextStyle(fontWeight: FontWeight.bold)),
            ]),
            backgroundColor: UserTheme.statusError,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ));
        }
      }
    } else {
      // No biometrics enrolled — proceed directly (device-level security is enough)
      _toggleDoor(doorType);
    }
  }

  Future<bool?> _showDesktopConfirmation(String doorType) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOpen = _doorOpen[doorType]!;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UserTheme.radiusL)),
        title: Row(
          children: [
            Icon(isOpen ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                color: isOpen ? UserTheme.statusError : UserTheme.primaryOrange, size: 22),
            const SizedBox(width: 10),
            Text(isOpen ? 'Secure Door?' : 'Unlock Door?',
                style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          ],
        ),
        content: Text(
          '${isOpen ? 'Lock' : 'Unlock'} the ${_doorLabel(doorType)}?\n\nOn Android this would require biometric confirmation.',
          style: TextStyle(color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL',
                style: TextStyle(color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isOpen ? 'SECURE' : 'UNLOCK',
                style: TextStyle(
                  color: isOpen ? UserTheme.statusError : UserTheme.primaryOrange,
                  fontWeight: FontWeight.bold,
                )),
          ),
        ],
      ),
    );
  }

  void _toggleDoor(String doorType) {
    if (!_esp32Connected) {
      _showOfflineError();
      return;
    }
    final isOpen = _doorOpen[doorType]!;
    setState(() { _doorProcessing[doorType] = true; _doorOpen[doorType] = !isOpen; });
    _ws.emitControlDoor(doorType, isOpen ? 'close' : 'open');
    Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _doorProcessing[doorType] = false); });
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${isOpen ? 'Closing' : 'Opening'} ${_doorLabel(doorType)}...'),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isOpen ? UserTheme.statusError : UserTheme.statusSuccess,
    ));
  }

  void _showUnregisterConfirmation() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isShared = _registeredUserCount > 1;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UserTheme.radiusL)),
        title: const Text('Remove Your Access?'),
        content: Text(
          isShared
              ? 'This will remove your access to this dropbox. $_registeredUserCount user(s) have this device registered — the device will stay active for the others.'
              : 'This will unregister the device from your account. You will need to scan the code again to reconnect.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (_userId != null) getIt<DropboxService>().unregisterDevice(_userId!);
            },
            child: const Text('REMOVE', style: TextStyle(color: UserTheme.statusError)),
          ),
        ],
      ),
    );
  }

  String _doorLabel(String doorType) {
    switch (doorType) {
      case kDoorTop: return 'Parcel Entry';
      case kDoorPickup: return 'Pickup door';
      case kDoorReceived: return 'Drop off door';
      default: return doorType;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: UserTheme.appBarGradient(context: context, title: '', centerTitle: true),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildManagementSection(),
                const SizedBox(height: 12),
                if (_hasDropbox) ...[
                  _buildConnectionBanner(),
                  const SizedBox(height: 16),
                  EmergencyLockdownCard(
                    isLockdownActive: _isLockdownActive,
                    onToggle: (val) {
                      setState(() => _isLockdownActive = val);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(val ? '⚠️ Emergency Lockdown Active' : '✅ System Security Nominal'),
                          backgroundColor: val ? UserTheme.statusError : UserTheme.statusSuccess,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  UserUi.sectionTitle(context, 'Hardware QR Access Badge', subtitle: 'Hold code in front of MH-ET barcode scanner'),
                  const SizedBox(height: 12),
                  QrAccessBadgeCard(
                    qrToken: 'SPD-QR-${DateTime.now().millisecondsSinceEpoch}',
                    onRefresh: () {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Dynamic QR Access Token Refreshed'), behavior: SnackBarBehavior.floating),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  UserUi.sectionTitle(context, 'Door Controls', subtitle: 'Control your hardware remotely'),
                  const SizedBox(height: 12),
                  _buildDoorCard(kDoorTop, 'Parcel Entry', 'Top door for courier drop-off', Icons.local_shipping_rounded, 'REED_TOP', UserTheme.primaryOrange),
                  const SizedBox(height: 14),
                  _buildDoorCard(kDoorPickup, 'Pickup door', 'Owner retrieval (Front bottom)', Icons.inventory_2_rounded, 'REED_PICKUP', UserTheme.accentAmberDark),
                  const SizedBox(height: 14),
                  _buildDoorCard(kDoorReceived, 'Drop off door', 'Owner deposit (Rear)', Icons.move_to_inbox_rounded, 'REED_RECEIVED', UserTheme.sunsetEnd),
                  const SizedBox(height: 32),
                  UserUi.sectionTitle(context, 'Internal Bins', subtitle: 'Capacities and fill levels'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildBinCard('Pickup Bin', 'US_PICKUP', _pickupFill, _logicalPickupCount, UserTheme.primaryOrange, Icons.inventory_2_rounded)),
                      const SizedBox(width: 14),
                      Expanded(child: _buildBinCard('Dropoff Bin', 'US_DROPOFF', _dropoffFill, _logicalDropoffCount, UserTheme.accentAmberDark, Icons.shopping_bag_rounded)),
                    ],
                  ),
                ] else if (_registrationChecked)
                  _buildEmptyState(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManagementSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return UserUi.surfaceCard(
      context,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.settings_input_component_rounded, color: UserTheme.primaryOrange, size: 22),
              const SizedBox(width: 12),
              Text(
                'HARDWARE CONFIG',
                style: TextStyle(
                  color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              if (_hasDropbox) ...[
                _buildStatusIndicator(),
              ],
            ],
          ),
          const SizedBox(height: 20),
          if (!_hasDropbox) ...[
            Text(
              'No smart hardware linked.',
              style: TextStyle(color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            UserUi.premiumButton(
              label: 'REGISTER HARDWARE',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HardwareRegistrationScreen())).then((_) => _init()),
              icon: Icons.qr_code_scanner_rounded,
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showWiFiConfigDialog,
                    icon: const Icon(Icons.wifi_tethering_rounded, size: 16),
                    label: const Text('WIFI'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showUnregisterConfirmation,
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('REMOVE'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: UserTheme.statusError,
                      side: const BorderSide(color: UserTheme.statusError),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    return UserUi.statusPill(
      label: _esp32Connected ? 'ONLINE' : 'OFFLINE',
      color: _esp32Connected ? UserTheme.statusSuccess : UserTheme.statusError,
    );
  }

  Widget _buildEmptyState() {
    return UserUi.emptyState(
      context,
      icon: Icons.developer_board_rounded,
      title: 'No Hardware Sync',
      subtitle: 'Sync your physical Smart Parcel Dropbox to enable remote controls and bin tracking.',
    );
  }

  void _showWiFiConfigDialog() {
    if (!_esp32Connected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hardware must be online for WiFi scan.'), behavior: SnackBarBehavior.floating));
      return;
    }
    _ws.requestWiFiScan();
    showDialog(context: context, barrierDismissible: false, builder: (context) => _WiFiScannerDialog(ws: _ws));
  }

  Widget _buildConnectionBanner() {
    final statusColor = _esp32Connected ? UserTheme.statusSuccess : UserTheme.statusError;
    final textLabel = _esp32Connected ? 'HARDWARE CONNECTED' : 'HARDWARE DISCONNECTED';
    
    return UserUi.glassCard(
      context,
      blur: 0,
      borderRadius: 12,
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: statusColor.withOpacity(0.08),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (_, __) => Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: statusColor,
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(0.6 * _pulseAnimation.value), 
                      blurRadius: 10, 
                      spreadRadius: 2
                    )
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            textLabel,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoorCard(String doorType, String title, String subtitle, IconData icon, String reedKey, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOpen = _doorOpen[doorType]!;
    final isProcessing = _doorProcessing[doorType]!;
    final reedOpen = _reedState[reedKey];

    return UserUi.surfaceCard(
      context,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: accentColor.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(subtitle, style: TextStyle(color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary, fontSize: 12)),
                  ],
                ),
              ),
              UserUi.statusPill(label: isOpen ? 'OPEN' : 'LOCKED', color: isOpen ? UserTheme.statusSuccess : UserTheme.statusError),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Icon(Icons.sensors_rounded, size: 12, color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
              const SizedBox(width: 6),
              Text(
                reedOpen == null ? 'Sensor: Unknown' : (reedOpen ? 'Sensor: OPEN' : 'Sensor: CLOSED'),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: reedOpen == true ? UserTheme.primaryOrange : (isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          UserUi.premiumButton(
            label: isProcessing ? 'PROCESSING...' : (isOpen ? 'SECURE DOOR' : 'UNLOCK DOOR'),
            onTap: isProcessing ? () {} : () => _requestDoorAuth(doorType),
            icon: isOpen ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
            color: !_esp32Connected ? Colors.grey : (isOpen ? UserTheme.statusError : accentColor),
          ),
        ],
      ),
    );
  }

  Widget _buildBinCard(String label, String sublabel, double? fill, int count, Color color, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pct = fill != null ? (fill * 100).round() : null;
    final fillLabel = '$count';

    return UserUi.surfaceCard(
      context,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: fill ?? 0,
              minHeight: 8,
              backgroundColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
              valueColor: AlwaysStoppedAnimation<Color>(fill == null ? Colors.grey : (fill > 0.8 ? UserTheme.statusError : color)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(fillLabel, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 24)),
                  const SizedBox(width: 4),
                  Text('Units', style: TextStyle(color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(fill == null ? 'Offline' : (fill > 0.85 ? 'FULL' : (count > 0 ? 'Stored' : 'Empty')), 
                       style: TextStyle(color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                  if (pct != null) 
                    Text(
                      'Scan: $pct%', 
                      style: TextStyle(fontSize: 9, color: isDark ? UserTheme.nightTextMuted.withOpacity(0.5) : UserTheme.dayTextMuted.withOpacity(0.5)),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WiFiScannerDialog extends StatefulWidget {
  final WebSocketService ws;
  const _WiFiScannerDialog({required this.ws});

  @override
  State<_WiFiScannerDialog> createState() => _WiFiScannerDialogState();
}

class _WiFiScannerDialogState extends State<_WiFiScannerDialog> {
  List<dynamic> _networks = [];
  bool _isLoading = true;
  StreamSubscription? _scanSub;

  @override
  void initState() {
    super.initState();
    _scanSub = widget.ws.wifiScanResults.listen((data) { if (mounted) setState(() { _networks = data['networks'] ?? []; _isLoading = false; }); });
    Future.delayed(const Duration(seconds: 10), () { if (mounted && _isLoading) setState(() => _isLoading = false); });
  }

  @override
  void dispose() { _scanSub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UserTheme.radiusL)),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  const Icon(Icons.wifi_find_rounded, color: UserTheme.primaryOrange),
                  const SizedBox(width: 12),
                  const Text('Select Network', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  const Spacer(),
                  if (_isLoading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: UserTheme.primaryOrange)),
                ],
              ),
            ),
            const Divider(height: 32),
            if (_networks.isEmpty && _isLoading)
              const Expanded(child: Center(child: Text('Scanning for proximity...')))
            else if (_networks.isEmpty && !_isLoading)
              const Expanded(child: Center(child: Text('No hardware pins found.')))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _networks.length + 1,
                  separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                  itemBuilder: (context, index) {
                    if (index == _networks.length) return ListTile(leading: const Icon(Icons.add_circle_outline_rounded), title: const Text('Manual Setup'), onTap: () => _promptPassword('', isManual: true));
                    final net = _networks[index];
                    final ssid = net['ssid'] ?? 'Unknown';
                    return ListTile(
                      leading: Icon(Icons.wifi_rounded, color: (net['rssi'] ?? -100) > -70 ? UserTheme.statusSuccess : UserTheme.statusWarning),
                      title: Text(ssid, style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => _promptPassword(ssid),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL'))),
            ),
          ],
        ),
      ),
    );
  }

  void _promptPassword(String ssid, {bool isManual = false}) {
    final ssidController = TextEditingController(text: ssid);
    final passController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UserTheme.radiusL)),
        title: Text(isManual ? 'Manual Config' : '$ssid Setup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isManual) TextField(controller: ssidController, decoration: const InputDecoration(labelText: 'SSID')),
            const SizedBox(height: 12),
            TextField(controller: passController, obscureText: true, decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline_rounded))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          SizedBox(
            width: 120, height: 44,
            child: UserUi.premiumButton(
              label: 'JOIN',
              fontSize: 14,
              onTap: () {
                if (ssidController.text.isNotEmpty) {
                  getIt<DropboxService>().pushHardwareConfig(ssid: ssidController.text, password: passController.text);
                  Navigator.pop(context); Navigator.pop(context);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
