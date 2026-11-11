import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/dropbox_service.dart';
import '../services/websocket_service.dart';
import '../services/service_locator.dart';
import '../models/tracking_model.dart';
import 'login_screen.dart';
import 'add_tracking_screen.dart';
import 'tracking_details_screen.dart';
import 'admin/admin_dashboard_screen.dart';
import 'admin/rider_management_screen.dart';
import 'dropbox_control_screen.dart';
import '../widgets/notification_badge.dart';
import 'add_pickup_screen.dart';
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
  int _selectedIndex = 0;
  int _ordersMode = 0; // 0: Inbound (Deliveries), 1: Outbound (Pickups)
  int _inboundFilterIndex = 0; // 0: All, 1: In Box, 2: Pending, 3: Retrieved
  int _outboundFilterIndex = 0; // 0: All, 1: Awaiting Pickup, 2: Completed

  bool _hasDropbox = true;

  // Stream subscriptions for cleanup
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Map<String, dynamic>>? _registrationSub;

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
    _connectionSub?.cancel();
    _registrationSub?.cancel();
    super.dispose();
  }

  void _setupStreams() {
    // Initialize streams lazily only when needed
    if (_userId != null) {
      // Establish WebSocket connection
      _databaseService.initSocket(_userId!);

      // ── WebSocket Connectivity & Auto-Refresh ──
      _connectionSub?.cancel();
      _connectionSub = _databaseService.connectionStatusStream.listen((connected) {
        if (mounted) {
          setState(() => _appConnected = connected);
          if (connected) {
            debugPrint('🔄 WebSocket reconnected, auto-refreshing data');
            _databaseService.refreshTracking(_userId!);
            _checkDropbox();
          }
        }
      });

      // ── Real-time Registration Sync ──
      _registrationSub?.cancel();
      // Listen to both registration and unregistration to update _hasDropbox
      _registrationSub = _databaseService.deviceRegisteredStream.listen((_) => _checkDropbox());
      _databaseService.deviceUnregisteredStream.listen((_) => _checkDropbox());
    }
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
    final dot = ok ? UserTheme.statusSuccess : UserTheme.statusError;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(left: 8),
      child: UserUi.glassCard(
        context,
        blur: 8,
        borderRadius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dot,
                boxShadow: [
                  BoxShadow(
                    color: dot.withOpacity(0.4),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              ok ? 'LIVE' : 'OFFLINE',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                color: ok ? dot : (isDark ? Colors.white : UserTheme.primaryOrange),
              ),
            ),
          ],
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
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.black.withOpacity(0.65) : Colors.white.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.08) : UserTheme.primaryOrange.withOpacity(0.15),
                  ),
                ),
                child: SizedBox(
                  height: 64,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(4, (index) {
                      final isSelected = _selectedIndex == index;
                      IconData icon; IconData activeIcon; String label;
                      if (index == 0) { icon = Icons.grid_view_outlined; activeIcon = Icons.grid_view_rounded; label = 'Home'; }
                      else if (index == 1) { icon = Icons.inventory_2_outlined; activeIcon = Icons.inventory_2_rounded; label = 'Orders'; }
                      else if (index == 2) { icon = Icons.dns_outlined; activeIcon = Icons.dns_rounded; label = 'Dropbox'; }
                      else { icon = Icons.person_outline_rounded; activeIcon = Icons.person_rounded; label = 'Profile'; }

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
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isSelected ? UserTheme.primaryOrange.withOpacity(0.15) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    isSelected ? activeIcon : icon,
                                    size: isSelected ? 24 : 22,
                                    color: isSelected ? UserTheme.primaryOrange : theme.hintColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected ? UserTheme.primaryOrange : theme.hintColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.visible,
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
      margin: const EdgeInsets.only(bottom: 24),
      child: UserUi.glassCard(
        context,
        blur: 12,
        borderRadius: UserTheme.radiusL,
        padding: const EdgeInsets.all(20),
        color: isDark ? UserTheme.primaryOrange.withOpacity(0.12) : UserTheme.daySurface.withOpacity(0.8),
        border: Border.all(color: UserTheme.primaryOrange.withOpacity(0.3)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: UserTheme.primaryOrange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: UserTheme.primaryOrange, size: 24),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Set Up Your Dropbox',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Register your Smart Parcel Dropbox to sync deliveries and pickups with your phone.',
              style: TextStyle(
                color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            UserUi.premiumButton(
              label: 'START REGISTRATION',
              onTap: () => setState(() => _selectedIndex = 2),
              icon: Icons.arrow_forward_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveOrdersTab() {
    if (_userId == null) return const Center(child: Text('Not logged in'));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StreamBuilder<List<TrackingModel>>(
            stream: _databaseService.getUserTrackingIds(_userId!),
            initialData: _databaseService.cachedTracking,
            builder: (context, snapshot) {
              final allOrders = snapshot.data ?? [];
              final dropOffBinCount = allOrders.where((o) => 
                o.mode == 'drop_off' && o.status == 'delivered').length;
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

                  const SizedBox(height: 18),

                  // ─── Minimalist Recent Activity Header ───
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Deliveries',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _selectedIndex = 1),
                        child: const Row(
                          children: [
                            Text(
                              'View Orders',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: UserTheme.primaryOrange),
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
                      actionLabel: 'ADD TRACKING',
                      onActionTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AddTrackingScreen()),
                      ),
                    ),
                  ] else ...[
                    ...recentOrders.map((order) {
                      int stageIndex = 0;
                      if (order.status == 'in_transit') stageIndex = 1;
                      else if (order.status == 'delivered') stageIndex = 2;
                      else if (order.status == 'done' || order.status == 'retrieved') stageIndex = 3;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
                          borderRadius: BorderRadius.circular(UserTheme.radiusL),
                          border: Border.all(
                            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
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
                                      CarrierBadge(shopName: order.shopName),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              order.trackingId,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                fontFamily: 'monospace',
                                                color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              order.getStatusText(),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      UserUi.statusPill(
                                        label: order.status.toUpperCase(),
                                        color: order.status == 'delivered'
                                            ? UserTheme.primaryOrange
                                            : (order.status == 'done' || order.status == 'retrieved'
                                                ? UserTheme.statusSuccess
                                                : Colors.indigo),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  DeliveryTimeline(stageIndex: stageIndex),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 140), // Extended padding for floating navbar clearance
        ],
      ),
    );
  }

  Widget _buildOrderCard(TrackingModel order) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _getStatusColor(order.status);
    int stageIndex = 0;
    if (order.status == 'in_transit') stageIndex = 1;
    else if (order.status == 'delivered') stageIndex = 2;
    else if (order.status == 'done' || order.status == 'retrieved') stageIndex = 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: UserUi.surfaceCard(
        context,
        padding: EdgeInsets.zero,
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
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          CarrierBadge(shopName: order.shopName),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              order.shopName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        UserUi.statusPill(
                          label: order.getStatusText().toUpperCase(),
                          color: statusColor,
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded, 
                            color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                            size: 20,
                          ),
                          onPressed: () => _confirmDelete(order),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Delete Tracking',
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : UserTheme.primaryOrange).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.tag_rounded,
                        size: 14,
                        color: isDark ? UserTheme.nightTextMuted : UserTheme.primaryOrange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      order.trackingId,
                      style: TextStyle(
                        color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const Spacer(),
                    if (order.registeredAt != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.access_time_rounded, size: 12,
                              color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
                          const SizedBox(width: 4),
                          Text(
                            _timeAgo(order.registeredAt),
                            style: TextStyle(
                              color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                DeliveryTimeline(stageIndex: stageIndex),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending': return UserTheme.statusWarning;
      case 'in_transit': return Colors.blue;
      case 'delivered': return UserTheme.statusSuccess;
      case 'awaiting_pickup': return Colors.indigo;
      case 'ready_for_pickup': return Colors.deepPurple;
      case 'retrieved': return Colors.grey;
      case 'done': return UserTheme.statusSuccess;
      default: return Colors.grey;
    }
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tracking?'),
        content: Text('Are you sure you want to remove ${tracking.shopName} (${tracking.trackingId}) from your list?\n\nThis action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              
              // 1. OPTIMISTIC UI FEEDBACK
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
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
                  ScaffoldMessenger.of(context).showSnackBar(
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
            child: const Text('DELETE'),
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
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
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

        // ── Sub-Category Filters (Clean Text, No Icons) ──
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                  emptyActionLabel = 'VIEW PENDING';
                  emptyActionOnTap = () => setState(() => _inboundFilterIndex = 2);
                } else if (_inboundFilterIndex == 2) {
                  // Pending
                  filtered = inboundOrders.where((o) => o.status == 'pending' || o.status == 'in_transit').toList();
                  emptyTitle = 'No Pending Parcels';
                  emptySubtitle = 'Parcels you register will appear here until they arrive at your Dropbox.';
                  emptyIcon = Icons.pending_actions_rounded;
                  emptyActionLabel = 'ADD TRACKING';
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
                  emptyActionLabel = 'ADD TRACKING';
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
                  emptyActionLabel = 'SCHEDULE PICKUP';
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
                  emptyActionLabel = 'SCHEDULE PICKUP';
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
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 4, bottom: 120),
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

    return FutureBuilder<Map<String, dynamic>?>(
      future: _userDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: UserTheme.primaryOrange));
        }

        Map<String, dynamic>? userData = snapshot.data;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 120),
          child: Column(
            children: [
              // Profile Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
                decoration: BoxDecoration(
                  gradient: UserTheme.sunsetGradient,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(UserTheme.radiusXL)),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: UserTheme.primaryOrange.withOpacity(0.1),
                        child: Text(
                          (userData?['fullName']?[0]?.toUpperCase() ?? userData?['email']?[0]?.toUpperCase() ?? 'U'),
                          style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: UserTheme.primaryOrange),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      userData?['fullName'] ?? 'Smart User',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      userData?['email'] ?? '',
                      style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Column(
                  children: [
                    UserUi.surfaceCard(
                      context,
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                            child: Row(
                              children: [
                                const Icon(Icons.contact_emergency_rounded, color: UserTheme.primaryOrange, size: 20),
                                const SizedBox(width: 12),
                                Text(
                                  'CONTACT INFORMATION',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildInfoTile(
                            context,
                            userData: userData,
                            icon: Icons.phone_android_rounded,
                            title: 'Phone Number',
                            value: userData?['phoneNumber'] ?? 'Not set',
                            isEmpty: userData?['phoneNumber'] == null || (userData?['phoneNumber'] as String).isEmpty,
                            isEditable: true,
                            fieldKey: 'phoneNumber',
                          ),
                          _buildInfoTile(
                            context,
                            userData: userData,
                            icon: Icons.map_rounded,
                            title: 'Home Address',
                            value: userData?['address'] ?? 'Not set',
                            isEmpty: userData?['address'] == null || (userData?['address'] as String).isEmpty,
                            isEditable: true,
                            fieldKey: 'address',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    UserUi.surfaceCard(
                      context,
                      padding: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                            child: Row(
                              children: [
                                const Icon(Icons.security_rounded, color: UserTheme.primaryOrange, size: 20),
                                const SizedBox(width: 12),
                                Text(
                                  'SECURITY & ACCESS',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildInfoTile(
                            context,
                            icon: Icons.alternate_email_rounded,
                            title: 'Email Identifier',
                            value: userData?['email'] ?? 'Not available',
                            isEmpty: false,
                          ),
                          _buildInfoTile(
                            context,
                            icon: Icons.verified_user_rounded,
                            title: 'Account Status',
                            value: 'Identity Verified',
                            isEmpty: false,
                            showValueIcon: true,
                          ),
                        ],
                      ),
                    ),
                    if (userData?['role'] == 'admin') ...[
                      const SizedBox(height: 24),
                      UserUi.premiumButton(
                        label: 'ADMIN DASHBOARD',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const AdminDashboardScreen())),
                        icon: Icons.admin_panel_settings_rounded,
                      ),
                      const SizedBox(height: 12),
                      UserUi.premiumButton(
                        label: 'MANAGE COURIERS',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const RiderManagementScreen())),
                        icon: Icons.motorcycle_rounded,
                        color: UserTheme.accentAmberDark,
                      ),
                    ],
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.power_settings_new_rounded, color: UserTheme.statusError, size: 20),
                        label: const Text(
                          'LOGOUT SESSION',
                          style: TextStyle(color: UserTheme.statusError, fontWeight: FontWeight.w900, letterSpacing: 1),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          backgroundColor: UserTheme.statusError.withOpacity(0.08),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UserTheme.radiusL)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 100), // Bottom padding for floating nav bar
                  ],
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
    Map<String, dynamic>? userData,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return InkWell(
      onTap: isEditable && fieldKey != null
          ? () => _showEditDialog(context, title, fieldKey, value, isEmpty)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.05) : UserTheme.primaryOrange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: isDark ? UserTheme.nightTextSecondary : UserTheme.primaryOrange),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isEmpty
                                ? (isDark ? UserTheme.nightTextMuted : Colors.grey)
                                : (isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary),
                          ),
                        ),
                      ),
                      if (showValueIcon)
                        const Icon(Icons.verified_rounded, size: 16, color: UserTheme.statusSuccess),
                    ],
                  ),
                ],
              ),
            ),
            if (isEditable)
              Icon(Icons.edit_note_rounded, size: 20, color: isDark ? UserTheme.nightTextMuted : Colors.grey[400]),
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
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newValue = controller.text.trim();
              if (newValue.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$title cannot be empty')),
                  );
                }
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
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
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
                  ScaffoldMessenger.of(context).showSnackBar(
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

  Future<void> _logout({String? message}) async {
    bool? confirm = false;

    if (message != null) {
      confirm = true;
    } else {
      confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Logout'),
            ),
          ],
        ),
      );
    }

    if (confirm == true) {
      await _authService.signOut();
      if (mounted) {
        if (message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.red,
            ),
          );
        }
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }
}
