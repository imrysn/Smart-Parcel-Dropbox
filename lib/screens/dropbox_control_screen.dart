import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dropoff_batches_screen.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../config/user_theme.dart';
import '../models/dropbox_model.dart';
import '../widgets/dropbox_model_view.dart';
import '../widgets/user_ui.dart';
import '../services/service_locator.dart';
import '../services/websocket_service.dart';
import '../services/auth_service.dart';
import '../services/ble_dropbox_service.dart';
import '../services/dropbox_service.dart';
import '../services/device_control_service.dart';
import '../services/input_validator.dart';
import 'hardware_registration_screen.dart';
import 'bluetooth_access_screen.dart';
import '../presentation/components/qr_access_badge_card.dart';

// ─── Door type constants matching ESP32 firmware ───────────────────────────
const String kDoorTop      = 'top';      // LOCK_TOP / REED_TOP
const String kDoorPickup   = 'pickup';   // LOCK_PICKUP / REED_PICKUP
const String kDoorReceived = 'received'; // LOCK_RECEIVED / REED_RECEIVED

// ─── Ultrasonic sensor range constants (cm) ────────────────────────────────
const double kBinEmpty  = 30.0;
const double kBinFull   =  5.0;

class DropboxControlScreen extends StatefulWidget {
  const DropboxControlScreen({
    super.key,
    this.simulationEnabled = false,
    this.embeddedInTab = false,
    this.onHardwareConnectionChanged,
  });

  final bool simulationEnabled;
  final bool embeddedInTab;
  final ValueChanged<bool?>? onHardwareConnectionChanged;

  @override
  State<DropboxControlScreen> createState() => _DropboxControlScreenState();
}

class _DropboxControlScreenState extends State<DropboxControlScreen> {

  late final WebSocketService _ws;
  StreamSubscription<Map<String, dynamic>>? _esp32Sub;
  StreamSubscription<Map<String, dynamic>>? _binSub;
  StreamSubscription<Map<String, dynamic>>? _deliverySub;
  StreamSubscription<Map<String, dynamic>>? _regSub;
  StreamSubscription<Map<String, dynamic>>? _unregSub;
  StreamSubscription<Map<String, dynamic>>? _doorSub;
  StreamSubscription<bool>? _connectionSub;

  bool? _hardwareConnected;
  bool get _esp32Connected => _hardwareConnected == true;
  bool _doorStateKnown = false;
  bool _showManagement = false;
  int _manageFilterIndex = 0;
  bool _diagnosticsExpanded = false;
  bool _isRefreshing = false;
  final Map<String, bool> _doorOpen = {kDoorTop: false, kDoorPickup: false, kDoorReceived: false};
  final Map<String, bool> _doorProcessing = {kDoorTop: false, kDoorPickup: false, kDoorReceived: false};
  static const _reedKeys = {kDoorTop: 'REED_TOP', kDoorPickup: 'REED_PICKUP', kDoorReceived: 'REED_RECEIVED'};
  final Map<String, bool?> _reedState = {};
  final Map<String, bool> _doorPreviews = {};
  final Map<String, Timer> _doorPreviewTimers = {};
  final Set<String> _offlineOpenDoors = {};
  double? _pickupFill;
  double? _dropoffFill;
  int _logicalPickupCount = 0;
  int _logicalDropoffCount = 0;
  DateTime? _latestDelivery;
  String? _userId;
  Dropbox? _dropbox;
  HardwareDiagnostics? _diagnostics;
  Timer? _diagnosticsExpiry;
  bool _hasDropbox = false;
  bool _registrationChecked = false;
  int _registeredUserCount = 0; // how many users share this device
  String? _ownerQrToken;
  bool _ownerQrLoading = false;
  Timer? _ownerQrExpiry;
  final bool _soundEnabled = true;

  @override
  void initState() {
    super.initState();
    _ws = getIt<WebSocketService>();
    _init();
  }

  Future<void> _init() async {
    final auth = getIt<AuthService>();
    _userId = await auth.currentUserId;
    if (_userId != null) {
      final dropboxService = getIt<DropboxService>();
      final dropbox = await dropboxService.getUserDropbox(_userId!);
      if (mounted) {
        setState(() {
          if (dropbox?.deviceId != _dropbox?.deviceId) {
            _doorStateKnown = false;
            _setHardwareConnection(
              dropbox == null || _ws.isConnected ? null : false,
            );
            _reedState.clear();
            _clearDoorPreviews();
            _offlineOpenDoors.clear();
            _doorProcessing.updateAll((_, __) => false);
            _ownerQrToken = null;
            _ownerQrExpiry?.cancel();
            _diagnostics = null;
            _latestDelivery = null;
          }
          _dropbox = dropbox;
          _updateDiagnostics(dropbox?.diagnostics);
          _hasDropbox = dropbox != null;
          _registrationChecked = true;
          if (dropbox != null) {
            _registeredUserCount = dropbox.registeredUserCount;
            _logicalPickupCount = dropbox.pickupCount;
            _logicalDropoffCount = dropbox.dropoffCount;
            // Pre-fill percentages based on initial logical counts (10% per parcel)
            _pickupFill = (_logicalPickupCount / 10).clamp(0.0, 1.0);
            _dropoffFill = (_logicalDropoffCount / 10).clamp(0.0, 1.0);
          } else {
            _registeredUserCount = 0;
            _logicalPickupCount = 0;
            _logicalDropoffCount = 0;
          }
        });
      }
    } else {
      if (mounted) setState(() => _registrationChecked = true);
    }
    if (!mounted) return;
    _esp32Sub?.cancel(); _binSub?.cancel(); _regSub?.cancel(); _unregSub?.cancel(); _doorSub?.cancel(); _connectionSub?.cancel();
    _connectionSub = _ws.connectionStatusStream.listen((connected) {
      if (!mounted) return;
      if (connected) {
        _requestHardwareState();
      } else {
        setState(() {
          _setHardwareConnection(_dropbox == null ? null : false);
          _doorStateKnown = false;
          _reedState.clear();
          _clearDoorPreviews();
        });
      }
    });
    _esp32Sub = _ws.esp32StatusUpdates.listen((data) {
      if (!mounted || !_matchesDropbox(data)) return;
      final wasOnline = _esp32Connected;
      setState(() {
        _setHardwareConnection(data['connected'] == true);
        _updateDiagnostics(HardwareDiagnostics.tryParse(data['diagnostics']));
        if (!_esp32Connected) {
          _doorStateKnown = false;
          _reedState.clear();
          _clearDoorPreviews();
        } else if (!wasOnline) {
          _offlineOpenDoors.clear();
        }
      });
      if (_esp32Connected && (!wasOnline || !_doorStateKnown)) {
        _ws.requestDoorStatus();
      }
    });
    _regSub = getIt<DropboxService>().deviceRegisteredStream.listen((_) => _init());
    _unregSub = getIt<DropboxService>().deviceUnregisteredStream.listen((data) {
      if (data['success'] == true || data['removedByOwner'] == true) _init();
    });
    _doorSub = _ws.doorStateUpdates.listen(_applyDoorState);
    _deliverySub?.cancel();
    _deliverySub = _ws.trackingStatusChanges.listen((data) {
      if (!mounted || !_matchesDropbox(data) ||
          data['mode'] != 'drop_off' || data['status'] != 'delivered') {
        return;
      }
      setState(() => _latestDelivery = DateTime.now());
    });
    _binSub = _ws.binStatusUpdates.listen((data) {
      if (!mounted || !_matchesDropbox(data)) return;
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

        _readReedState(data);
      });
    });
    _requestHardwareState();
  }

  bool _matchesDropbox(Map<String, dynamic> data) =>
      _dropbox != null && data['deviceId'] == _dropbox!.deviceId;

  void _setHardwareConnection(bool? connected) {
    if (_hardwareConnected == connected) return;
    _hardwareConnected = connected;
    widget.onHardwareConnectionChanged?.call(connected);
  }

  void _updateDiagnostics(HardwareDiagnostics? reading) {
    if (reading != null && !(_diagnostics?.reportedAt.isAfter(reading.reportedAt) ?? false)) {
      _diagnostics = reading;
    }
    _diagnosticsExpiry?.cancel();
    final report = _diagnostics;
    if (report == null) return;
    final remaining = report.reportedAt.add(HardwareDiagnostics.freshness).difference(DateTime.now());
    if (remaining > Duration.zero) {
      _diagnosticsExpiry = Timer(remaining, () {
        if (mounted) setState(() {});
      });
    }
  }

  void _requestHardwareState() {
    _ws.requestEsp32Status();
    _ws.requestDoorStatus();
  }

  void _applyDoorState(Map<String, dynamic> data, {bool readReeds = true}) {
    if (!mounted || !_esp32Connected || !_matchesDropbox(data)) return;
    if (data['parcelDoorOpen'] is! bool || data['pickupDoorOpen'] is! bool || data['receivedDoorOpen'] is! bool) return;
    setState(() {
      _doorOpen[kDoorTop] = data['parcelDoorOpen'] as bool;
      _doorOpen[kDoorPickup] = data['pickupDoorOpen'] as bool;
      _doorOpen[kDoorReceived] = data['receivedDoorOpen'] as bool;
      _doorStateKnown = true;
      if (readReeds) _readReedState(data);
    });
  }

  void _readReedState(Map<String, dynamic> data) {
    if (!_esp32Connected) return;
    for (final entry in _reedKeys.entries) {
      final reading = data[entry.value];
      final open = switch (reading) {
        true || 1 => true,
        false || 0 => false,
        _ => null,
      };
      if (open == null) continue;
      final previous = _reedState[entry.value];
      _reedState[entry.value] = open;
      if (open == _doorPreviews[entry.key] ||
          (previous != null && previous != open)) {
        _clearDoorPreview(entry.key);
      }
    }
  }

  bool _modelDoorOpen(String door) => _esp32Connected
      ? (_doorPreviews[door] ?? _reedState[_reedKeys[door]] ?? false)
      : _offlineOpenDoors.contains(door);

  void _clearDoorPreview(String door) {
    _doorPreviews.remove(door);
    _doorPreviewTimers.remove(door)?.cancel();
  }

  void _clearDoorPreviews() {
    for (final timer in _doorPreviewTimers.values) {
      timer.cancel();
    }
    _doorPreviewTimers.clear();
    _doorPreviews.clear();
  }

  double _cmToFill(double cm) {
    final clamped = cm.clamp(kBinFull, kBinEmpty);
    return 1.0 - ((clamped - kBinFull) / (kBinEmpty - kBinFull));
  }

  @override
  void dispose() {
    _clearDoorPreviews();
    _diagnosticsExpiry?.cancel();
    _esp32Sub?.cancel(); _binSub?.cancel(); _regSub?.cancel(); _unregSub?.cancel(); _doorSub?.cancel(); _connectionSub?.cancel();
    _ownerQrExpiry?.cancel();
    _deliverySub?.cancel();
    super.dispose();
  }

  void _showOfflineError() {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Row(
        children: [
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

  Future<void> _toggleDoor(String doorType, {bool fromModel = false}) async {
    if (!_doorOpen.containsKey(doorType)) return;
    if (!_esp32Connected) {
      _showOfflineError();
      return;
    }
    final deviceId = _dropbox?.deviceId;
    if (deviceId == null || _doorProcessing.values.any((pending) => pending)) return;
    if (!_doorStateKnown) {
      _requestHardwareState();
      if (fromModel) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Checking the door. Try again in a moment.'),
        ));
      }
      return;
    }
    final shouldUnlock = !(_doorOpen[doorType]! ||
        (fromModel && _modelDoorOpen(doorType)));
    setState(() {
      _doorProcessing[doorType] = true;
      if (fromModel) {
        _clearDoorPreview(doorType);
        _doorPreviews[doorType] = shouldUnlock;
        _doorPreviewTimers[doorType] = Timer(const Duration(seconds: 15), () {
          if (mounted) setState(() => _clearDoorPreview(doorType));
        });
      }
    });
    try {
      final state = await getIt<DeviceControlService>().setDoorLock(
        doorType: doorType, unlock: shouldUnlock, deviceId: deviceId,
      );
      if (!mounted || _dropbox?.deviceId != deviceId) return;
      _applyDoorState(state, readReeds: false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${_doorLabel(doorType)} ${shouldUnlock ? 'unlocked' : 'locked'}'),
      ));
    } catch (error) {
      if (!mounted || _dropbox?.deviceId != deviceId) return;
      setState(() {
        _doorStateKnown = false;
        _clearDoorPreview(doorType);
      });
      _requestHardwareState();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error is StateError ? error.message : 'The dropbox did not confirm the lock state.'),
      ));
    } finally {
      if (mounted && _dropbox?.deviceId == deviceId) {
        setState(() => _doorProcessing[doorType] = false);
      }
    }
  }

  void _selectModelDoor(String doorType) {
    if (!_reedKeys.containsKey(doorType)) return;
    if (!_esp32Connected) {
      setState(() {
        if (!_offlineOpenDoors.remove(doorType)) {
          _offlineOpenDoors.add(doorType);
        }
      });
      return;
    }
    if (_dropbox == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Register your Dropbox to control its doors.'),
      ));
      return;
    }
    unawaited(_toggleDoor(doorType, fromModel: true));
  }

  Future<void> _refreshOwnerBadge() async {
    if (_ownerQrLoading) return;
    final deviceId = _dropbox?.deviceId;
    setState(() => _ownerQrLoading = true);
    try {
      final pass = await _ws.requestOwnerPass();
      if (!mounted || _dropbox?.deviceId != deviceId) return;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(pass['expiresAt'] as int);
      _ownerQrExpiry?.cancel();
      setState(() => _ownerQrToken = pass['token'] as String);
      _ownerQrExpiry = Timer(expiresAt.difference(DateTime.now()), () {
        if (mounted) setState(() => _ownerQrToken = null);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create an access QR. Check your connection.')),
        );
      }
    } finally {
      if (mounted) setState(() => _ownerQrLoading = false);
    }
  }

  void _showUnregisterConfirmation() {
    final isShared = _registeredUserCount > 1;
    UserUi.showDashboardDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove your access?'),
        scrollable: true,
        content: Text(
          isShared
              ? 'This will remove your access to this dropbox. $_registeredUserCount user(s) have this device registered — the device will stay active for the others.'
              : 'This will unregister the device from your account. You will need to scan the code again to reconnect.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            style: UserUi.dashboardFilledStyle(context, destructive: true),
            onPressed: () {
              Navigator.pop(context);
              if (_userId != null) {
                getIt<DropboxService>().unregisterDevice(_userId!);
              }
            },
            child: const Text('Remove access'),
          ),
        ],
      ),
    );
  }

  String _doorLabel(String doorType) {
    switch (doorType) {
      case kDoorTop: return 'Parcel Entry';
      case kDoorPickup: return 'Pickup Door';
      case kDoorReceived: return 'Drop-off Door';
      default: return doorType;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showAppBar = !widget.embeddedInTab &&
        (ModalRoute.of(context)?.canPop ?? false);

    return Container(
      decoration: _showManagement
          ? BoxDecoration(color: UserUi.dashboardColors(context).background)
          : UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: showAppBar,
        appBar: showAppBar
            ? UserTheme.appBarGradient(
                context: context,
                title: 'Dropbox Control',
                centerTitle: false,
                backgroundColor: Colors.transparent,
                leading: PointerInterceptor(
                  intercepting: kIsWeb || defaultTargetPlatform == TargetPlatform.iOS,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              )
            : null,
        body: Stack(
          fit: StackFit.expand,
          children: [
            IndexedStack(
              index: _showManagement ? 1 : 0,
              sizing: StackFit.expand,
              children: [
                DropboxModelView(
                  key: ValueKey(_dropbox?.deviceId),
                  simulationEnabled: widget.simulationEnabled,
                  soundEnabled: _soundEnabled,
                  onDoorSelected: _selectModelDoor,
                  openDoors: {
                    for (final door in _reedKeys.keys) door: _modelDoorOpen(door),
                  },
                  parcelCount: _logicalDropoffCount,
                  hardwareOnline: _esp32Connected,
                  anyDoorUnlocked: _doorStateKnown ? _doorOpen.containsValue(true) : null,
                  latestDelivery: _latestDelivery,
                  headerBuilder: (weatherControl) => Align(
                    alignment: Alignment.topCenter,
                    child: SafeArea(
                      bottom: false,
                      child: _buildCabinetHeader(weatherControl: weatherControl),
                    ),
                  ),
                ),
                if (_showManagement)
                  SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        _buildManagementHeader(),
                        Expanded(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) => Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, (1 - value) * 10),
                                child: child,
                              ),
                            ),
                            child: _buildManagementPage(),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshManagement() async {
    if (_isRefreshing) return;
    HapticFeedback.lightImpact();
    setState(() => _isRefreshing = true);
    try {
      if (_esp32Connected) {
        _requestHardwareState();
      }
      await _init();
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  Widget _buildCabinetHeader({Widget? weatherControl}) {
    final intercept = kIsWeb || defaultTargetPlatform == TargetPlatform.iOS;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: UserUi.listPadding(context, top: 6, bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_esp32Connected && _logicalDropoffCount > 0)
                      PointerInterceptor(
                        intercepting: intercept,
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _logicalDropoffCount == 1
                                ? '1 parcel waiting'
                                : '$_logicalDropoffCount parcels waiting',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? UserTheme.nightTextSecondary
                                  : UserTheme.dayTextSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PointerInterceptor(
                intercepting: intercept,
                child: _buildHeaderToggleButton(),
              ),
            ],
          ),
          if (weatherControl != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: PointerInterceptor(
                intercepting: intercept,
                child: weatherControl,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderToggleButton() {
    final busyDoors = _doorProcessing.values.any((busy) => busy);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: 'Open Dropbox Management',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _showManagement = true);
          },
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 110,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDark ? UserTheme.nightCard : Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: busyDoors
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : Text(
                    'Manage',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? UserTheme.nightTextPrimary : Colors.black,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Color get _manageForeground => UserUi.dashboardColors(context).foreground;

  TextStyle get _manageSecondaryText => TextStyle(
    fontSize: 13,
    color: UserUi.dashboardColors(context).secondary,
  );

  Widget _buildManagementHeader() {
    return Padding(
      padding: UserUi.listPadding(context),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton(
          onPressed: () => setState(() => _showManagement = false),
          style: TextButton.styleFrom(foregroundColor: _manageForeground),
          child: const Text('Back to 3D'),
        ),
      ),
    );
  }

  Widget _buildManagementPage() {
    final bottomPadding = widget.embeddedInTab ? 116.0 : 32.0;
    final showDoors = _manageFilterIndex == 0 || _manageFilterIndex == 1;
    final showBins = _manageFilterIndex == 0 || _manageFilterIndex == 2;
    final showAccess = _manageFilterIndex == 0 || _manageFilterIndex == 3;
    final foreground = _manageForeground;

    return OutlinedButtonTheme(
      data: OutlinedButtonThemeData(style: UserUi.dashboardOutlineStyle(context)),
      child: RefreshIndicator(
        color: foreground,
        onRefresh: _refreshManagement,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: UserUi.listPadding(context, top: 0, bottom: bottomPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_registrationChecked)
                UserUi.shimmerCard(context)
              else if (!_hasDropbox)
                _buildUnlinkedDropbox()
              else ...[
                _buildUnitSummary(),
                const SizedBox(height: UserUi.dashboardSpacing),
                _buildManageFilterBar(),
                if (showDoors) ...[
                  const SizedBox(height: UserUi.dashboardSpacing),
                  UserUi.sectionTitle(
                    context,
                    'Door Controls',
                    fontSize: 16,
                    subtitle: !_esp32Connected
                        ? 'Connect the Dropbox to use remote door controls.'
                        : (!_doorStateKnown
                              ? 'Waiting for lock status.'
                              : null),
                  ),
                  _buildDoorControls(),
                ],
                if (showBins) ...[
                  const SizedBox(height: UserUi.dashboardSpacing),
                  UserUi.sectionTitle(context, 'Storage Bins', fontSize: 16),
                  _buildStorageBinsGrid(),
                ],
                if (showAccess) ...[
                  const SizedBox(height: UserUi.dashboardSpacing),
                  UserUi.sectionTitle(context, 'Access & Unit', fontSize: 16),
                  QrAccessBadgeCard(
                    qrToken: _ownerQrToken,
                    onRefresh: _ownerQrLoading ? null : _refreshOwnerBadge,
                  ),
                  const SizedBox(height: UserUi.sS),
                  _buildAccessAndSettingsCard(),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManageFilterBar() {
    const filters = ['All', 'Doors', 'Bins', 'Access'];
    return Wrap(
      spacing: UserUi.sS,
      children: [
        for (final (index, label) in filters.indexed)
          UserUi.dashboardFilterChip(
            context,
            label: label,
            selected: _manageFilterIndex == index,
            onSelected: (selected) {
              if (selected) setState(() => _manageFilterIndex = index);
            },
          ),
      ],
    );
  }

  Widget _buildUnitSummary() {
    final unitName = _dropbox!.name.trim();
    final wifiSsid = (_dropbox?.wifiSSID ?? '').trim();
    final status = switch (_hardwareConnected) {
      true => wifiSsid.isEmpty ? 'Connected' : 'Connected · $wifiSsid',
      false => 'Offline · Check power or Wi-Fi',
      null => 'Checking connection…',
    };
    final showBleSetup = !_esp32Connected && BleDropboxService.supported;
    final setupButton = OutlinedButton(
      onPressed: showBleSetup
          ? _openBluetoothWifiSetup
          : (_esp32Connected ? _showWiFiConfigDialog : null),
      child: Text(showBleSetup ? 'Bluetooth Wi-Fi' : 'Wi-Fi Setup'),
    );
    final syncButton = OutlinedButton(
      onPressed: _isRefreshing ? null : _refreshManagement,
      child: Text(_isRefreshing ? 'Syncing…' : 'Sync Unit'),
    );

    return UserUi.dashboardCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            unitName.isEmpty ? 'Smart Parcel Dropbox' : unitName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Semantics(
            liveRegion: true,
            child: Text(status, style: _manageSecondaryText),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 270 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.25) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    setupButton,
                    const SizedBox(height: 4),
                    syncButton,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: setupButton),
                  const SizedBox(width: UserUi.sS),
                  Expanded(child: syncButton),
                ],
              );
            },
          ),
          const Divider(height: UserUi.sM),
          _buildDiagnostics(),
        ],
      ),
    );
  }

  Widget _buildUnlinkedDropbox() {
    return UserUi.emptyState(
      context,
      icon: Icons.inventory_2_outlined,
      title: 'Set Up Your Dropbox',
      subtitle: 'Link your Dropbox to manage doors and track parcels.',
      action: Column(
        children: [
          OutlinedButton(
            onPressed: () => Navigator.of(context)
                .push(
                  MaterialPageRoute(
                    builder: (_) => const HardwareRegistrationScreen(),
                  ),
                )
                .then((_) {
                  if (mounted) _init();
                }),
            child: const Text('Register Hardware'),
          ),
          if (BleDropboxService.supported)
            TextButton(
              onPressed: _openOfflineUnlock,
              style: TextButton.styleFrom(foregroundColor: _manageForeground),
              child: const Text('Offline unlock'),
            ),
        ],
      ),
    );
  }

  void _openBluetoothWifiSetup() {
    final id = _dropbox?.deviceId;
    if (id == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => HardwareRegistrationScreen(wifiSetupDeviceId: id),
          ),
        )
        .then((_) {
          if (mounted) _init();
        });
  }

  Widget _buildAccessAndSettingsCard() {
    final rows = [
      _buildUnitSettingRow(
        title: 'Household members',
        subtitle:
            '$_registeredUserCount ${_registeredUserCount == 1 ? 'person paired' : 'people paired'}',
        onTap: _showHouseholdMembersSheet,
      ),
      _buildUnitSettingRow(
        title: 'Trusted courier passes',
        subtitle: 'Manage rider barcodes and QR passes',
        onTap: _showTrustedCouriersSheet,
      ),
      if (BleDropboxService.supported && _esp32Connected)
        _buildUnitSettingRow(
          title: 'Bluetooth Wi-Fi setup',
          subtitle: 'Connect the Dropbox to another Wi-Fi network',
          onTap: _openBluetoothWifiSetup,
        ),
      if (BleDropboxService.supported)
        _buildUnitSettingRow(
          title: 'Offline unlock',
          subtitle: 'Use Bluetooth to unlock the drop-off door',
          onTap: _openOfflineUnlock,
        ),
      _buildUnitSettingRow(
        title: 'Drop-off batches',
        subtitle: 'Review parcels the chute sensor could not confirm',
        onTap: _openDropoffBatches,
      ),
      _buildUnitSettingRow(
        title: 'Unlink Dropbox',
        subtitle: 'Remove this Dropbox from your account',
        titleColor: Theme.of(context).colorScheme.onErrorContainer,
        onTap: _showUnregisterConfirmation,
      ),
    ];

    return UserUi.dashboardCard(
      context,
      padding: const EdgeInsets.symmetric(
        horizontal: UserUi.dashboardSpacing,
        vertical: 4,
      ),
      child: Column(
        children: [
          for (final (index, row) in rows.indexed) ...[
            if (index > 0) const Divider(height: 1),
            row,
          ],
        ],
      ),
    );
  }

  void _openDropoffBatches() {
    final box = _dropbox;
    if (box == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DropoffBatchesScreen(deviceId: box.deviceId),
      ),
    );
  }

  void _openOfflineUnlock() {
    final box = _dropbox;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OfflineUnlockScreen(
          ownerDeviceId: box?.userId == _userId ? box?.deviceId : null,
        ),
      ),
    );
  }

  Widget _buildDiagnostics() {
    final report = _diagnostics;
    final stale = !_esp32Connected || report?.isStaleAt(DateTime.now()) == true;
    final localizations = MaterialLocalizations.of(context);

    return ExpansionTile(
      initiallyExpanded: _diagnosticsExpanded,
      onExpansionChanged: (expanded) => _diagnosticsExpanded = expanded,
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      textColor: _manageForeground,
      iconColor: _manageSecondaryText.color,
      childrenPadding: const EdgeInsets.only(bottom: UserUi.sS),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      title: const Text(
        'Hardware details',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      children: [
        if (report == null)
          Text('No hardware readings yet.', style: _manageSecondaryText)
        else ...[
          Text(
            stale ? 'Last available readings' : 'Current readings',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Firmware: ${report.firmwareVersion}',
            style: _manageSecondaryText,
          ),
          Text(
            'Wi-Fi signal: ${report.wifiRssi} dBm',
            style: _manageSecondaryText,
          ),
          Text(
            'Uptime: ${_formatUptime(report.uptimeSeconds)}',
            style: _manageSecondaryText,
          ),
          Text(
            'Last report: ${localizations.formatShortDate(report.reportedAt.toLocal())} '
            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(report.reportedAt.toLocal()))}',
            style: _manageSecondaryText,
          ),
        ],
        if ((_dropbox?.wifiSSID ?? '').isNotEmpty)
          Text('Network: ${_dropbox!.wifiSSID}', style: _manageSecondaryText),
        Text('Unit ID: ${_dropbox!.deviceId}', style: _manageSecondaryText),
      ],
    );
  }

  String _formatUptime(int seconds) {
    final uptime = Duration(seconds: seconds);
    if (uptime.inHours > 0) {
      return '${uptime.inHours}h ${uptime.inMinutes.remainder(60)}m';
    }
    if (uptime.inMinutes > 0) return '${uptime.inMinutes}m';
    return '${uptime.inSeconds}s';
  }

  Widget _buildUnitSettingRow({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? titleColor,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(
          color: titleColor,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(subtitle, style: _manageSecondaryText),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: _manageSecondaryText.color,
      ),
      onTap: onTap,
    );
  }

  void _showHouseholdMembersSheet() {
    final deviceId = _dropbox?.deviceId;
    if (deviceId == null || deviceId.isEmpty) return;
    UserUi.showDashboardSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HouseholdMembersSheet(
        deviceId: deviceId,
        currentUserId: _userId ?? '',
        onChanged: _init,
      ),
    );
  }

  void _showTrustedCouriersSheet() {
    UserUi.showDashboardSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _TrustedCouriersSheet(),
    );
  }

  void _showWiFiConfigDialog() {
    if (!_esp32Connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hardware must be online for Wi-Fi setup.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _ws.requestWiFiScan();
    UserUi.showDashboardDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _WiFiScannerDialog(ws: _ws),
    );
  }

  Widget _buildDoorControls() {
    return UserUi.dashboardCard(
      context,
      padding: const EdgeInsets.symmetric(
        horizontal: UserUi.dashboardSpacing,
        vertical: 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDoorRow(
            kDoorTop,
            'Parcel Entry',
            'Top chute for courier deliveries',
          ),
          const Divider(height: 1),
          _buildDoorRow(kDoorPickup, 'Pickup Door', 'For courier pickups'),
          const Divider(height: 1),
          _buildDoorRow(
            kDoorReceived,
            'Drop-off Door',
            'For retrieving deliveries',
          ),
        ],
      ),
    );
  }

  Widget _buildDoorRow(String doorType, String title, String purpose) {
    final unlocked = _doorOpen[doorType]!;
    final ajar = _reedState[_reedKeys[doorType]] == true;
    final processing = _doorProcessing[doorType]!;
    final controlsAvailable =
        _esp32Connected &&
        _doorStateKnown &&
        !_doorProcessing.containsValue(true);
    final actionLabel = processing
        ? 'Updating…'
        : (unlocked ? 'Lock' : 'Unlock');
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(purpose, style: _manageSecondaryText),
        if (_doorStateKnown || ajar) ...[
          const SizedBox(height: 4),
          Semantics(
            liveRegion: true,
            child: Text(
              [
                if (_doorStateKnown) unlocked ? 'Unlocked' : 'Locked',
                if (ajar) 'Door ajar',
              ].join(' · '),
              style: _manageSecondaryText.copyWith(
                fontWeight: FontWeight.w700,
                color: ajar ? UserUi.dashboardColors(context).accent : null,
              ),
            ),
          ),
        ],
      ],
    );
    final action = OutlinedButton(
      onPressed: controlsAvailable ? () => _toggleDoor(doorType) : null,
      child: Text(actionLabel),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 260 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.25) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [details, const SizedBox(height: 4), action],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 12),
              action,
            ],
          );
        },
      ),
    );
  }

  Widget _buildStorageBinsGrid() {
    final pickup = _buildBinCard(
      'Pickup Bin',
      'Awaiting courier',
      _pickupFill,
      _logicalPickupCount,
    );
    final delivery = _buildBinCard(
      'Delivery Bin',
      'Incoming parcels',
      _dropoffFill,
      _logicalDropoffCount,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.25) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pickup,
              const SizedBox(height: UserUi.sS),
              delivery,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: pickup),
            const SizedBox(width: UserUi.sS),
            Expanded(child: delivery),
          ],
        );
      },
    );
  }

  Widget _buildBinCard(String title, String purpose, double? fill, int count) {
    final level = fill?.clamp(0.0, 1.0);
    final capacity = level == null
        ? 'Fill level unavailable'
        : '${(level * 100).round()}% estimated full';
    final foreground = _manageForeground;
    return UserUi.dashboardCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(purpose, style: _manageSecondaryText),
          const SizedBox(height: 10),
          Text(
            '$count ${count == 1 ? 'parcel' : 'parcels'}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          if (level != null) ...[
            ExcludeSemantics(
              child: LinearProgressIndicator(
                value: level,
                minHeight: 5,
                borderRadius: BorderRadius.circular(3),
                backgroundColor: foreground.withValues(alpha: 0.12),
                color: level > 0.85
                    ? Theme.of(context).colorScheme.error
                    : foreground,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(capacity, style: _manageSecondaryText),
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
    final colors = UserUi.dashboardColors(context);
    return Dialog(
      child: Container(
        width: double.infinity,
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Icon(Icons.wifi_find_rounded, color: colors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Select Wi-Fi network',
                        style: Theme.of(context).dialogTheme.titleTextStyle),
                  ),
                  if (_isLoading)
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: UserTheme.primaryOrange)),
                ],
              ),
            ),
            const Divider(height: 32),
            if (_networks.isEmpty && _isLoading)
              const Expanded(
                  child: Center(child: Text('Scanning for nearby networks...')))
            else if (_networks.isEmpty && !_isLoading)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'No Wi-Fi networks found nearby.',
                      style: TextStyle(color: colors.secondary),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => _promptPassword('', isManual: true),
                      icon: const Icon(Icons.add_circle_outline_rounded,
                          size: 18),
                      label: const Text('Enter Wi-Fi manually'),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _networks.length + 1,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: colors.border),
                  itemBuilder: (context, index) {
                    if (index == _networks.length) {
                      return ListTile(
                          leading: const Icon(Icons.add_circle_outline_rounded),
                          title: const Text('Manual setup'),
                          onTap: () => _promptPassword('', isManual: true));
                    }
                    final net = _networks[index];
                    final ssid = net['ssid'] ?? 'Unknown';
                    return ListTile(
                      leading: Icon(Icons.wifi_rounded,
                          color: (net['rssi'] ?? -100) > -70
                              ? UserTheme.statusSuccess
                              : UserTheme.statusWarning),
                      title: Text(ssid,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () => _promptPassword(ssid),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'))),
            ),
          ],
        ),
      ),
    );
  }

  void _promptPassword(String ssid, {bool isManual = false}) async {
    final ssidController = TextEditingController(text: ssid);
    final passController = TextEditingController();
    bool isJoining = false;

    final success = await UserUi.showDashboardDialog<bool>(
      context: context,
      barrierDismissible: !isJoining,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final targetSsid = ssidController.text.trim();
          final isValid = targetSsid.isNotEmpty;

          return AlertDialog(
            title:
                Text(isManual ? 'Set up Wi-Fi manually' : 'Connect to $ssid'),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isManual)
                  TextField(
                    controller: ssidController,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(labelText: 'SSID'),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: passController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isJoining
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isJoining || !isValid
                    ? null
                    : () async {
                        if (targetSsid.isEmpty) return;
                        setDialogState(() => isJoining = true);

                        try {
                          getIt<DropboxService>().pushHardwareConfig(
                            ssid: targetSsid,
                            password: passController.text,
                          );

                          if (dialogContext.mounted) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Pushing Wi-Fi credentials for "$targetSsid"...'),
                                backgroundColor: UserTheme.primaryOrange,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }

                          await Future.delayed(
                              const Duration(milliseconds: 600));
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            setDialogState(() => isJoining = false);
                          }
                        }
                      },
                child: Text(isJoining ? 'Connecting…' : 'Connect'),
              ),
            ],
          );
        },
      ),
    );

    if (success == true && mounted) {
      Navigator.pop(context);
    }
  }
}

class _HouseholdMembersSheet extends StatefulWidget {
  final String deviceId;
  final String currentUserId;
  final VoidCallback onChanged;

  const _HouseholdMembersSheet({
    required this.deviceId,
    required this.currentUserId,
    required this.onChanged,
  });

  @override
  State<_HouseholdMembersSheet> createState() => _HouseholdMembersSheetState();
}

class _HouseholdMembersSheetState extends State<_HouseholdMembersSheet> {
  final _dropboxService = getIt<DropboxService>();
  bool _loading = true;
  bool _creatingInvite = false;
  bool _isPrimaryOwner = false;
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _dropboxService.getDeviceMembers(widget.deviceId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _isPrimaryOwner = res?['isPrimaryOwner'] == true;
      final list = res?['members'];
      _members = list is List ? list.cast<Map<String, dynamic>>() : [];
    });
  }

  Future<void> _showAddMemberDialog() async {
    final formKey = GlobalKey<FormState>();
    final emailCtrl = TextEditingController();
    final colors = UserUi.dashboardColors(context);
    final messenger = ScaffoldMessenger.of(context);

    final added = await UserUi.showDashboardDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        bool saving = false;
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Add household member'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Enter the email of the family member\'s account. They will get instant access without needing to touch the physical box.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.secondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Member email address',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                      validator: InputValidator.validateEmail,
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorText!,
                        style: const TextStyle(
                          color: UserTheme.statusError,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    saving ? null : () => Navigator.pop(dialogCtx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() {
                          saving = true;
                          errorText = null;
                        });
                        try {
                          await _dropboxService.addDeviceMember(
                            deviceId: widget.deviceId,
                            email: emailCtrl.text.trim(),
                          );
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                        } catch (e) {
                          setDialogState(() {
                            saving = false;
                            errorText = e.toString();
                          });
                        }
                      },
                child: Text(saving ? 'Adding...' : 'Add member'),
              ),
            ],
          ),
        );
      },
    );

    emailCtrl.dispose();
    if (added == true && mounted) {
      widget.onChanged();
      await _load();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Household member added!'),
          backgroundColor: UserTheme.statusSuccess,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showInviteCodeDialog() async {
    if (_creatingInvite) return;
    setState(() => _creatingInvite = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final invite = await _dropboxService.createHouseholdInvite(
          deviceId: widget.deviceId);
      if (!mounted) return;
      setState(() => _creatingInvite = false);

      final token = (invite['token'] ?? '').toString();
      final pin = (invite['pin'] ?? '').toString();
      final deviceName =
          (invite['deviceName'] ?? 'Smart Parcel Dropbox').toString();
      final colors = UserUi.dashboardColors(context);

      await UserUi.showDashboardDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Household invite code'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Have your family member open Register Dropbox on their phone and scan this QR or enter the 6-digit PIN for "$deviceName".',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.secondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(UserTheme.radiusM),
                  ),
                    child: SizedBox.square(
                      dimension: 164,
                      child: QrImageView(
                        data: token,
                        version: QrVersions.auto,
                        backgroundColor: Colors.white,
                      ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(UserTheme.radiusM),
                  ),
                  child: Text(
                    pin,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                      color: colors.foreground,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Expires in 15 minutes · Single-use',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colors.secondary,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: pin.isNotEmpty ? pin : token));
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Invite PIN copied to clipboard'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 17),
              label: const Text('Copy PIN'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) {
        widget.onChanged();
        await _load();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creatingInvite = false);
        messenger.showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: UserTheme.statusError,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _removeMember(String memberId, String label) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _dropboxService.removeDeviceMember(
        deviceId: widget.deviceId,
        memberId: memberId,
      );
      widget.onChanged();
      await _load();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Removed $label from household access'),
          backgroundColor: UserTheme.statusSuccess,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: UserTheme.statusError,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = UserUi.dashboardColors(context);
    final primaryText = colors.foreground;
    final secondaryText = colors.secondary;
    final surfaceColor = colors.background;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Household members',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            if (!_loading && _isPrimaryOwner) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: _showAddMemberDialog,
                    child: const Text('Add by email'),
                  ),
                  OutlinedButton(
                    onPressed: _creatingInvite ? null : _showInviteCodeDialog,
                    child: Text(_creatingInvite
                        ? 'Creating invite…'
                        : 'Invite QR / PIN'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Pair family members directly from your phone without walking out to the box.',
                style:
                    TextStyle(fontSize: 12, color: secondaryText, height: 1.35),
              ),
            ] else if (!_loading) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(UserTheme.radiusM),
                ),
                child: Text(
                  'Only the primary owner can add or remove household members in the app.',
                  style: TextStyle(
                      fontSize: 12.5, color: secondaryText, height: 1.4),
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                    child: CircularProgressIndicator(
                        color: UserTheme.primaryOrange)),
              )
            else if (_members.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No household members found.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondaryText),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _members.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: colors.border,
                  ),
                  itemBuilder: (context, index) {
                    final member = _members[index];
                    final id = (member['id'] ?? '').toString();
                    final name = (member['fullName'] ?? '').toString().trim();
                    final email = (member['email'] ?? '').toString();
                    final isPrimary = member['isPrimaryOwner'] == true;
                    final isSelf = id == widget.currentUserId;
                    final displayName = name.isNotEmpty
                        ? name
                        : (email.isNotEmpty ? email : 'Member');

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: colors.accent.withValues(alpha: 0.12),
                        child: Text(
                          displayName[0].toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: colors.accent,
                          ),
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              isSelf ? '$displayName (You)' : displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: primaryText,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isPrimary) ...[
                            const SizedBox(width: 8),
                            Text(
                              'Owner',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: colors.accent,
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: email.isNotEmpty
                          ? Text(email,
                              style:
                                  TextStyle(fontSize: 12, color: secondaryText))
                          : null,
                      trailing: (_isPrimaryOwner && !isPrimary && !isSelf)
                          ? IconButton(
                              icon: const Icon(Icons.person_remove_outlined,
                                  color: UserTheme.statusError, size: 20),
                              tooltip: 'Remove member',
                              onPressed: () => _removeMember(id, displayName),
                            )
                          : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrustedCouriersSheet extends StatefulWidget {
  const _TrustedCouriersSheet();

  @override
  State<_TrustedCouriersSheet> createState() => _TrustedCouriersSheetState();
}

class _TrustedCouriersSheetState extends State<_TrustedCouriersSheet> {
  final _dropboxService = getIt<DropboxService>();
  bool _loading = true;
  List<Map<String, dynamic>> _passes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _dropboxService.getTrustedCouriers();
    if (!mounted) return;
    setState(() {
      _passes = items;
      _loading = false;
    });
  }

  void _showAddPassDialog() {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    bool saving = false;

    UserUi.showDashboardDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add trusted courier pass'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Register a recurring courier badge or manifest ID so your rider can unlock the dropbox directly.',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Courier / Rider Name',
                    hintText: 'e.g. J&T Express · Regular Rider',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: idCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Pass / Badge ID',
                    hintText: 'e.g. RIDER-JNT-01',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty ||
                          idCtrl.text.trim().length < 3) {
                        return;
                      }
                      setDialogState(() => saving = true);
                      final nav = Navigator.of(dialogContext);
                      try {
                        await _dropboxService.addTrustedCourier(
                          riderId: idCtrl.text,
                          name: nameCtrl.text,
                        );
                        if (dialogContext.mounted) nav.pop();
                        await _load();
                      } catch (e) {
                        setDialogState(() => saving = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(e.toString()),
                            backgroundColor: UserTheme.statusError,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
              child: Text(saving ? 'Adding...' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showQrModal(String riderId, String name) {
    final qrSize =
        (MediaQuery.sizeOf(context).shortestSide * 0.5).clamp(160.0, 210.0);
    UserUi.showDashboardDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(name),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SizedBox.square(
                dimension: qrSize,
                child: QrImageView(
                  data: riderId,
                  version: QrVersions.auto,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              riderId,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePass(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _dropboxService.removeTrustedCourier(id);
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: UserTheme.statusError,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = UserUi.dashboardColors(context);
    final primaryText = colors.foreground;
    final secondaryText = colors.secondary;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.74),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Trusted courier passes',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  onPressed: _showAddPassDialog,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text(
                    'Add pass',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                    child: CircularProgressIndicator(
                        color: UserTheme.primaryOrange)),
              )
            else if (_passes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No recurring courier passes yet. Tap Add pass to register one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondaryText, fontSize: 13),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _passes.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: colors.border,
                  ),
                  itemBuilder: (context, index) {
                    final pass = _passes[index];
                    final id = (pass['_id'] ?? '').toString();
                    final riderId = (pass['riderId'] ?? '').toString();
                    final name = (pass['name'] ?? 'Courier').toString();

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      leading: Icon(Icons.motorcycle_rounded,
                          color: colors.accent, size: 22),
                      title: Text(
                        name,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: primaryText),
                      ),
                      subtitle: Text(
                        riderId,
                        style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: secondaryText),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.qr_code_rounded,
                                color: colors.accent, size: 20),
                            tooltip: 'Show QR Pass',
                            onPressed: () => _showQrModal(riderId, name),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                color: UserTheme.statusError, size: 20),
                            tooltip: 'Revoke Pass',
                            onPressed: () => _deletePass(id),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
