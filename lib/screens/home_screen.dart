import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
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
  bool _hasDropbox = true;

  // Stream subscriptions for cleanup
  Stream<Map<String, dynamic>?>? _doorStateStream;
  StreamSubscription? _binSub;
  StreamSubscription? _regSub;

  bool _appConnected = false;
  int _currentCapacity = 0;
  String? _userId;
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
      if (_userId != null) {
        _userDataFuture = _databaseService.getUserData(_userId!);
        _setupStreams();
        _checkDropbox();
      }
      setState(() {});
    }
  }

  void _setupStreams() {
    _doorStateStream = WebSocketService().esp32StatusUpdates;
    
    // Listen to device registration to update UI
    _regSub?.cancel();
    _regSub = _databaseService.deviceRegisteredStream.listen((_) => _checkDropbox());

    // Listen to hardware telemetry (Capacity)
    _binSub?.cancel();
    _binSub = WebSocketService().binStatusUpdates.listen((data) {
      if (mounted) {
        final dynamic rawLevel = data['US_DROPOFF'];
        final num fillLevel = (rawLevel is num) ? rawLevel : 30.0;
        setState(() {
          // Calculate percentage: 25cm distance range (empty=30cm, full=5cm)
          double percent = 100.0 - (((fillLevel.toDouble() - 5.0).clamp(0.0, 25.0) / 25.0) * 100.0);
          _currentCapacity = percent.round().clamp(0, 100);
        });
      }
    });

    // Listen to general connection status
    WebSocketService().connectionStatusStream.listen((connected) {
      if (mounted) setState(() => _appConnected = connected);
    });
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
      debugPrint('Error checking dropbox: $e');
    }
  }

  @override
  void dispose() {
    _binSub?.cancel();
    _regSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: [
              _buildHomeTab(),
              _buildOrdersTab(),
              _buildPickUpTab(),
              const DropboxControlScreen(),
              _buildProfileTab(),
            ],
          ),
          _buildFloatingNavBar(isDark),
        ],
      ),
    );
  }

  Widget _buildFloatingNavBar(bool isDark) {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 24,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(UserTheme.radiusXL),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isDark 
                  ? Colors.black.withOpacity(0.6) 
                  : Colors.white.withOpacity(0.75),
              borderRadius: BorderRadius.circular(UserTheme.radiusXL),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNavItem(0, Icons.dashboard_rounded, 'Home'),
                _buildNavItem(1, Icons.shopping_bag_rounded, 'Orders'),
                _buildNavItem(2, Icons.local_shipping_rounded, 'PickUp'),
                _buildNavItem(3, Icons.dns_rounded, 'Dropbox'),
                _buildNavItem(4, Icons.person_rounded, 'Profile'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedIndex = index);
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected 
                  ? UserTheme.primaryOrange.withOpacity(0.15) 
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isSelected 
                  ? UserTheme.primaryOrange 
                  : (isDark ? Colors.white54 : Colors.black38),
              size: 26,
            ),
          ),
          if (isSelected) 
            Container(
              margin: const EdgeInsets.only(top: 2),
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                color: UserTheme.primaryOrange,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    return _buildActiveOrdersTab();
  }

  Widget _buildActiveOrdersTab() {
    if (_userId == null) return const Center(child: Text('Not logged in'));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Greeting Header
          FutureBuilder<Map<String, dynamic>?>(
            future: _userDataFuture,
            builder: (context, snap) {
              final name = (snap.data?['fullName'] as String? ?? '').split(' ').first;
              return Padding(
                padding: const EdgeInsets.only(top: 40, bottom: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isNotEmpty ? 'Hello, $name 👋' : 'Hello there 👋',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Your parcels are being monitored.',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    NotificationBadge(userId: _userId!, databaseService: _databaseService),
                  ],
                ),
              );
            },
          ),

          // Device Hero Card
          _buildDeviceHeroCard(),

          if (!_hasDropbox) _buildNoDropboxBanner(),

          StreamBuilder<List<TrackingModel>>(
            stream: _databaseService.getUserTrackingIds(_userId!),
            initialData: _databaseService.cachedTracking,
            builder: (context, snapshot) {
              final allOrders = snapshot.data ?? [];
              final isDark = Theme.of(context).brightness == Brightness.dark;

              final activeDropOffCount = allOrders.where((o) => 
                o.mode == 'drop_off' && ['pending', 'in_transit'].contains(o.status)).length;
              final dropOffBinCount = allOrders.where((o) => 
                o.mode == 'drop_off' && o.status == 'delivered').length;
              final activePickupCount = allOrders.where((o) => 
                o.mode == 'pickup' && o.status == 'pending').length;
              final pickUpBinCount = allOrders.where((o) => 
                o.mode == 'pickup' && o.status == 'ready_for_pickup').length;

              final dropOffWeekly = _calculateWeeklyData(allOrders, (o) => o.mode == 'drop_off');
              final deliveredWeekly = _calculateWeeklyData(allOrders, (o) => 
                o.mode == 'drop_off' && ['delivered', 'done', 'retrieved'].contains(o.status));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            color: UserTheme.primaryOrange,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'PARCEL ACTIVITY',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.05,
                    children: [
                      _buildMiniStatCard(
                        title: 'Active Orders',
                        value: '$activeDropOffCount',
                        icon: Icons.inventory_2_rounded,
                        color: UserTheme.primaryOrange,
                        weeklyData: dropOffWeekly,
                      ),
                      _buildMiniStatCard(
                        title: 'In Dropbox',
                        value: '$dropOffBinCount',
                        icon: Icons.shopping_basket_rounded,
                        color: UserTheme.statusSuccess,
                        weeklyData: deliveredWeekly,
                      ),
                      _buildMiniStatCard(
                        title: 'Active Pickups',
                        value: '$activePickupCount',
                        icon: Icons.outbox_rounded,
                        color: UserTheme.statusInfo,
                        weeklyData: [5, 8, 12, 7, 4, 9, 6], // Placeholder
                      ),
                      _buildMiniStatCard(
                        title: 'For Return',
                        value: '$pickUpBinCount',
                        icon: Icons.assignment_return_rounded,
                        color: UserTheme.statusWarning,
                        weeklyData: [2, 4, 3, 5, 2, 6, 4], // Placeholder
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          decoration: BoxDecoration(
                            color: UserTheme.statusInfo,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '7-DAY ACTIVITY',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  UserUi.surfaceCard(
                    context,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: WeeklyActivityChart(
                      receivedData: dropOffWeekly,
                      deliveredData: deliveredWeekly,
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  _buildRetailerJungle(allOrders),
                ],
              );
            },
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildDeviceHeroCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _doorStateStream,
      builder: (context, doorSnap) {
        final doorState = doorSnap.data;
        final command = doorState?['command'] as String?;
        final isOpen = command == 'open';
        final Color connColor = _appConnected ? UserTheme.statusSuccess : UserTheme.statusError;
        final Color doorColor = isOpen ? UserTheme.statusWarning : UserTheme.statusSuccess;

        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(UserTheme.radiusXL),
            gradient: isDark
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  )
                : UserTheme.sunsetGradient,
            boxShadow: [
              BoxShadow(
                color: UserTheme.primaryOrange.withOpacity(isDark ? 0.2 : 0.4),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(UserTheme.radiusXL),
            child: Stack(
              children: [
                // Mesh Gradient Simulation
                Positioned(
                  right: -50,
                  top: -50,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.12),
                    ),
                  ),
                ),
                Positioned(
                  left: -20,
                  bottom: -40,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: const Icon(Icons.sensors_rounded, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'SMART DROPBOX',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                Text(
                                  'Device Monitor',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: connColor,
                                    boxShadow: [
                                      BoxShadow(color: connColor.withOpacity(0.6), blurRadius: 6, spreadRadius: 1),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _appConnected ? 'ONLINE' : 'OFFLINE',
                                  style: TextStyle(
                                    color: connColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 28),
                      
                      Row(
                        children: [
                          _buildHeroMetric(
                            title: 'CAPACITY',
                            value: _appConnected ? '$_currentCapacity%' : '--',
                            icon: Icons.layers_rounded,
                            progress: _appConnected ? (_currentCapacity / 100).clamp(0.0, 1.0) : 0.0,
                            progressColor: _currentCapacity > 80 
                                ? UserTheme.statusError 
                                : (_currentCapacity > 50 ? UserTheme.statusWarning : Colors.white),
                          ),
                          const SizedBox(width: 16),
                          _buildHeroMetric(
                            title: 'DOOR',
                            value: _appConnected ? (isOpen ? 'OPEN' : 'LOCKED') : '--',
                            icon: Icons.door_front_door_rounded,
                            isStatus: true,
                            statusColor: isOpen ? UserTheme.statusWarning : UserTheme.statusSuccess,
                            subtitle: 'Tap to manage →',
                            onTap: () => setState(() => _selectedIndex = 3),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeroMetric({
    required String title,
    required String value,
    required IconData icon,
    double? progress,
    Color? progressColor,
    bool isStatus = false,
    Color? statusColor,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(UserTheme.radiusM),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(UserTheme.radiusM),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: Colors.white.withOpacity(0.7), size: 14),
                      const SizedBox(width: 6),
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (isStatus) 
                        Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: statusColor,
                            boxShadow: [
                              BoxShadow(color: statusColor!.withOpacity(0.5), blurRadius: 6, spreadRadius: 1),
                            ],
                          ),
                        ),
                      Text(
                        value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (progress != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Stack(
                        children: [
                          Container(
                            height: 6,
                            color: Colors.white.withOpacity(0.15),
                          ),
                          FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: progressColor,
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: [
                                  BoxShadow(color: progressColor!.withOpacity(0.4), blurRadius: 4),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required List<int> weeklyData,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        borderRadius: BorderRadius.circular(UserTheme.radiusL),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
                child: Icon(icon, color: color, size: 24),
              ),
              MiniSparkline(data: weeklyData, color: color),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
              letterSpacing: -1.5,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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

    return UserUi.surfaceCard(
      context,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: UserTheme.primaryOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.auto_graph_rounded, color: UserTheme.primaryOrange, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ecommerce Platforms Used',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : UserTheme.dayTextPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      'Marketplace activity breakdown',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              UserUi.statusPill(
                label: '${orders.length} Parcels', 
                color: UserTheme.primaryOrange,
              ),
            ],
          ),
          const SizedBox(height: 32),
          ...counts.entries.where((e) => e.value > 0 || e.key == 'Others').map((entry) {
            final percentage = entry.value / total;
            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        entry.key,
                        style: TextStyle(
                          color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextPrimary, 
                          fontWeight: FontWeight.w800, 
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${entry.value}',
                        style: TextStyle(
                          color: UserTheme.primaryOrange, 
                          fontWeight: FontWeight.w900, 
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Stack(
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: percentage > 0 ? percentage : 0.05,
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            gradient: UserTheme.sunsetGradient,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: UserTheme.primaryOrange.withOpacity(0.3), 
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
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
    );
  }

  Widget _buildOrdersTab() {
    return const OrdersTab(); // Assuming this is defined in your codebase correctly
  }

  Widget _buildPickUpTab() {
    return PickupScreen(userId: _userId!, databaseService: _databaseService); // Re-integrating existing pickup screen
  }

  Widget _buildNoDropboxBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: UserUi.surfaceCard(
        context,
        color: UserTheme.primaryOrange.withOpacity(isDark ? 0.1 : 0.05),
        padding: const EdgeInsets.all(20),
        child: Column(
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
    );
  }

  List<int> _calculateWeeklyData(List<TrackingModel> orders, bool Function(TrackingModel) filter) {
    final now = DateTime.now();
    final List<int> dailyCounts = List.filled(7, 0);

    for (int i = 0; i < 7; i++) {
      final date = now.subtract(Duration(days: 6 - i));
      final dateString = date.toIso8601String().split('T')[0];
      
      int countForDay = orders.where((o) {
        if (!filter(o)) return false;
        if (o.registeredAt == null) return false;
        final regDateStr = o.registeredAt!.toIso8601String().split('T')[0];
        return regDateStr == dateString;
      }).length;
      
      dailyCounts[i] = countForDay;
    }
    return dailyCounts;
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
                decoration: BoxDecoration(
                  gradient: UserTheme.sunsetGradient,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(UserTheme.radiusXL)),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.white24,
                      child: Text(
                        (userData?['fullName']?[0]?.toUpperCase() ?? 'U'),
                        style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(userData?['fullName'] ?? 'Smart User', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
                    Text(userData?['email'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.8))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildInfoTile(icon: Icons.phone_android_rounded, title: 'Phone', value: userData?['phoneNumber'] ?? 'Not set'),
                    _buildInfoTile(icon: Icons.map_rounded, title: 'Address', value: userData?['address'] ?? 'Not set'),
                    const SizedBox(height: 32),
                    UserUi.premiumButton(
                      label: 'LOGOUT SESSION',
                      onTap: () => _authService.signOut().then((_) => Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const LoginScreen()))),
                      icon: Icons.power_settings_new_rounded,
                      color: UserTheme.statusError,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoTile({required IconData icon, required String title, required String value}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
        borderRadius: BorderRadius.circular(UserTheme.radiusM),
      ),
      child: Row(
        children: [
          Icon(icon, color: UserTheme.primaryOrange),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 12, color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ],
      ),
    );
  }
}

class OrdersTab extends StatelessWidget {
  const OrdersTab({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Orders Tab Placeholder'));
  }
}
