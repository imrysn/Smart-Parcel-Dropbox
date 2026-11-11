import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/database_service.dart';
import '../services/delivery_push_service.dart';
import '../services/dropbox_service.dart';
import '../services/input_validator.dart';
import '../services/websocket_service.dart';
import '../services/service_locator.dart';
import '../models/tracking_model.dart';
import 'login_screen.dart';
import 'add_tracking_screen.dart';
import 'tracking_details_screen.dart';
import 'dropbox_control_screen.dart';
import '../widgets/notification_badge.dart';
import 'add_pickup_screen.dart';
import 'logs_screen.dart';
import 'access_log_screen.dart';
import '../widgets/user_ui.dart';
import '../config/user_theme.dart';
import '../presentation/components/carrier_badge.dart';
import '../presentation/components/delivery_timeline.dart';
import '../presentation/components/in_box_spotlight.dart';

/// Home Screen - Main dashboard showing active orders
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
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
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;

  // Stream subscriptions for cleanup
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Map<String, dynamic>>? _registrationSub;
  StreamSubscription<Map<String, dynamic>>? _unregistrationSub;
  DeliveryPushService? _deliveryPush;

  bool _appConnected = false;

  // Current user ID
  String? _userId;

  // Cache FutureBuilder future to prevent recreation on every rebuild
  Future<Map<String, dynamic>?>? _userDataFuture;

  @override
  void initState() {
    super.initState();
    _initUser();
  }

  Future<void> _initUser() async {
    _userId = await _authService.currentUserId;
    _appConnected = getIt<WebSocketService>().isConnected;
    _biometricEnabled = await _authService.isBiometricLockEnabled();
    _biometricAvailable = await _biometricService.isBiometricAvailable();
    if (mounted) {
      _setupStreams();
      // Cache user data future once
      if (_userId != null) {
        _userDataFuture = _databaseService.getUserData(_userId!);
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

  /// Refresh user data after profile updates
  void _refreshUserData() {
    if (_userId != null) {
      setState(() {
        _userDataFuture = _databaseService.getUserData(_userId!);
      });
    }
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Smart Parcel Dropbox';
      case 1:
        return 'Orders';
      case 2:
        return 'Dropbox Management';
      case 3:
        return 'Profile';
      default:
        return 'Smart Parcel Dropbox';
    }
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
    
    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        appBar: UserTheme.appBarGradient(
          context: context,
          title: _getAppBarTitle(),
          centerTitle: false,
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
              NotificationBadge(
                userId: _userId!,
                databaseService: _databaseService,
                onSelectTab: (tabIndex, {subTabIndex}) {
                  setState(() {
                    _selectedIndex = tabIndex;
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
            _buildConnectivityIndicator(),
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
                child: Container(
                  height: 62,
                  decoration: BoxDecoration(
                    color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
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

                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedIndex = index;
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
                                  color: isSelected ? UserTheme.primaryOrange : inactiveColor,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? UserTheme.primaryOrange : inactiveColor,
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
        body: _getSelectedTab(),
      ),
    );
  }

  Widget _buildNoDropboxBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: UserUi.surfaceCard(
        context,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.qr_code_scanner_rounded, color: UserTheme.primaryOrange, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Set Up Your Dropbox',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Register your Smart Parcel Dropbox to sync deliveries and pickups with your phone.',
              style: TextStyle(
                color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            UserUi.premiumButton(
              label: 'Register Hardware',
              onTap: () => setState(() => _selectedIndex = 2),
              icon: Icons.arrow_forward_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Material(
        color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        borderRadius: BorderRadius.circular(UserTheme.radiusM),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(UserTheme.radiusM),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(UserTheme.radiusM),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: UserTheme.primaryOrange),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveOrdersTab() {
    if (_userId == null) return const Center(child: Text('Not logged in'));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      color: UserTheme.primaryOrange,
      onRefresh: () async {
        await Future.wait([
          _databaseService.refreshTracking(_userId!),
          _checkDropbox(),
        ]);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: UserUi.listPadding(context, top: 16, bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StreamBuilder<List<TrackingModel>>(
              stream: _databaseService.getUserTrackingIds(_userId!),
              initialData: _databaseService.cachedTracking,
              builder: (context, snapshot) {
                final allOrders = snapshot.data ?? [];
                final dropOffBinCount = allOrders.where((o) =>
                  (o.mode == 'drop_off' || o.mode.isEmpty) && o.status == 'delivered').length;
                final inBoxParcel = allOrders.where((o) => o.status == 'delivered').firstOrNull;
                final recentOrders = allOrders.take(2).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_hasDropbox) _buildNoDropboxBanner(),

                    // ─── Modern In-Box Parcel Spotlight Card ───
                    InBoxSpotlight(
                      inBoxParcel: inBoxParcel,
                      totalInBoxCount: dropOffBinCount,
                      onTapDetails: () {
                        if (inBoxParcel != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => TrackingDetailsScreen(tracking: inBoxParcel),
                            ),
                          );
                        }
                      },
                    ),

                    const SizedBox(height: 14),

                    // ─── Minimalist Quick Actions ───
                    Row(
                      children: [
                        _buildQuickActionButton(
                          icon: Icons.add_box_outlined,
                          label: 'Add Tracking',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AddTrackingScreen()),
                          ).then((_) {
                            if (_userId != null) _databaseService.refreshTracking(_userId!);
                          }),
                        ),
                        const SizedBox(width: 10),
                        _buildQuickActionButton(
                          icon: Icons.local_shipping_outlined,
                          label: 'Schedule Pickup',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AddPickupScreen()),
                          ).then((_) {
                            if (_userId != null) _databaseService.refreshTracking(_userId!);
                          }),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // ─── Minimalist Recent Activity Header ───
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Recent Deliveries',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                            ),
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => setState(() => _selectedIndex = 1),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'View Orders',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: UserTheme.primaryOrange),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_forward_rounded, size: 14, color: UserTheme.primaryOrange),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // ─── Recent 2 Deliveries Stream with Live Delivery Timeline ───
                    if (recentOrders.isEmpty) ...[
                      UserUi.emptyState(
                        context,
                        icon: Icons.inventory_2_outlined,
                        title: 'No Recent Deliveries',
                        subtitle: 'Incoming courier deliveries and staged pickups will appear here.',
                        actionLabel: 'Add Tracking',
                        onActionTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AddTrackingScreen()),
                        ),
                      ),
                    ] else ...[
                      ...recentOrders.map((order) => _buildOrderCard(order, showDelete: false)),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 120), // Clearance for floating navbar
          ],
        ),
      ),
    );
  }

  ({int stageIndex, bool isPickup}) _stageForOrder(TrackingModel order) {
    final isPickup = order.mode == 'pickup' || order.mode == 'pick_up';
    if (isPickup) {
      int stage = 0;
      if (order.status == 'ready_for_pickup') {
        stage = 1;
      } else if (order.status == 'done' || order.status == 'retrieved') {
        stage = 2;
      }
      return (stageIndex: stage, isPickup: true);
    }

    int stage = 0;
    if (order.status == 'in_transit') {
      stage = 1;
    } else if (order.status == 'delivered') {
      stage = 2;
    } else if (order.status == 'done' || order.status == 'retrieved') {
      stage = 3;
    }
    return (stageIndex: stage, isPickup: false);
  }

  Widget _buildOrderCard(TrackingModel order, {bool showDelete = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = UserTheme.getStatusColor(order.status);
    final stage = _stageForOrder(order);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: UserUi.surfaceCard(
        context,
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => TrackingDetailsScreen(tracking: order),
                ),
              );
            },
            borderRadius: BorderRadius.circular(UserTheme.radiusL),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: CarrierBadge(shopName: order.shopName)),
                      const SizedBox(width: 8),
                      UserUi.statusPill(
                        label: order.getStatusText(),
                        color: statusColor,
                      ),
                      if (showDelete) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                            size: 18,
                          ),
                          onPressed: () => _confirmDelete(order),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Delete Tracking',
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          order.trackingId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      if (order.registeredAt != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          _timeAgo(order.registeredAt),
                          style: TextStyle(
                            color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  DeliveryTimeline(
                    stageIndex: stage.stageIndex,
                    isPickup: stage.isPickup,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Returns a human-readable relative time string.
  String _timeAgo(DateTime? date) {
    if (date == null) return 'Unknown';
    final diff = DateTime.now().difference(date).abs();
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }

  void _confirmDelete(TrackingModel tracking) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Tracking?'),
        content: Text('Are you sure you want to remove ${tracking.shopName} (${tracking.trackingId}) from your list?\n\nThis action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();

              // 1. OPTIMISTIC UI FEEDBACK
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Deleted ${tracking.trackingId}'),
                    backgroundColor: UserTheme.statusSuccess,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }

              // 2. ASYNC BACKGROUND NETWORK SYNC
              try {
                await _databaseService.deleteTrackingId(
                  userId: _userId!,
                  trackingId: tracking.trackingId,
                );
              } catch (e) {
                // 3. ROLLBACK ON FAILURE
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Network error. Delete failed: $e'),
                      backgroundColor: UserTheme.statusError,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: UserTheme.statusError,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildAllOrdersTab() {
    if (_userId == null) return const Center(child: Text('Not logged in'));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // ── Primary 2-Mode Segment Control (DELIVERIES vs PICKUPS) ──
        Padding(
          padding: UserUi.listPadding(context, top: 12, bottom: 6),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                _buildPrimaryModeItem(0, 'DELIVERIES'),
                _buildPrimaryModeItem(1, 'PICKUPS'),
              ],
            ),
          ),
        ),

        // ── Sub-Category Filters (Clean Text, No Icons) ──
        UserUi.responsiveContainer(
          context,
          maxWidth: 600,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: UserUi.horizontalGutter(context), vertical: 6),
            child: Row(
              children: _ordersMode == 0
                  ? [
                      _buildFilterChip('All', 0, _inboundFilterIndex, (i) => setState(() => _inboundFilterIndex = i)),
                      const SizedBox(width: 8),
                      _buildFilterChip('In Box', 1, _inboundFilterIndex, (i) => setState(() => _inboundFilterIndex = i)),
                      const SizedBox(width: 8),
                      _buildFilterChip('Pending', 2, _inboundFilterIndex, (i) => setState(() => _inboundFilterIndex = i)),
                      const SizedBox(width: 8),
                      _buildFilterChip('Retrieved', 3, _inboundFilterIndex, (i) => setState(() => _inboundFilterIndex = i)),
                    ]
                  : [
                      _buildFilterChip('All', 0, _outboundFilterIndex, (i) => setState(() => _outboundFilterIndex = i)),
                      const SizedBox(width: 8),
                      _buildFilterChip('Awaiting Pickup', 1, _outboundFilterIndex, (i) => setState(() => _outboundFilterIndex = i)),
                      const SizedBox(width: 8),
                      _buildFilterChip('Completed', 2, _outboundFilterIndex, (i) => setState(() => _outboundFilterIndex = i)),
                    ],
            ),
          ),
        ),

        const SizedBox(height: 4),

        // ── Dynamic List Stream ──
        Expanded(
          child: StreamBuilder<List<TrackingModel>>(
            stream: _databaseService.getUserTrackingIds(_userId!),
            initialData: _databaseService.cachedTracking,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return UserUi.emptyState(
                  context,
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load orders',
                  subtitle: 'Check your connection and pull down to refresh.',
                );
              }

              // Show shimmering skeletons while waiting for first data
              if (snapshot.connectionState == ConnectionState.waiting && (snapshot.data ?? []).isEmpty) {
                return UserUi.shimmerList(context, count: 5);
              }

              final allOrders = snapshot.data ?? [];
              List<TrackingModel> filtered;
              String emptyTitle;
              String emptySubtitle;
              IconData emptyIcon;
              String? emptyActionLabel;
              VoidCallback? emptyActionOnTap;

              if (_ordersMode == 0) {
                // ─── INBOUND DELIVERIES ───
                final inboundOrders = allOrders.where((o) => o.mode == 'drop_off' || o.mode.isEmpty).toList();

                if (_inboundFilterIndex == 1) {
                  // In Box
                  filtered = inboundOrders.where((o) => o.status == 'delivered').toList();
                  emptyTitle = 'No Parcels in Box';
                  emptySubtitle = 'When a courier delivers a parcel, it will be securely locked inside.';
                  emptyIcon = Icons.inbox_rounded;
                  emptyActionLabel = 'View Pending';
                  emptyActionOnTap = () => setState(() => _inboundFilterIndex = 2);
                } else if (_inboundFilterIndex == 2) {
                  // Pending
                  filtered = inboundOrders.where((o) => o.status == 'pending' || o.status == 'in_transit').toList();
                  emptyTitle = 'No Pending Parcels';
                  emptySubtitle = 'Parcels you register will appear here until they arrive at your Dropbox.';
                  emptyIcon = Icons.pending_actions_rounded;
                  emptyActionLabel = 'Add Tracking';
                  emptyActionOnTap = () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddTrackingScreen()),
                  );
                } else if (_inboundFilterIndex == 3) {
                  // Retrieved
                  filtered = inboundOrders.where((o) => o.status == 'retrieved' || o.status == 'done').toList();
                  emptyTitle = 'No Retrieval History';
                  emptySubtitle = 'Completed deliveries and collected parcels will be archived here.';
                  emptyIcon = Icons.history_rounded;
                } else {
                  // All Deliveries
                  filtered = inboundOrders;
                  emptyTitle = 'No Deliveries Found';
                  emptySubtitle = 'Register incoming tracking IDs to track your parcel deliveries.';
                  emptyIcon = Icons.inventory_2_outlined;
                  emptyActionLabel = 'Add Tracking';
                  emptyActionOnTap = () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddTrackingScreen()),
                  );
                }
              } else {
                // ─── PICKUPS ───
                final outboundOrders = allOrders.where((o) => o.mode == 'pickup' || o.mode == 'pick_up').toList();

                if (_outboundFilterIndex == 1) {
                  // Awaiting Pickup
                  filtered = outboundOrders.where((o) =>
                    o.status == 'awaiting_pickup' || o.status == 'pending' || o.status == 'ready_for_pickup').toList();
                  emptyTitle = 'No Awaiting Pickups';
                  emptySubtitle = 'Parcels waiting in your Dropbox for courier collection will appear here.';
                  emptyIcon = Icons.schedule_rounded;
                  emptyActionLabel = 'Schedule Pickup';
                  emptyActionOnTap = () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddPickupScreen()),
                  ).then((_) => _databaseService.refreshTracking(_userId!));
                } else if (_outboundFilterIndex == 2) {
                  // Completed
                  filtered = outboundOrders.where((o) => o.status == 'retrieved' || o.status == 'done').toList();
                  emptyTitle = 'No Completed Pickups';
                  emptySubtitle = 'Parcels collected by riders from your Dropbox will be archived here.';
                  emptyIcon = Icons.history_rounded;
                } else {
                  // All Pickups
                  filtered = outboundOrders;
                  emptyTitle = 'No Pickups Scheduled';
                  emptySubtitle = 'Schedule couriers to pick up returns or outbound parcels from your Dropbox.';
                  emptyIcon = Icons.outbox_rounded;
                  emptyActionLabel = 'Schedule Pickup';
                  emptyActionOnTap = () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddPickupScreen()),
                  ).then((_) => _databaseService.refreshTracking(_userId!));
                }
              }

              // Smart Sorting: Newest & Most urgent first
              filtered.sort((a, b) {
                int getScore(String status) {
                  if (status == 'pending' || status == 'in_transit' || status == 'awaiting_pickup') return 0;
                  if (status == 'ready_for_pickup' || status == 'delivered') return 1;
                  return 2; // delivered, retrieved, done
                }

                int scoreA = getScore(a.status);
                int scoreB = getScore(b.status);
                if (scoreA != scoreB) return scoreA.compareTo(scoreB);

                final timeA = a.registeredAt ?? DateTime(2000);
                final timeB = b.registeredAt ?? DateTime(2000);
                return timeB.compareTo(timeA);
              });

              if (filtered.isEmpty) {
                return RefreshIndicator(
                  onRefresh: () => _databaseService.refreshTracking(_userId!),
                  color: UserTheme.primaryOrange,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 40, bottom: 120),
                    child: UserUi.emptyState(
                      context,
                      icon: emptyIcon,
                      title: emptyTitle,
                      subtitle: emptySubtitle,
                      actionLabel: emptyActionLabel,
                      onActionTap: emptyActionOnTap,
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () => _databaseService.refreshTracking(_userId!),
                color: UserTheme.primaryOrange,
                child: ListView.builder(
                  padding: UserUi.listPadding(context, top: 4, bottom: 120),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final order = filtered[index];
                    return _buildOrderCard(order);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryModeItem(int index, String label) {
    final isSelected = _ordersMode == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _ordersMode = index;
            _databaseService.refreshTracking(_userId!);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? UserTheme.primaryOrange : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: UserTheme.primaryOrange.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 0.6,
                color: isSelected
                    ? Colors.white
                    : (isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    int index,
    int selectedIndex,
    ValueChanged<int> onSelect, {
    IconData? icon,
  }) {
    final isSelected = selectedIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => onSelect(index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white : UserTheme.dayTextPrimary)
              : (isDark ? UserTheme.nightCard : UserTheme.dayCard),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? (isDark ? Colors.white : UserTheme.dayTextPrimary)
                : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06)),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: isSelected
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _getSelectedTab() {
    switch (_selectedIndex) {
      case 0:
        return _buildActiveOrdersTab();
      case 1:
        return _buildAllOrdersTab();
      case 2:
        return const DropboxControlScreen();
      case 3:
        return _buildProfileTab();
      default:
        return _buildActiveOrdersTab();
    }
  }

  Widget _buildProfileTab() {
    if (_userId == null) return const Center(child: Text('Not logged in'));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary;
    final secondaryText = isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return FutureBuilder<Map<String, dynamic>?>(
      future: _userDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: UserTheme.primaryOrange));
        }

        Map<String, dynamic>? userData = snapshot.data;
        final fullName = (userData?['fullName'] as String?)?.trim();
        final email = (userData?['email'] as String?)?.trim() ?? '';
        final initial = (fullName != null && fullName.isNotEmpty)
            ? fullName[0].toUpperCase()
            : (email.isNotEmpty ? email[0].toUpperCase() : 'U');

        return SingleChildScrollView(
          padding: UserUi.listPadding(context, top: 20, bottom: 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Minimalist Profile Identity Header
              UserUi.surfaceCard(
                context,
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: UserTheme.primaryOrange.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: UserTheme.primaryOrange.withValues(alpha: 0.35),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: UserTheme.primaryOrange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (fullName != null && fullName.isNotEmpty) ? fullName : 'Smart User',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: primaryText,
                              letterSpacing: -0.4,
                            ),
                          ),
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              email,
                              style: TextStyle(
                                fontSize: 13,
                                color: secondaryText,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'Contact information',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: secondaryText,
                  ),
                ),
              ),
              UserUi.surfaceCard(
                context,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _buildInfoTile(
                      context,
                      icon: Icons.phone_android_rounded,
                      title: 'Phone number',
                      value: userData?['phoneNumber'] ?? 'Not set',
                      isEmpty: userData?['phoneNumber'] == null || (userData?['phoneNumber'] as String).isEmpty,
                      isEditable: true,
                      fieldKey: 'phoneNumber',
                    ),
                    Divider(height: 1, indent: 52, color: dividerColor),
                    _buildInfoTile(
                      context,
                      icon: Icons.location_on_outlined,
                      title: 'Home address',
                      value: userData?['address'] ?? 'Not set',
                      isEmpty: userData?['address'] == null || (userData?['address'] as String).isEmpty,
                      isEditable: true,
                      fieldKey: 'address',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'Activity & security',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: secondaryText,
                  ),
                ),
              ),
              UserUi.surfaceCard(
                context,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _buildInfoTile(
                      context,
                      icon: Icons.alternate_email_rounded,
                      title: 'Email identifier',
                      value: email.isNotEmpty ? email : 'Not available',
                      isEmpty: email.isEmpty,
                    ),
                    Divider(height: 1, indent: 52, color: dividerColor),
                    _buildInfoTile(
                      context,
                      icon: Icons.verified_user_outlined,
                      title: 'Account status',
                      value: 'Identity verified',
                      isEmpty: false,
                      showValueIcon: true,
                    ),
                    Divider(height: 1, indent: 52, color: dividerColor),
                    _buildInfoTile(
                      context,
                      icon: Icons.qr_code_2_rounded,
                      title: 'Parcel scan logs',
                      value: 'Courier drop-off & pickup history',
                      isEmpty: false,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LogsScreen()),
                      ),
                    ),
                    Divider(height: 1, indent: 52, color: dividerColor),
                    _buildInfoTile(
                      context,
                      icon: Icons.history_rounded,
                      title: 'Owner access history',
                      value: 'Door unlocks & QR owner verifications',
                      isEmpty: false,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AccessLogScreen()),
                      ),
                    ),
                    Divider(height: 1, indent: 52, color: dividerColor),
                    _buildInfoTile(
                      context,
                      icon: Icons.lock_reset_rounded,
                      title: 'Password',
                      value: 'Update account password',
                      isEmpty: false,
                      onTap: _showChangePasswordDialog,
                    ),
                    Divider(height: 1, indent: 52, color: dividerColor),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.fingerprint_rounded,
                            size: 20,
                            color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Biometric app lock',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: primaryText,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _biometricAvailable
                                      ? 'Require Face ID or fingerprint on launch'
                                      : 'Available on supported Android & iOS devices',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch.adaptive(
                            value: _biometricEnabled && _biometricAvailable,
                            activeTrackColor: UserTheme.primaryOrange,
                            onChanged: _biometricAvailable ? _toggleBiometricLock : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded, color: UserTheme.statusError, size: 18),
                  label: const Text(
                    'Log out',
                    style: TextStyle(
                      color: UserTheme.statusError,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: UserTheme.statusError.withValues(alpha: 0.06),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(UserTheme.radiusM),
                      side: BorderSide(color: UserTheme.statusError.withValues(alpha: 0.2)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: _confirmDeleteAccount,
                  child: Text(
                    'Delete account',
                    style: TextStyle(
                      color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required bool isEmpty,
    bool showValueIcon = false,
    bool isEditable = false,
    String? fieldKey,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor = isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary;
    final mutedColor = isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted;

    final VoidCallback? effectiveTap = onTap ??
        (isEditable && fieldKey != null
            ? () => _showEditDialog(context, title, fieldKey, value, isEmpty)
            : null);

    return InkWell(
      onTap: effectiveTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: secondaryColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: mutedColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isEmpty
                                ? mutedColor
                                : (isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary),
                          ),
                        ),
                      ),
                      if (showValueIcon) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.verified_rounded, size: 15, color: UserTheme.statusSuccess),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (isEditable)
              Icon(Icons.edit_outlined, size: 18, color: mutedColor)
            else if (onTap != null)
              Icon(Icons.chevron_right_rounded, size: 20, color: mutedColor),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    String title,
    String fieldKey,
    String currentValue,
    bool isEmpty,
  ) {
    final TextEditingController controller = TextEditingController(
      text: isEmpty ? '' : currentValue,
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit $title'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: title,
            hintText: 'Enter $title',
          ),
          keyboardType: fieldKey == 'phoneNumber'
              ? TextInputType.phone
              : TextInputType.streetAddress,
          maxLines: fieldKey == 'address' ? 3 : 1,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newValue = controller.text.trim();
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(dialogContext);
              if (newValue.isEmpty) {
                messenger.showSnackBar(
                  SnackBar(content: Text('$title cannot be empty')),
                );
                return;
              }

              try {
                // Update in database
                await _databaseService.updateUserProfile(
                  userId: _userId!,
                  phoneNumber: fieldKey == 'phoneNumber' ? newValue : null,
                  address: fieldKey == 'address' ? newValue : null,
                );

                if (mounted) {
                  navigator.pop();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('$title updated successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  // Refresh the profile data to show updated values
                  _refreshUserData();
                }
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBiometricLock(bool enable) async {
    final messenger = ScaffoldMessenger.of(context);
    if (enable) {
      final ok = await _biometricService.authenticate(
        reason: 'Verify biometrics to enable app lock',
      );
      if (!ok) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Biometric verification was not completed.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }
    await _authService.setBiometricLockEnabled(enable);
    if (mounted) {
      setState(() => _biometricEnabled = enable);
      messenger.showSnackBar(
        SnackBar(
          content: Text(enable ? 'Biometric app lock enabled' : 'Biometric app lock disabled'),
          backgroundColor: UserTheme.statusSuccess,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showChangePasswordDialog() {
    final formKey = GlobalKey<FormState>();
    final currentController = TextEditingController();
    final nextController = TextEditingController();
    final confirmController = TextEditingController();
    bool submitting = false;
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Password'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: currentController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Current password'),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nextController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'New password'),
                    validator: InputValidator.validatePassword,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Confirm new password'),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v != nextController.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => submitting = true);
                      final navigator = Navigator.of(dialogContext);
                      try {
                        await _databaseService.changePassword(
                          currentPassword: currentController.text,
                          newPassword: nextController.text,
                        );
                        if (dialogContext.mounted) navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Password updated successfully'),
                            backgroundColor: UserTheme.statusSuccess,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(e.toString()),
                            backgroundColor: UserTheme.statusError,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
              child: Text(submitting ? 'Saving...' : 'Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteAccount() {
    if (_userId == null) return;
    final confirmController = TextEditingController();
    bool deleting = false;
    final messenger = ScaffoldMessenger.of(context);
    final rootNavigator = Navigator.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Delete Account?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This permanently deletes your profile, parcels, and unlinks your Dropbox access. Type DELETE below to confirm.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(hintText: 'Type DELETE'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: deleting ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: deleting || confirmController.text.trim() != 'DELETE'
                  ? null
                  : () async {
                      setDialogState(() => deleting = true);
                      final dialogNav = Navigator.of(dialogContext);
                      try {
                        await _databaseService.deleteUser(_userId!);
                        if (dialogContext.mounted) dialogNav.pop();
                        if (mounted) {
                          rootNavigator.pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                            (route) => false,
                          );
                        }
                      } catch (e) {
                        setDialogState(() => deleting = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(e.toString()),
                            backgroundColor: UserTheme.statusError,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: UserTheme.statusError,
                foregroundColor: Colors.white,
              ),
              child: Text(deleting ? 'Deleting...' : 'Delete'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout({String? message}) async {
    bool? confirm = false;

    if (message != null) {
      confirm = true;
    } else {
      confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Logout'),
            ),
          ],
        ),
      );
    }

    if (confirm == true) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      await _authService.signOut();
      if (mounted) {
        if (message != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.red,
            ),
          );
        }
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }
}
