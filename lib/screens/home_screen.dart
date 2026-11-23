import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/database_service.dart';
import '../services/delivery_push_service.dart';
import '../services/dropbox_service.dart';
import '../services/secure_storage_service.dart';
import '../services/websocket_service.dart';
import '../services/service_locator.dart';
import '../models/tracking_model.dart';
import 'add_tracking_screen.dart';
import 'tracking_details_screen.dart';
import 'dropbox_control_screen.dart';
import '../widgets/notification_badge.dart';
import 'add_pickup_screen.dart';
import '../widgets/user_ui.dart';
import '../config/user_theme.dart';
import '../presentation/screens/home/home_dashboard_tab.dart';
import '../presentation/screens/orders/orders_tab.dart';
import '../presentation/screens/profile/profile_tab.dart';

/// Home Screen - Main dashboard showing active orders
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _devModePreference = 'dropbox_dev_mode';

  final AuthService _authService = AuthService();
  final _preferences = SecureStorageService();
  final DatabaseService _databaseService = DatabaseService();
  final DropboxService _dropboxService = getIt<DropboxService>();
  final BiometricService _biometricService = getIt.isRegistered<BiometricService>()
      ? getIt<BiometricService>()
      : BiometricService();
  int _selectedIndex = 0;
  int _ordersMode = 0; // 0: Inbound (Deliveries), 1: Outbound (Pickups)
  int _inboundFilterIndex = 0; // 0: All, 1: In Box, 2: Pending, 3: Retrieved
  int _outboundFilterIndex = 0; // 0: All, 1: Awaiting Pickup, 2: Completed

  bool _hasDropbox = true;
  bool _devModeEnabled =
      kDebugMode && !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  bool _devModeBusy = true;

  bool get _supportsDevMode =>
      kIsWeb ||
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.windows,
      }.contains(defaultTargetPlatform);

  // Stream subscriptions for cleanup
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Map<String, dynamic>>? _registrationSub;
  StreamSubscription<Map<String, dynamic>>? _unregistrationSub;
  DeliveryPushService? _deliveryPush;

  bool _appConnected = false;
  bool? _dropboxHardwareConnected;

  // Current user ID
  String? _userId;

  @override
  void initState() {
    super.initState();
    _initUser();
    if (_supportsDevMode) unawaited(_restoreDevMode());
  }

  Future<void> _restoreDevMode() async {
    final saved = await _preferences.getPreference(_devModePreference);
    if (!mounted) return;
    setState(() {
      if (saved != null) _devModeEnabled = saved == 'true';
      _devModeBusy = false;
    });
  }

  Future<void> _setDevMode(bool enabled) async {
    if (_devModeBusy) return;
    setState(() => _devModeBusy = true);
    final saved = await _preferences.savePreference(
      _devModePreference,
      enabled.toString(),
    );
    if (!mounted) return;
    setState(() {
      if (saved) _devModeEnabled = enabled;
      _devModeBusy = false;
    });
    if (!saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save Dev mode. Try again.')),
      );
    }
  }

  Future<void> _initUser() async {
    _userId = await _authService.currentUserId;
    _appConnected = getIt<WebSocketService>().isConnected;
    if (mounted) {
      _setupStreams();
      if (_userId != null) {
        _checkDropbox();
      }
      setState(() {});
    }
  }

  Future<void> _checkDropbox() async {
    if (_userId == null) return;
    try {
      final dropbox = await _dropboxService.getUserDropbox(_userId!);
      if (mounted) {
        setState(() {
          _hasDropbox = dropbox != null && dropbox.isRegistered;
        });
      }
    } catch (e) {
      debugPrint('Error checking dropbox status on home: $e');
    }
  }

  @override
  void dispose() {
    _deliveryPush?.pendingTap.removeListener(_openDeliveryTap);
    _connectionSub?.cancel();
    _registrationSub?.cancel();
    _unregistrationSub?.cancel();
    super.dispose();
  }

  void _setupStreams() {
    // Initialize streams lazily only when needed
    if (_userId != null) {
      // Establish WebSocket connection
      _databaseService.initSocket(_userId!);
      if (getIt.isRegistered<DeliveryPushService>()) {
        final push = getIt<DeliveryPushService>();
        _deliveryPush = push;
        push.pendingTap.addListener(_openDeliveryTap);
        unawaited(push.sync(_userId!));
        unawaited(_openDeliveryTap());
      }

      // ── WebSocket Connectivity & Auto-Refresh ──
      _connectionSub?.cancel();
      _connectionSub = _databaseService.connectionStatusStream.listen((connected) {
        if (mounted) {
          setState(() => _appConnected = connected);
          if (connected) {
            debugPrint('🔄 WebSocket reconnected, auto-refreshing data');
            _checkDropbox();
          }
        }
      });

      // ── Real-time Registration Sync ──
      _registrationSub?.cancel();
      _unregistrationSub?.cancel();
      // Listen to both registration and unregistration to update _hasDropbox
      _registrationSub = _databaseService.deviceRegisteredStream.listen((_) => _checkDropbox());
      _unregistrationSub = _databaseService.deviceUnregisteredStream.listen((_) => _checkDropbox());
    }
  }

  Future<void> _openDeliveryTap() async {
    final push = _deliveryPush;
    final userId = _userId;
    final eventId = push?.pendingTap.value;
    if (push == null || userId == null || eventId == null || !mounted) return;
    push.pendingTap.value = null;
    TrackingModel? parcel;
    try {
      parcel = await push.loadParcel(eventId, userId);
    } catch (_) {
      // The parcel stays in notification history if the network is unavailable.
    }
    if (!mounted || _databaseService.sessionUserId != userId) return;
    if (parcel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Parcel details are unavailable.')),
      );
      return;
    }
    final tracking = parcel;
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TrackingDetailsScreen(tracking: tracking),
    )));
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Smart Parcel Dropbox';
      case 1:
        return 'Orders';
      case 2:
        return 'Dropbox';
      case 3:
        return 'Profile';
      default:
        return 'Smart Parcel Dropbox';
    }
  }

  void _selectTab(int index) {
    if (index != _selectedIndex) _dropboxHardwareConnected = null;
    _selectedIndex = index;
  }

  void _updateDropboxHardwareConnection(bool? connected) {
    if (!mounted || _selectedIndex != 2 || _dropboxHardwareConnected == connected) {
      return;
    }
    setState(() => _dropboxHardwareConnected = connected);
  }

  Widget _buildConnectivityIndicator() {
    final ok = _appConnected;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = ok ? UserTheme.statusSuccess : (isDark ? UserTheme.nightTextSecondary : UserTheme.primaryOrange);

    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        ok ? 'Live' : 'Offline',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: statusColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final showingCabinet = _selectedIndex == 2;
    final interceptCabinet = showingCabinet &&
        (kIsWeb || defaultTargetPlatform == TargetPlatform.iOS);
    
    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: showingCabinet,
        appBar: UserTheme.appBarGradient(
          context: context,
          title: _getAppBarTitle(),
          titleSuffix: showingCabinet && _dropboxHardwareConnected == false
              ? UserUi.hardwareOfflineDot()
              : null,
          centerTitle: false,
          backgroundColor: showingCabinet ? Colors.transparent : null,
          actions: [
            if (_selectedIndex == 1)
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, color: UserTheme.primaryOrange, size: 22),
                tooltip: _ordersMode == 0 ? 'Add Tracking ID' : 'Schedule Pickup',
                onPressed: () {
                  if (_ordersMode == 0) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AddTrackingScreen()),
                    );
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AddPickupScreen()),
                    ).then((_) => _databaseService.refreshTracking(_userId!));
                  }
                },
              ),
            if (_userId != null)
              PointerInterceptor(
                intercepting: interceptCabinet,
                child: NotificationBadge(
                  userId: _userId!,
                  databaseService: _databaseService,
                  onSelectTab: (tabIndex, {subTabIndex}) {
                    setState(() {
                      _selectTab(tabIndex);
                      if (subTabIndex != null) {
                        if (subTabIndex == 2) {
                          _ordersMode = 1;
                        } else {
                          _ordersMode = 0;
                          _inboundFilterIndex = subTabIndex == 0 ? 2 : (subTabIndex == 1 ? 1 : 3);
                        }
                      }
                    });
                  },
                ),
              ),
            if (_selectedIndex != 2) _buildConnectivityIndicator(),
            const SizedBox(width: 12),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: EdgeInsets.fromLTRB(UserUi.horizontalGutter(context), 0, UserUi.horizontalGutter(context), 14),
                child: PointerInterceptor(
                  intercepting: interceptCabinet,
                  child: Container(
                  height: 62,
                  decoration: BoxDecoration(
                    color: (isDark ? UserTheme.nightCard : UserTheme.dayCard)
                        .withValues(alpha: UserTheme.floatingSurfaceOpacity),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(4, (index) {
                      final isSelected = _selectedIndex == index;
                      IconData icon; IconData activeIcon; String label;
                      if (index == 0) { icon = Icons.grid_view_outlined; activeIcon = Icons.grid_view_rounded; label = 'Home'; }
                      else if (index == 1) { icon = Icons.inventory_2_outlined; activeIcon = Icons.inventory_2_rounded; label = 'Orders'; }
                      else if (index == 2) { icon = Icons.dns_outlined; activeIcon = Icons.dns_rounded; label = 'Dropbox'; }
                      else { icon = Icons.person_outline_rounded; activeIcon = Icons.person_rounded; label = 'Profile'; }

                      final inactiveColor = isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary;
                      final selectedColor = index == 2
                          ? (isDark ? UserTheme.primaryOrangeLight : UserTheme.primaryOrangeOnLight)
                          : UserTheme.primaryOrange;

                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectTab(index);
                              if (index <= 1 && _userId != null) {
                                _databaseService.refreshTracking(_userId!);
                                if (index == 0) _checkDropbox();
                              }
                            });
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  isSelected ? activeIcon : icon,
                                  size: 22,
                                  color: isSelected ? selectedColor : inactiveColor,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? selectedColor : inactiveColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: _getSelectedTab(),
      ),
    );
  }

  Widget _getSelectedTab() {
    switch (_selectedIndex) {
      case 0:
        if (_userId == null) return const Center(child: Text('Not logged in'));
        return HomeDashboardTab(
          userId: _userId!,
          hasDropbox: _hasDropbox,
          hardwareOnline: _appConnected,
          devModeEnabled: _devModeEnabled,
          databaseService: _databaseService,
          onSetupDropbox: () => setState(() => _selectTab(2)),
          onOpenCabinet: () => setState(() => _selectTab(2)),
          onViewOrders: () => setState(() => _selectTab(1)),
          onRefresh: () async {
            await Future.wait([
              _databaseService.refreshTracking(_userId!),
              _checkDropbox(),
            ]);
          },
        );
      case 1:
        if (_userId == null) return const Center(child: Text('Not logged in'));
        return OrdersTab(
          userId: _userId!,
          databaseService: _databaseService,
          ordersMode: _ordersMode,
          inboundFilterIndex: _inboundFilterIndex,
          outboundFilterIndex: _outboundFilterIndex,
          onOrdersModeChanged: (mode) => setState(() => _ordersMode = mode),
          onInboundFilterChanged: (index) => setState(() => _inboundFilterIndex = index),
          onOutboundFilterChanged: (index) => setState(() => _outboundFilterIndex = index),
        );
      case 2:
        return DropboxControlScreen(
          simulationEnabled: _devModeEnabled,
          embeddedInTab: true,
          onHardwareConnectionChanged: _updateDropboxHardwareConnection,
        );
      case 3:
        if (_userId == null) return const Center(child: Text('Not logged in'));
        return ProfileTab(
          userId: _userId!,
          databaseService: _databaseService,
          authService: _authService,
          biometricService: _biometricService,
          devModeEnabled: _devModeEnabled,
          devModeBusy: _devModeBusy,
          supportsDevMode: _supportsDevMode,
          onDevModeChanged: _setDevMode,
        );
      default:
        if (_userId == null) return const Center(child: Text('Not logged in'));
        return HomeDashboardTab(
          userId: _userId!,
          hasDropbox: _hasDropbox,
          hardwareOnline: _appConnected,
          devModeEnabled: _devModeEnabled,
          databaseService: _databaseService,
          onSetupDropbox: () => setState(() => _selectTab(2)),
          onOpenCabinet: () => setState(() => _selectTab(2)),
          onViewOrders: () => setState(() => _selectTab(1)),
          onRefresh: () async {
            await Future.wait([
              _databaseService.refreshTracking(_userId!),
              _checkDropbox(),
            ]);
          },
        );
    }
  }
}
