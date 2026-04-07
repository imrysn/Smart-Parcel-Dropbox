import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../widgets/fade_animation.dart';
import '../services/dropbox_service.dart';
import '../services/websocket_service.dart';
import '../services/service_locator.dart';
import '../services/error_handler.dart';
import '../models/tracking_model.dart';
import 'login_screen.dart';
import 'add_tracking_screen.dart';
import 'tracking_details_screen.dart';
import 'logs_screen.dart';
import 'notifications_screen.dart';
import 'admin/admin_dashboard_screen.dart';
import 'admin/rider_management_screen.dart';
import 'dropbox_control_screen.dart';

import 'pickup_screen.dart';
import 'owner_verify_screen.dart';
import 'access_qr_screen.dart';
import 'access_log_screen.dart';
import '../widgets/notification_badge.dart';
import '../widgets/weekly_activity_chart.dart';
import '../widgets/mini_sparkline.dart';
import '../widgets/user_ui.dart';
import '../config/user_theme.dart';

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
  int _ordersTabIndex = 0; // 0: Delivered, 1: Pick Up, 2: Retrieved

  bool _hasDropbox = true;

  // Stream subscriptions for cleanup
  Stream<List<TrackingModel>>? _activeOrdersStream;
  Stream<List<TrackingModel>>? _activePickupsStream;
  Stream<int>? _notificationsCountStream;
  Stream<Map<String, dynamic>?>? _doorStateStream;
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
    // Clean up streams to prevent memory leaks
    _activeOrdersStream = null;
    _activePickupsStream = null;
    _notificationsCountStream = null;
    _connectionSub?.cancel();
    _registrationSub?.cancel();
    super.dispose();
  }

  void _setupStreams() {
    // Initialize streams lazily only when needed
    if (_userId != null) {
      // Establish WebSocket connection
      _databaseService.initSocket(_userId!);

      _activeOrdersStream = _databaseService.getActiveOrders(_userId!);
      _activePickupsStream = _databaseService.getActivePickups(_userId!);
      _notificationsCountStream =
          _databaseService.getUnreadNotificationsCount(_userId!);
      _doorStateStream = _databaseService.getDropBoxDoorState();

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
        return 'Pick Up';
      case 3:
        return 'Dropbox Management';
      case 4:
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
            if (_userId != null)
              NotificationBadge(
                userId: _userId!,
                databaseService: _databaseService,
              ),
            _buildConnectivityIndicator(),
            const SizedBox(width: 12),
          ],
        ),
        floatingActionButton: _getFloatingActionButton(),
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
                    children: List.generate(5, (index) {
                      final isSelected = _selectedIndex == index;
                      IconData icon; IconData activeIcon; String label;
                      if (index == 0) { icon = Icons.grid_view_outlined; activeIcon = Icons.grid_view_rounded; label = 'Home'; }
                      else if (index == 1) { icon = Icons.inventory_2_outlined; activeIcon = Icons.inventory_2_rounded; label = 'Orders'; }
                      else if (index == 2) { icon = Icons.outbox_outlined; activeIcon = Icons.outbox_rounded; label = 'Pickup'; }
                      else if (index == 3) { icon = Icons.dns_outlined; activeIcon = Icons.dns_rounded; label = 'Dropbox'; }
                      else { icon = Icons.person_outline_rounded; activeIcon = Icons.person_rounded; label = 'Profile'; }

                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedIndex = index;
                              if (index <= 2 && _userId != null) {
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

  Widget? _getFloatingActionButton() {
    if (_selectedIndex == 1) {
      return FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const AddTrackingScreen(),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Tracking ID'),
        heroTag: 'home_fab',
      );
    }
    return null;
  }


  List<int> _calculateWeeklyData(List<TrackingModel> orders, bool Function(TrackingModel) filter) {
    final now = DateTime.now();
    final List<int> dailyCounts = List.filled(7, 0);

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dateString = date.toIso8601String().split('T')[0];
      
      int countForDay = orders.where((o) {
        if (!filter(o)) return false;
        if (o.registeredAt == null) return false;
        final regDateStr = o.registeredAt!.toIso8601String().split('T')[0];
        return regDateStr == dateString;
      }).length;
      
      dailyCounts[6 - i] = countForDay;
    }
    return dailyCounts;
  }

  Widget _buildNoDropboxBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FadeAnimation(0.2, Container(
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
              onTap: () => setState(() => _selectedIndex = 3),
              icon: Icons.arrow_forward_rounded,
            ),
          ],
        ),
      ),
    ));
  }

  Widget _buildMiniStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required List<int> weeklyData,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return UserUi.surfaceCard(
      context,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              MiniSparkline(data: weeklyData, color: color),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
              letterSpacing: -1,
            ),
          ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetailerJungle(List<TrackingModel> orders) {
    final Map<String, int> counts = {
      'Shopee': 0, 'Lazada': 0, 'TikTok': 0, 'Amazon': 0, 'Others': 0,
    };

    for (var order in orders) {
      final name = order.shopName.toLowerCase();
      if (name.contains('shopee')) counts['Shopee'] = counts['Shopee']! + 1;
      else if (name.contains('lazada')) counts['Lazada'] = counts['Lazada']! + 1;
      else if (name.contains('tiktok')) counts['TikTok'] = counts['TikTok']! + 1;
      else if (name.contains('amazon')) counts['Amazon'] = counts['Amazon']! + 1;
      else counts['Others'] = counts['Others']! + 1;
    }

    final total = orders.isEmpty ? 1 : orders.length;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      child: UserUi.glassCard(
        context,
        blur: 16,
        padding: const EdgeInsets.all(22),
        color: UserTheme.sunsetStart.withOpacity(0.95),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.auto_graph_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Ecommerce Platforms Used',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                UserUi.statusPill(label: '${orders.length} Parcels', color: Colors.white),
              ],
            ),
            const SizedBox(height: 24),
            ...counts.entries.where((e) => e.value > 0 || e.key == 'Others').map((entry) {
              final percentage = entry.value / total;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          entry.key,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        Text(
                          '${entry.value}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Stack(
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: percentage > 0 ? percentage : 0.05,
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [UserTheme.accentAmberLight, Colors.white]),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveOrdersTab() {
    if (_userId == null) return const Center(child: Text('Not logged in'));

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
              
              // Calculate specific state metrics
              final activeDropOffCount = allOrders.where((o) => 
                o.mode == 'drop_off' && ['pending', 'in_transit'].contains(o.status)).length;
              final dropOffBinCount = allOrders.where((o) => 
                o.mode == 'drop_off' && o.status == 'delivered').length;
                
              final activePickupCount = allOrders.where((o) => 
                o.mode == 'pickup' && o.status == 'pending').length;
              final pickUpBinCount = allOrders.where((o) => 
                o.mode == 'pickup' && o.status == 'ready_for_pickup').length;

              final dropOffWeekly = _calculateWeeklyData(allOrders, (o) => o.mode == 'drop_off');
              final pickUpWeekly = _calculateWeeklyData(allOrders, (o) => o.mode == 'pickup');
              final deliveredWeekly = _calculateWeeklyData(allOrders, (o) => o.mode == 'drop_off' && ['delivered', 'done'].contains(o.status));
              final readyPickupWeekly = _calculateWeeklyData(allOrders, (o) => o.mode == 'pickup' && o.status == 'ready_for_pickup');

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_hasDropbox) _buildNoDropboxBanner(),
                  UserUi.sectionTitle(
                    context,
                    'Dashboard overview',
                    subtitle: 'Live counts from your parcel activity',
                  ),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.08,
                    children: [
                      FadeAnimation(0.3, _buildMiniStatCard(
                        title: 'Active Orders',
                        value: '$activeDropOffCount',
                        icon: Icons.local_shipping_rounded,
                        color: UserTheme.primaryOrange,
                        weeklyData: dropOffWeekly,
                      )),
                      FadeAnimation(0.4, _buildMiniStatCard(
                        title: 'Drop-Off Bin',
                        value: '$dropOffBinCount',
                        icon: Icons.inbox_rounded,
                        color: UserTheme.accentAmberDark,
                        weeklyData: deliveredWeekly,
                      )),
                      FadeAnimation(0.5, _buildMiniStatCard(
                        title: 'Active Pickups',
                        value: '$activePickupCount',
                        icon: Icons.outbox_rounded,
                        color: UserTheme.gradientPink,
                        weeklyData: pickUpWeekly,
                      )),
                      FadeAnimation(0.6, _buildMiniStatCard(
                        title: 'Pick-Up Bin',
                        value: '$pickUpBinCount',
                        icon: Icons.inventory_2_rounded,
                        color: UserTheme.primaryOrangeDark,
                        weeklyData: readyPickupWeekly,
                      )),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  // Phase 5: Secure Access QR Action
                  UserUi.premiumButton(
                    label: 'GENERATE ACCESS QR',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => const AccessQrScreen()),
                    ),
                    icon: Icons.qr_code_rounded,
                  ),
                  
                  const SizedBox(height: 12),
                  WeeklyActivityChart(
                    receivedData: dropOffWeekly,
                    deliveredData: deliveredWeekly,
                  ),
                  
                  const SizedBox(height: 12),
                  _buildRetailerJungle(allOrders),
                ],
              );
            },
          ),
          const SizedBox(height: 100), // Bottom padding for floating nav bar
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropboxStatusCard() {
    if (_userId == null) return const SizedBox.shrink();

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _doorStateStream,
      builder: (context, snapshot) {
        final doorState = snapshot.data;
        final command = doorState?['command'] as String?;
        final isOpen = command == 'open';
        final isProcessing = doorState?['status'] == 'processing';

        return Card(
          margin: const EdgeInsets.all(16),
          elevation: 4,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: isOpen
                    ? [Colors.green.shade50, Colors.white]
                    : [
                        Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withOpacity(0.1),
                        Colors.white
                      ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isOpen
                          ? Colors.green.shade100
                          : Colors.orange.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isOpen ? Icons.lock_open : Icons.lock,
                      color: isOpen
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Drop Box Status',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isProcessing
                              ? 'Processing...'
                              : (isOpen
                                  ? 'Unlocked & Open'
                                  : 'Locked & Secure'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const DropboxControlScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Manage'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrderCard(TrackingModel order) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _getStatusColor(order.status);

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
                      child: Text(
                        order.shopName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
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
                        color: (isDark ? Colors.white : UserTheme.primaryOrange).withOpacity(0.08),
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
                  ],
                ),
                if (order.registeredAt != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.access_time_rounded, size: 14,
                            color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _timeAgo(order.registeredAt),
                        style: TextStyle(
                          color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
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
              try {
                // Show loading indicator
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deleting ${tracking.trackingId}...'),
                    duration: const Duration(seconds: 1),
                  ),
                );
                
                await _databaseService.deleteTrackingId(
                  userId: _userId!,
                  trackingId: tracking.trackingId,
                );
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tracking deleted successfully'),
                      backgroundColor: UserTheme.statusSuccess,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
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
        // ── Status Segment Control (Master Categories) ──
        Container(
          margin: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _buildSegmentItem(0, 'PENDING', Icons.pending_actions_rounded),
              _buildSegmentItem(1, 'DELIVERED', Icons.local_shipping_rounded),
              _buildSegmentItem(2, 'RETRIEVED', Icons.history_rounded),
            ],
          ),
        ),

        // ── Filtered List Based on Status ──
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

              List<TrackingModel> allOrders = snapshot.data ?? [];
              List<TrackingModel> filtered;

              // Apply Refined User-Requested Status Logic
              if (_ordersTabIndex == 0) {
                // 1. PENDING - Just added, waiting for activity
                filtered = allOrders.where((o) => o.status == 'pending' || o.status == 'in_transit').toList();
              } else if (_ordersTabIndex == 1) {
                // 2. DELIVERED - Courier dropped off, physically in the box
                filtered = allOrders.where((o) => o.mode == 'drop_off' && o.status == 'delivered').toList();
              } else {
                // 3. RETRIEVED - Final History (Collected by owner or rider)
                filtered = allOrders.where((o) => o.status == 'retrieved' || o.status == 'done').toList();
              }

              if (filtered.isEmpty) {
                String title; String subtitle; IconData icon;
                if (_ordersTabIndex == 0) {
                  title = 'No Pending Parcels';
                  subtitle = 'Orders you add manually will appear here until they arrive.';
                  icon = Icons.pending_actions_rounded;
                } else if (_ordersTabIndex == 1) {
                  title = 'No Parcels in Box';
                  subtitle = 'When a courier drops off a parcel, it will move here.';
                  icon = Icons.local_shipping_rounded;
                } else {
                  title = 'No Retrieval History';
                  subtitle = 'Completed orders and retrieved parcels move here.';
                  icon = Icons.history_rounded;
                }

                return UserUi.emptyState(
                  context,
                  icon: icon,
                  title: title,
                  subtitle: subtitle,
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

  Widget _buildSegmentItem(int index, String label, IconData icon) {
    final isSelected = _ordersTabIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _ordersTabIndex = index;
            _databaseService.refreshTracking(_userId!);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? UserTheme.primaryOrange : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected 
              ? [BoxShadow(color: UserTheme.primaryOrange.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 3))]
              : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon, 
                size: 14, 
                color: isSelected ? Colors.white : (isDark ? Colors.white60 : Colors.black45)
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: isSelected ? Colors.white : (isDark ? Colors.white60 : Colors.black45),
                ),
                maxLines: 1,
              ),
            ],
          ),
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
        return PickupScreen(
          userId: _userId!,
          databaseService: _databaseService,
        );
      case 3:
        return const DropboxControlScreen();
      case 4:
        return _buildProfileTab();
      default:
        return _buildActiveOrdersTab();
    }
  }

  Widget _buildPickupTab() {
    if (_userId == null) return const Center(child: Text('Not logged in'));

    return StreamBuilder<List<TrackingModel>>(
      stream: _activePickupsStream,
      initialData: _databaseService.cachedTracking
          .where((t) =>
              t.mode == 'pickup' &&
              ['pending', 'ready_for_pickup'].contains(t.status))
          .toList(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Error loading pickups'));
        }

        var pickups = snapshot.data ?? [];

        // Mock data for UI demonstration if list is empty
        if (pickups.isEmpty) {
          pickups = [
            TrackingModel(
              trackingId: 'PICKUP-12345',
              userId: _userId!,
              shopName: 'Return Parcel (Shopee)',
              status: 'ready_for_pickup',
              mode: 'pickup',
              registeredAt: DateTime.now().subtract(const Duration(hours: 2)),
            ),
            TrackingModel(
              trackingId: 'PICKUP-67890',
              userId: _userId!,
              shopName: 'Document to Office',
              status: 'pending',
              mode: 'pickup',
              registeredAt: DateTime.now().subtract(const Duration(days: 1)),
            ),
          ];
        }

        if (pickups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.outbox_outlined, size: 80, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('No pickups registered',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                const SizedBox(height: 8),
                Text('Add an item for riders to collect',
                    style: TextStyle(color: Colors.grey[500])),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: pickups.length,
          itemBuilder: (context, index) {
            final pickup = pickups[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: _buildOrderCard(pickup),
            );
          },
        );
      },
    );
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
