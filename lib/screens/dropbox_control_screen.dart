import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  const DropboxControlScreen({super.key});

  @override
  State<DropboxControlScreen> createState() => _DropboxControlScreenState();
}

class _DropboxControlScreenState extends State<DropboxControlScreen> {

  late final WebSocketService _ws;
  StreamSubscription<Map<String, dynamic>>? _esp32Sub;
  StreamSubscription<Map<String, dynamic>>? _binSub;
  StreamSubscription<Map<String, dynamic>>? _regSub;
  StreamSubscription<Map<String, dynamic>>? _unregSub;
  StreamSubscription<Map<String, dynamic>>? _doorSub;
  StreamSubscription<bool>? _connectionSub;

  bool _esp32Connected = false;
  bool _doorStateKnown = false;
  bool _showManagement = false;
  int _manageFilterIndex = 0; // 0: All, 1: Doors, 2: Bins, 3: Access & Unit
  bool _diagnosticsExpanded = false;
  bool _isRefreshing = false;
  bool _headerTogglePressed = false;
  bool _headerToggleHovered = false;
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
            _esp32Connected = false;
            _reedState.clear();
            _clearDoorPreviews();
            _offlineOpenDoors.clear();
            _doorProcessing.updateAll((_, __) => false);
            _ownerQrToken = null;
            _ownerQrExpiry?.cancel();
            _diagnostics = null;
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
          _esp32Connected = false;
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
        _esp32Connected = data['connected'] == true;
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
      case kDoorPickup: return 'Pickup Door';
      case kDoorReceived: return 'Drop-off Door';
      default: return doorType;
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: canPop,
        appBar: canPop
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
        body: IndexedStack(
          index: _showManagement ? 1 : 0,
          sizing: StackFit.expand,
          children: [
            Stack(
              fit: StackFit.expand,
              children: [
                DropboxModelView(
                  key: ValueKey(_dropbox?.deviceId),
                  onDoorSelected: _selectModelDoor,
                  openDoors: {
                    for (final door in _reedKeys.keys) door: _modelDoorOpen(door),
                  },
                  parcelCount: _logicalDropoffCount,
                ),
                Align(
                  alignment: Alignment.topCenter,
                  child: SafeArea(
                    bottom: false,
                    child: PointerInterceptor(
                      intercepting: kIsWeb || defaultTargetPlatform == TargetPlatform.iOS,
                      child: _buildCabinetHeader(),
                    ),
                  ),
                ),
              ],
            ),
            if (_showManagement)
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _buildCabinetHeader(),
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

  Widget _buildCabinetHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: UserUi.listPadding(context, top: 6, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                UserUi.statusPill(
                  label: _esp32Connected ? 'Online' : 'Offline',
                  color: _esp32Connected ? UserTheme.statusSuccess : UserTheme.statusWarning,
                ),
                if (_esp32Connected && _logicalDropoffCount > 0)
                  Semantics(
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
                        color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildHeaderToggleButton(),
        ],
      ),
    );
  }

  Widget _buildHeaderToggleButton() {
    final openDoors = _doorOpen.values.where((open) => open).length;
    final ajarDoors = _reedState.values.where((open) => open == true).length;
    final busyDoors = _doorProcessing.values.any((busy) => busy);
    final isManageTarget = !_showManagement;
    final showBusySpinner = _isRefreshing || (isManageTarget && busyDoors);

    final fillAlpha = _headerTogglePressed
        ? 0.22
        : (_headerToggleHovered ? 0.18 : 0.14);
    final borderColor = (isManageTarget && ajarDoors > 0)
        ? UserTheme.statusWarning.withValues(alpha: _headerTogglePressed ? 0.8 : 0.6)
        : UserTheme.primaryOrange.withValues(
            alpha: _headerTogglePressed ? 0.72 : (_headerToggleHovered ? 0.56 : 0.42),
          );
    final scale = _headerTogglePressed
        ? 0.94
        : (_headerToggleHovered ? 1.03 : 1.0);

    Widget? trailingCue;
    if (isManageTarget) {
      if (ajarDoors > 0) {
        trailingCue = _buildHeaderMicroBadge(
          label: ajarDoors == 1 ? 'Ajar' : '$ajarDoors ajar',
          color: UserTheme.statusWarning,
        );
      } else if (openDoors > 0) {
        trailingCue = _buildHeaderMicroBadge(
          label: '$openDoors open',
          color: UserTheme.statusSuccess,
        );
      } else {
        trailingCue = _buildHeaderLiveDot(_esp32Connected);
      }
    } else if (_logicalDropoffCount > 0) {
      trailingCue = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: UserTheme.primaryOrange,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$_logicalDropoffCount',
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.1,
          ),
        ),
      );
    } else {
      trailingCue = _buildHeaderLiveDot(_esp32Connected);
    }

    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              _headerTogglePressed = false;
              _showManagement = !_showManagement;
            });
          },
          onHighlightChanged: (pressed) {
            if (_headerTogglePressed != pressed) {
              setState(() => _headerTogglePressed = pressed);
            }
          },
          onHover: (hovered) {
            if (_headerToggleHovered != hovered) {
              setState(() => _headerToggleHovered = hovered);
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: UserTheme.primaryOrange.withValues(alpha: fillAlpha),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.92, end: 1.0).animate(anim),
                  child: child,
                ),
              ),
              child: Row(
                key: ValueKey<bool>(_showManagement),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showBusySpinner)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: UserTheme.primaryOrange,
                      ),
                    )
                  else
                    Icon(
                      _showManagement ? Icons.view_in_ar_rounded : Icons.tune_rounded,
                      size: 16,
                      color: UserTheme.primaryOrange,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    _showManagement ? 'Dropbox' : 'Manage',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: UserTheme.primaryOrange,
                    ),
                  ),
                  const SizedBox(width: 6),
                  trailingCue,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderLiveDot(bool online) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: online
            ? UserTheme.statusSuccess
            : UserTheme.primaryOrange.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildHeaderMicroBadge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _buildManagementPage() {
    // Keep last card clear of HomeScreen's floating bottom navigation bar.
    final bottomPad = Navigator.canPop(context) ? 32.0 : 116.0;
    final showDoors = _manageFilterIndex == 0 || _manageFilterIndex == 1;
    final showBins = _manageFilterIndex == 0 || _manageFilterIndex == 2;
    final showUnit = _manageFilterIndex == 0 || _manageFilterIndex == 3;
    final openDoors = _doorOpen.values.where((open) => open).length;
    final ajarDoors = _reedState.values.where((open) => open == true).length;
    final totalParcels = _logicalPickupCount + _logicalDropoffCount;

    return RefreshIndicator(
      color: UserTheme.primaryOrange,
      onRefresh: _refreshManagement,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: UserUi.listPadding(context, top: 8, bottom: bottomPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildManagementSection(),
            if (_hasDropbox) ...[
              const SizedBox(height: 14),
              _buildManageFilterBar(),
              const SizedBox(height: 18),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showDoors) ...[
                      _buildManageSectionHeader(
                        title: 'Door Controls',
                        subtitle: 'Lock or unlock compartments remotely',
                        badgeText: ajarDoors > 0
                            ? '$ajarDoors ajar'
                            : (!_doorStateKnown
                                ? 'Syncing'
                                : (openDoors == 0 ? 'All locked' : '$openDoors unlocked')),
                        badgeColor: ajarDoors > 0 || !_doorStateKnown
                            ? UserTheme.statusWarning
                            : (openDoors > 0 ? UserTheme.statusSuccess : null),
                      ),
                      const SizedBox(height: 8),
                      _buildDoorCard(
                        kDoorTop,
                        'Parcel Entry',
                        'Top chute for courier deliveries',
                        Icons.local_shipping_rounded,
                        'REED_TOP',
                        UserTheme.primaryOrange,
                      ),
                      const SizedBox(height: 10),
                      _buildDoorCard(
                        kDoorPickup,
                        'Pickup Door',
                        'Outbound courier compartment',
                        Icons.inventory_2_rounded,
                        'REED_PICKUP',
                        UserTheme.primaryOrange,
                      ),
                      const SizedBox(height: 10),
                      _buildDoorCard(
                        kDoorReceived,
                        'Drop-off Door',
                        'Owner retrieval compartment',
                        Icons.move_to_inbox_rounded,
                        'REED_RECEIVED',
                        UserTheme.primaryOrange,
                      ),
                      if (showBins || showUnit) const SizedBox(height: 22),
                    ],
                    if (showBins) ...[
                      _buildManageSectionHeader(
                        title: 'Storage Bins',
                        subtitle: 'Live compartment fill levels',
                        badgeText: totalParcels == 1 ? '1 parcel' : '$totalParcels parcels',
                        badgeColor: totalParcels > 0 ? UserTheme.primaryOrange : null,
                      ),
                      const SizedBox(height: 8),
                      _buildStorageBinsGrid(),
                      if (showUnit) const SizedBox(height: 22),
                    ],
                    if (showUnit) ...[
                      _buildManageSectionHeader(
                        title: 'Access & Unit',
                        subtitle: 'Owner QR pass, sharing & device tools',
                        badgeText: _registeredUserCount > 1 ? '$_registeredUserCount members' : null,
                        badgeColor: UserTheme.statusInfo,
                      ),
                      const SizedBox(height: 8),
                      QrAccessBadgeCard(
                        qrToken: _ownerQrToken,
                        onRefresh: _ownerQrLoading ? null : _refreshOwnerBadge,
                      ),
                      const SizedBox(height: 14),
                      _buildAccessAndSettingsCard(),
                    ],
                  ],
                ),
              ),
            ] else if (_registrationChecked) ...[
              const SizedBox(height: 18),
              _buildEmptyState(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildManageSectionHeader({
    required String title,
    required String subtitle,
    String? badgeText,
    Color? badgeColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary;
    final secondaryText = isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary;
    final effectiveBadge = badgeColor ?? secondaryText;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 18.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (badgeText != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: effectiveBadge.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  color: effectiveBadge,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildManageFilterBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unlockedCount = _doorOpen.values.where((open) => open).length;
    final items = <(int, String, String?)>[
      (0, 'All', null),
      (1, 'Doors', unlockedCount > 0 ? '$unlockedCount open' : '3'),
      (2, 'Bins', '${_logicalPickupCount + _logicalDropoffCount}'),
      (3, 'Access', null),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final scrollable = constraints.maxWidth < 330 || textScale > 1.25;

        if (scrollable) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _buildFilterChip(
                    index: items[i].$1,
                    label: items[i].$2,
                    badge: items[i].$3,
                  ),
                ],
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? UserTheme.nightSurface : UserTheme.daySurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            children: [
              for (final item in items)
                Expanded(
                  child: _buildFilterChip(
                    index: item.$1,
                    label: item.$2,
                    badge: item.$3,
                    segmented: true,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip({
    required int index,
    required String label,
    String? badge,
    bool segmented = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = _manageFilterIndex == index;
    final radius = segmented ? 14.0 : 20.0;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected
                ? Colors.white
                : (isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary),
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.22)
                  : UserTheme.primaryOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : UserTheme.primaryOrange,
              ),
            ),
          ),
        ],
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _manageFilterIndex = index);
        },
        borderRadius: BorderRadius.circular(radius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: segmented ? 6 : 14,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: selected
                ? UserTheme.primaryOrange
                : (segmented
                    ? Colors.transparent
                    : (isDark ? UserTheme.nightCard : UserTheme.dayCard)),
            borderRadius: BorderRadius.circular(radius),
            border: segmented
                ? null
                : Border.all(
                    color: selected
                        ? UserTheme.primaryOrange
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.07)),
                  ),
          ),
          child: segmented
              ? FittedBox(fit: BoxFit.scaleDown, child: content)
              : content,
        ),
      ),
    );
  }

  Widget _buildManagementSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = !_hasDropbox
        ? UserTheme.primaryOrange
        : (_esp32Connected ? UserTheme.statusSuccess : UserTheme.statusError);
    final primaryText = isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary;
    final secondaryText = isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary;
    final unitName = (_dropbox?.name ?? '').trim().isNotEmpty
        ? _dropbox!.name
        : 'Smart Dropbox Unit';
    final wifiSsid = (_dropbox?.wifiSSID ?? '').trim();
    final statusLine = !_hasDropbox
        ? 'No hardware linked to this account'
        : (_esp32Connected
            ? (wifiSsid.isNotEmpty ? 'Connected · $wifiSsid' : 'Hardware online & synced')
            : 'Offline · Check power or Wi-Fi');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        borderRadius: BorderRadius.circular(UserTheme.radiusL),
        border: Border.all(
          color: _hasDropbox && _esp32Connected
              ? UserTheme.statusSuccess.withValues(alpha: 0.28)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: isDark ? 0.18 : 0.12),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        _hasDropbox
                            ? (_esp32Connected ? Icons.dns_rounded : Icons.cloud_off_rounded)
                            : Icons.developer_board_rounded,
                        color: statusColor,
                        size: 22,
                      ),
                    ),
                    if (_hasDropbox)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
                              width: 2.2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unitName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: primaryText,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.35,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      statusLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _hasDropbox ? statusColor : secondaryText,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_hasDropbox) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isRefreshing ? null : _refreshManagement,
                  icon: _isRefreshing
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: UserTheme.primaryOrange,
                          ),
                        )
                      : const Icon(Icons.sync_rounded, size: 19),
                  color: secondaryText,
                  tooltip: 'Refresh unit status',
                  style: IconButton.styleFrom(
                    backgroundColor: isDark ? UserTheme.nightSurface : UserTheme.daySurface,
                    minimumSize: const Size(38, 38),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ],
          ),
          if (_hasDropbox) ...[
            const SizedBox(height: 16),
            _buildUnitSnapshotStrip(),
            const SizedBox(height: 12),
            _buildDiagnostics(),
            const SizedBox(height: 14),
            _buildUnitPrimaryActions(),
          ] else ...[
            if (BleDropboxService.supported) ...[
              const SizedBox(height: 14),
              _buildUnitSettingRow(
                icon: Icons.bluetooth_searching_rounded,
                iconColor: UserTheme.statusInfo,
                title: 'Offline unlock',
                subtitle: 'Prepare or use emergency access for the received-parcel door',
                onTap: _openOfflineUnlock,
              ),
            ],
            const SizedBox(height: 14),
            UserUi.premiumButton(
              label: 'Register Hardware',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const HardwareRegistrationScreen()))
                  .then((_) => _init()),
              icon: Icons.qr_code_scanner_rounded,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUnitSnapshotStrip() {
    final unlockedCount = _doorOpen.values.where((open) => open).length;
    final ajarCount = _reedState.values.where((open) => open == true).length;
    final doorValue = !_doorStateKnown
        ? 'Syncing'
        : (ajarCount > 0
            ? '$ajarCount Ajar'
            : (unlockedCount == 0 ? 'All Locked' : '$unlockedCount Open'));
    final doorColor = ajarCount > 0 || !_doorStateKnown
        ? UserTheme.statusWarning
        : (unlockedCount > 0 ? UserTheme.statusSuccess : UserTheme.primaryOrange);

    final tiles = [
      _buildSnapshotTile(
        label: 'Doors',
        value: doorValue,
        icon: unlockedCount > 0 ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
        accent: doorColor,
        onTap: () => setState(() => _manageFilterIndex = 1),
      ),
      _buildSnapshotTile(
        label: 'Waiting',
        value: '$_logicalDropoffCount ${_logicalDropoffCount == 1 ? 'parcel' : 'parcels'}',
        icon: Icons.inventory_2_outlined,
        accent: UserTheme.primaryOrange,
        onTap: () => setState(() => _manageFilterIndex = 2),
      ),
      _buildSnapshotTile(
        label: 'Members',
        value: '$_registeredUserCount paired',
        icon: Icons.group_outlined,
        accent: UserTheme.statusInfo,
        onTap: () => setState(() => _manageFilterIndex = 3),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        if (constraints.maxWidth < 310 || textScale > 1.25) {
          return Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                tiles[i],
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: tiles[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSnapshotTile({
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? UserTheme.nightSurface : UserTheme.daySurface;

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 14, color: accent),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnitPrimaryActions() {
    final showBleRecovery = !_esp32Connected && BleDropboxService.supported && _dropbox != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedText = isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final stacked = constraints.maxWidth < 290 || textScale > 1.3;

        final primaryAction = showBleRecovery
            ? FilledButton.icon(
                onPressed: _openBluetoothWifiSetup,
                icon: const Icon(Icons.bluetooth_rounded, size: 17),
                label: const Text(
                  'Bluetooth Wi-Fi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: UserTheme.primaryOrange,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              )
            : AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _esp32Connected ? 1.0 : 0.72,
                child: OutlinedButton.icon(
                  onPressed: _showWiFiConfigDialog,
                  icon: const Icon(Icons.wifi_tethering_rounded, size: 16),
                  label: const Text(
                    'Wi-Fi Setup',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _esp32Connected ? UserTheme.primaryOrange : mutedText,
                    backgroundColor: _esp32Connected
                        ? UserTheme.primaryOrange.withValues(alpha: 0.08)
                        : Colors.transparent,
                    side: BorderSide(
                      color: _esp32Connected
                          ? UserTheme.primaryOrange.withValues(alpha: 0.45)
                          : mutedText.withValues(alpha: 0.28),
                    ),
                    minimumSize: const Size.fromHeight(44),
                    padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              );

        final secondaryAction = BleDropboxService.supported
            ? OutlinedButton.icon(
                onPressed: _openOfflineUnlock,
                icon: const Icon(Icons.bluetooth_searching_rounded, size: 16),
                label: const Text(
                  'Offline Unlock',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: UserTheme.statusInfo,
                  side: BorderSide(color: UserTheme.statusInfo.withValues(alpha: 0.35)),
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              )
            : OutlinedButton.icon(
                onPressed: _isRefreshing ? null : _refreshManagement,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _isRefreshing
                      ? const SizedBox(
                          key: ValueKey('syncing-spinner'),
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: UserTheme.primaryOrange,
                          ),
                        )
                      : const Icon(
                          Icons.sync_rounded,
                          key: ValueKey('sync-icon'),
                          size: 16,
                        ),
                ),
                label: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    _isRefreshing ? 'Syncing…' : 'Sync Unit',
                    key: ValueKey<bool>(_isRefreshing),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: UserTheme.primaryOrange,
                  backgroundColor: !_esp32Connected
                      ? UserTheme.primaryOrange.withValues(alpha: 0.10)
                      : Colors.transparent,
                  side: BorderSide(
                    color: UserTheme.primaryOrange.withValues(
                      alpha: !_esp32Connected ? 0.50 : 0.34,
                    ),
                  ),
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [primaryAction, const SizedBox(height: 8), secondaryAction],
          );
        }
        return Row(
          children: [
            Expanded(child: primaryAction),
            const SizedBox(width: 10),
            Expanded(child: secondaryAction),
          ],
        );
      },
    );
  }

  void _openBluetoothWifiSetup() {
    final id = _dropbox?.deviceId;
    if (id == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => HardwareRegistrationScreen(wifiSetupDeviceId: id),
        ))
        .then((_) {
          if (mounted) _init();
        });
  }

  Widget _buildAccessAndSettingsCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    final rows = <Widget>[
      _buildUnitSettingRow(
        icon: Icons.group_outlined,
        iconColor: UserTheme.primaryOrange,
        title: 'Household members',
        subtitle: '$_registeredUserCount ${_registeredUserCount == 1 ? 'person paired' : 'people paired'}',
        badge: '$_registeredUserCount',
        onTap: _showHouseholdMembersSheet,
      ),
      _buildUnitSettingRow(
        icon: Icons.badge_outlined,
        iconColor: UserTheme.statusSuccess,
        title: 'Trusted courier passes',
        subtitle: 'Manage recurring rider barcodes & QR badges',
        onTap: _showTrustedCouriersSheet,
      ),
      if (BleDropboxService.supported && _dropbox != null)
        _buildUnitSettingRow(
          icon: Icons.bluetooth_rounded,
          iconColor: _esp32Connected ? UserTheme.statusInfo : UserTheme.primaryOrange,
          title: 'Bluetooth Wi-Fi setup',
          subtitle: 'Reconnect an offline Dropbox to Wi-Fi',
          badge: !_esp32Connected ? 'Offline tool' : null,
          onTap: _openBluetoothWifiSetup,
        ),
      if (BleDropboxService.supported)
        _buildUnitSettingRow(
          icon: Icons.bluetooth_searching_rounded,
          iconColor: UserTheme.statusInfo,
          title: 'Offline unlock',
          subtitle: 'Emergency BLE access for the received-parcel door',
          onTap: _openOfflineUnlock,
        ),
      _buildUnitSettingRow(
        icon: Icons.link_off_rounded,
        iconColor: UserTheme.statusError,
        title: 'Unlink dropbox',
        subtitle: 'Remove hardware pairing from this account',
        titleColor: UserTheme.statusError,
        onTap: _showUnregisterConfirmation,
      ),
    ];

    return UserUi.surfaceCard(
      context,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: dividerColor),
            rows[i],
          ],
        ],
      ),
    );
  }

  void _openOfflineUnlock() {
    final box = _dropbox;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OfflineUnlockScreen(
        ownerDeviceId: box?.userId == _userId ? box?.deviceId : null,
      ),
    ));
  }

  Widget _buildDiagnostics() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final report = _diagnostics;
    final surface = isDark ? UserTheme.nightSurface : UserTheme.daySurface;
    final muted = isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary;

    if (report == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.sensors_off_rounded, size: 16, color: muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No hardware diagnostics reported yet.',
                style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
    }

    final stale = !_esp32Connected || report.isStaleAt(DateTime.now());
    final date = report.reportedAt.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date));
    final uptime = Duration(seconds: report.uptimeSeconds);
    final uptimeLabel = uptime.inHours > 0
        ? '${uptime.inHours}h ${uptime.inMinutes.remainder(60)}m'
        : uptime.inMinutes > 0
            ? '${uptime.inMinutes}m'
            : '${uptime.inSeconds}s';
    final signalColor = report.wifiRssi >= -67
        ? UserTheme.statusSuccess
        : (report.wifiRssi >= -80 ? UserTheme.statusWarning : UserTheme.statusError);
    final signalLabel = report.wifiRssi >= -67
        ? 'Strong'
        : (report.wifiRssi >= -80 ? 'Fair' : 'Weak');

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _diagnosticsExpanded = !_diagnosticsExpanded);
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: stale ? UserTheme.statusWarning : UserTheme.statusSuccess,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      stale ? 'Telemetry · Stale' : 'Telemetry · Live',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _diagnosticsExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: muted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildDiagPill(
                    icon: Icons.wifi_rounded,
                    color: signalColor,
                    text: '${report.wifiRssi} dBm · $signalLabel',
                  ),
                  _buildDiagPill(
                    icon: Icons.schedule_rounded,
                    color: UserTheme.statusInfo,
                    text: uptimeLabel,
                  ),
                  _buildDiagPill(
                    icon: Icons.memory_rounded,
                    color: UserTheme.primaryOrange,
                    text: 'v${report.firmwareVersion}',
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: !_diagnosticsExpanded
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Last report: ${localizations.formatShortDate(date)} $time',
                              style: TextStyle(fontSize: 11.5, color: muted),
                            ),
                            if ((_dropbox?.wifiSSID ?? '').isNotEmpty)
                              Text(
                                'Network: ${_dropbox!.wifiSSID}',
                                style: TextStyle(fontSize: 11.5, color: muted),
                              ),
                            if (_dropbox != null)
                              Text(
                                'Unit ID: ${_dropbox!.deviceId}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontFamily: 'monospace',
                                  color: muted,
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDiagPill({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitSettingRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color iconColor = UserTheme.primaryOrange,
    Color? titleColor,
    String? badge,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: titleColor ??
                          (isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: iconColor,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
            ),
          ],
        ),
      ),
    );
  }

  void _showHouseholdMembersSheet() {
    final deviceId = _dropbox?.deviceId;
    if (deviceId == null || deviceId.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HouseholdMembersSheet(
        deviceId: deviceId,
        currentUserId: _userId ?? '',
        onChanged: _init,
      ),
    );
  }

  void _showTrustedCouriersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TrustedCouriersSheet(),
    );
  }

  Widget _buildEmptyState() {
    return UserUi.emptyState(
      context,
      icon: Icons.developer_board_rounded,
      title: 'No Hardware Synced',
      subtitle: 'Link your physical Smart Parcel Dropbox to enable remote doors and live bin tracking.',
    );
  }

  void _showWiFiConfigDialog() {
    if (!_esp32Connected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hardware must be online for Wi-Fi setup.'), behavior: SnackBarBehavior.floating));
      return;
    }
    _ws.requestWiFiScan();
    showDialog(context: context, barrierDismissible: false, builder: (context) => _WiFiScannerDialog(ws: _ws));
  }

  Widget _buildDoorCard(
    String doorType,
    String title,
    String subtitle,
    IconData icon,
    String reedKey,
    Color accentColor,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOpen = _doorOpen[doorType]!;
    final isProcessing = _doorProcessing[doorType]!;
    final anyProcessing = _doorProcessing.values.any((pending) => pending);
    final reedOpen = _reedState[reedKey] == true;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);

    final statusLabel = !_doorStateKnown
        ? 'Unknown'
        : (isOpen ? 'Unlocked' : 'Locked');
    final statusColor = !_doorStateKnown
        ? UserTheme.statusWarning
        : (isOpen ? UserTheme.statusSuccess : UserTheme.statusError);
    final borderColor = reedOpen
        ? UserTheme.statusWarning.withValues(alpha: isDark ? 0.5 : 0.45)
        : (isOpen && _doorStateKnown
            ? UserTheme.statusSuccess.withValues(alpha: isDark ? 0.45 : 0.35)
            : (isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06)));
    final iconColor = reedOpen ? UserTheme.statusWarning : accentColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        borderRadius: BorderRadius.circular(UserTheme.radiusL),
        border: Border.all(color: borderColor, width: reedOpen ? 1.3 : 1),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackAction = constraints.maxWidth < 300 || textScale > 1.25;
          final actionPill = _buildDoorActionPill(
            doorType: doorType,
            isOpen: isOpen,
            isProcessing: isProcessing,
            disabled: anyProcessing,
            expandedLabel: stackAction,
            accentColor: accentColor,
          );

          final infoContent = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: isDark ? 0.16 : 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark
                            ? UserTheme.nightTextPrimary
                            : UserTheme.dayTextPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark
                            ? UserTheme.nightTextMuted
                            : UserTheme.dayTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildDoorStatusChip(statusLabel, statusColor),
                        if (reedOpen)
                          _buildDoorStatusChip(
                            'Ajar',
                            UserTheme.statusWarning,
                            icon: Icons.sensor_door_outlined,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!stackAction) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: actionPill,
                ),
              ],
            ],
          );

          if (!stackAction) return infoContent;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              infoContent,
              const SizedBox(height: 14),
              actionPill,
            ],
          );
        },
      ),
    );
  }

  Widget _buildDoorStatusChip(String label, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ] else ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoorActionPill({
    required String doorType,
    required bool isOpen,
    required bool isProcessing,
    required bool disabled,
    required bool expandedLabel,
    required Color accentColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final buttonColor = !_esp32Connected
        ? (isDark ? Colors.grey.shade700 : Colors.grey.shade500)
        : (isOpen ? UserTheme.statusError : accentColor);
    final label = isProcessing
        ? (expandedLabel ? 'Waiting for dropbox…' : 'Syncing…')
        : (!_doorStateKnown
            ? (expandedLabel ? 'Refresh lock state' : 'Sync')
            : (isOpen
                ? (expandedLabel ? 'Lock Door' : 'Lock')
                : (expandedLabel ? 'Unlock Door' : 'Unlock')));
    final actionIcon = !_doorStateKnown
        ? Icons.sync_rounded
        : (isOpen ? Icons.lock_outline_rounded : Icons.lock_open_rounded);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: disabled && !isProcessing ? 0.55 : 1.0,
      child: Material(
        color: buttonColor,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: disabled
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  _toggleDoor(doorType);
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: const BoxConstraints(minHeight: 42),
            padding: EdgeInsets.symmetric(
              horizontal: expandedLabel ? 16 : 14,
              vertical: 10,
            ),
            child: Row(
              mainAxisSize: expandedLabel ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isProcessing)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  Icon(actionIcon, size: 17, color: Colors.white),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStorageBinsGrid() {
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final pickupCard = _buildBinCard(
      'Pickup Bin',
      'Awaiting courier',
      _pickupFill,
      _logicalPickupCount,
      UserTheme.primaryOrange,
      Icons.inventory_2_rounded,
    );
    final deliveryCard = _buildBinCard(
      'Delivery Bin',
      'Incoming parcels',
      _dropoffFill,
      _logicalDropoffCount,
      UserTheme.primaryOrange,
      Icons.shopping_bag_rounded,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 320 || textScale > 1.3) {
          return Column(
            children: [
              pickupCard,
              const SizedBox(height: 12),
              deliveryCard,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: pickupCard),
            const SizedBox(width: 12),
            Expanded(child: deliveryCard),
          ],
        );
      },
    );
  }

  Widget _buildBinCard(
    String label,
    String sublabel,
    double? fill,
    int count,
    Color color,
    IconData icon,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final clampedFill = fill?.clamp(0.0, 1.0);
    final pct = clampedFill != null ? (clampedFill * 100).round() : null;
    final unitLabel = count == 1 ? 'parcel' : 'parcels';
    final barColor = clampedFill == null
        ? Colors.grey
        : (clampedFill > 0.85
            ? UserTheme.statusError
            : (clampedFill > 0.65 ? UserTheme.statusWarning : color));
    final statusLabel = clampedFill == null
        ? 'Offline'
        : (clampedFill > 0.85 ? 'Full' : (count == 0 ? 'Empty' : 'Active'));

    return UserUi.surfaceCard(
      context,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.16 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: barColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  pct != null ? '$pct%' : '--',
                  style: TextStyle(
                    color: barColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark
                  ? UserTheme.nightTextPrimary
                  : UserTheme.dayTextPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sublabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
            ),
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: clampedFill ?? 0),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '$count $unitLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                statusLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: clampedFill != null && clampedFill > 0.85
                      ? UserTheme.statusError
                      : (isDark
                          ? UserTheme.nightTextMuted
                          : UserTheme.dayTextSecondary),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
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
              const Expanded(child: Center(child: Text('Scanning for nearby networks...')))
            else if (_networks.isEmpty && !_isLoading)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'No Wi-Fi networks found nearby.',
                      style: TextStyle(color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => _promptPassword('', isManual: true),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 18, color: UserTheme.primaryOrange),
                      label: const Text('Enter Wi-Fi Manually', style: TextStyle(color: UserTheme.primaryOrange, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _networks.length + 1,
                  separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
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
              child: Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
            ),
          ],
        ),
      ),
    );
  }

  void _promptPassword(String ssid, {bool isManual = false}) async {
    final ssidController = TextEditingController(text: ssid);
    final passController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isJoining = false;

    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: !isJoining,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final targetSsid = ssidController.text.trim();
          final isValid = targetSsid.isNotEmpty;

          return AlertDialog(
            backgroundColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UserTheme.radiusL)),
            title: Text(isManual ? 'Manual Config' : '$ssid Setup'),
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
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            actions: [
              TextButton(
                onPressed: isJoining ? null : () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 100, minHeight: 42),
                child: UserUi.premiumButton(
                  label: isJoining ? 'Connecting...' : 'Connect',
                  fontSize: 13,
                  fullWidth: false,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  isLoading: isJoining,
                  color: !isValid || isJoining ? Colors.grey : null,
                  onTap: () async {
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
                            content: Text('Pushing Wi-Fi credentials for "$targetSsid"...'),
                            backgroundColor: UserTheme.primaryOrange,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                      
                      await Future.delayed(const Duration(milliseconds: 600));
                      if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                    } catch (e) {
                      if (dialogContext.mounted) {
                        setDialogState(() => isJoining = false);
                      }
                    }
                  },
                ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messenger = ScaffoldMessenger.of(context);

    final added = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        bool saving = false;
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UserTheme.radiusL)),
            title: const Text('Add Household Member', style: TextStyle(fontWeight: FontWeight.w800)),
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
                        color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Member Email Address',
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
                onPressed: saving ? null : () => Navigator.pop(dialogCtx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: UserTheme.primaryOrange,
                  foregroundColor: Colors.white,
                ),
                child: Text(saving ? 'Adding...' : 'Add Member'),
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
      final invite = await _dropboxService.createHouseholdInvite(deviceId: widget.deviceId);
      if (!mounted) return;
      setState(() => _creatingInvite = false);

      final token = (invite['token'] ?? '').toString();
      final pin = (invite['pin'] ?? '').toString();
      final deviceName = (invite['deviceName'] ?? 'Smart Parcel Dropbox').toString();
      final isDark = Theme.of(context).brightness == Brightness.dark;

      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: isDark ? UserTheme.nightCard : UserTheme.dayCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UserTheme.radiusL)),
          title: const Text('Household Invite Code', style: TextStyle(fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Have your family member open Register Dropbox on their phone and scan this QR or enter the 6-digit PIN for "$deviceName".',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
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
                  child: QrImageView(
                    data: token,
                    version: QrVersions.auto,
                    size: 164,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? UserTheme.nightSurface : UserTheme.daySurface,
                    borderRadius: BorderRadius.circular(UserTheme.radiusM),
                  ),
                  child: Text(
                    pin,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                      color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Expires in 15 minutes · Single-use',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: pin.isNotEmpty ? pin : token));
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
            TextButton(
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary;
    final secondaryText = isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary;
    final cardColor = isDark ? UserTheme.nightCard : UserTheme.dayCard;
    final surfaceColor = isDark ? UserTheme.nightSurface : UserTheme.daySurface;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(UserTheme.radiusXL)),
      ),
      padding: EdgeInsets.fromLTRB(
        UserUi.horizontalGutter(context),
        16,
        UserUi.horizontalGutter(context),
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.78),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Household Members',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: primaryText),
            ),
            const SizedBox(height: 10),
            if (!_loading && _isPrimaryOwner) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _showAddMemberDialog,
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
                      label: const Text('Add by Email', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: UserTheme.primaryOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _creatingInvite ? null : _showInviteCodeDialog,
                      icon: _creatingInvite
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.qr_code_2_rounded, size: 18),
                      label: const Text('Invite QR / PIN', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Pair family members directly from your phone without walking out to the box.',
                style: TextStyle(fontSize: 12, color: secondaryText, height: 1.35),
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
                  style: TextStyle(fontSize: 12.5, color: secondaryText, height: 1.4),
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator(color: UserTheme.primaryOrange)),
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
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                  itemBuilder: (context, index) {
                    final member = _members[index];
                    final id = (member['id'] ?? '').toString();
                    final name = (member['fullName'] ?? '').toString().trim();
                    final email = (member['email'] ?? '').toString();
                    final isPrimary = member['isPrimaryOwner'] == true;
                    final isSelf = id == widget.currentUserId;
                    final displayName = name.isNotEmpty ? name : (email.isNotEmpty ? email : 'Member');

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: UserTheme.primaryOrange.withValues(alpha: 0.12),
                        child: Text(
                          displayName[0].toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: UserTheme.primaryOrange,
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
                            const Text(
                              'Owner',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: UserTheme.primaryOrange,
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: email.isNotEmpty
                          ? Text(email, style: TextStyle(fontSize: 12, color: secondaryText))
                          : null,
                      trailing: (_isPrimaryOwner && !isPrimary && !isSelf)
                          ? IconButton(
                              icon: const Icon(Icons.person_remove_outlined, color: UserTheme.statusError, size: 20),
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

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Trusted Courier Pass'),
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
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty || idCtrl.text.trim().length < 3) return;
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
    final qrSize = (MediaQuery.sizeOf(context).shortestSide * 0.5).clamp(160.0, 210.0);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: QrImageView(
                data: riderId,
                version: QrVersions.auto,
                size: qrSize,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              riderId,
              style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary;
    final secondaryText = isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary;
    final cardColor = isDark ? UserTheme.nightCard : UserTheme.dayCard;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(UserTheme.radiusXL)),
      ),
      padding: EdgeInsets.fromLTRB(
        UserUi.horizontalGutter(context),
        16,
        UserUi.horizontalGutter(context),
        MediaQuery.of(context).padding.bottom + 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.74),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Trusted Courier Passes',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: primaryText),
                  ),
                ),
                TextButton.icon(
                  onPressed: _showAddPassDialog,
                  icon: const Icon(Icons.add_rounded, size: 18, color: UserTheme.primaryOrange),
                  label: const Text(
                    'Add Pass',
                    style: TextStyle(color: UserTheme.primaryOrange, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator(color: UserTheme.primaryOrange)),
              )
            else if (_passes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No recurring courier passes yet. Tap Add Pass to register one.',
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
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                  itemBuilder: (context, index) {
                    final pass = _passes[index];
                    final id = (pass['_id'] ?? '').toString();
                    final riderId = (pass['riderId'] ?? '').toString();
                    final name = (pass['name'] ?? 'Courier').toString();

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      leading: const Icon(Icons.motorcycle_rounded, color: UserTheme.primaryOrange, size: 22),
                      title: Text(
                        name,
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: primaryText),
                      ),
                      subtitle: Text(
                        riderId,
                        style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: secondaryText),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.qr_code_rounded, color: UserTheme.primaryOrange, size: 20),
                            tooltip: 'Show QR Pass',
                            onPressed: () => _showQrModal(riderId, name),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: UserTheme.statusError, size: 20),
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
