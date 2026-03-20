import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
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

/// Home Screen - Main dashboard showing active orders
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _databaseService = DatabaseService();
  int _selectedIndex = 0;

  // Stream subscriptions for cleanup
  Stream<List<TrackingModel>>? _activeOrdersStream;
  Stream<List<TrackingModel>>? _activePickupsStream;
  Stream<int>? _notificationsCountStream;
  Stream<Map<String, dynamic>?>? _doorStateStream;

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
    if (mounted) {
      _setupStreams();
      // Cache user data future once
      if (_userId != null) {
        _userDataFuture = _databaseService.getUserData(_userId!);
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    // Clean up streams to prevent memory leaks
    _activeOrdersStream = null;
    _activePickupsStream = null;
    _notificationsCountStream = null;
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

      // Note: Account deletion check was removed as it relied on Firestore.
      // In the MongoDB branch, account status is handled via the Node.js API and WebSockets.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      extendBody: true,
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        centerTitle: false, // Ensures the title is aligned to the left
        actions: [
          // Notifications button with badge - isolated widget prevents AppBar rebuilds
          if (_userId != null)
            NotificationBadge(
              userId: _userId!,
              databaseService: _databaseService,
            ),
        ],
      ),
      floatingActionButton: _getFloatingActionButton(),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(35),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(35),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: NavigationBar(
                backgroundColor: Colors.transparent,
              elevation: 0,
              height: 70,
              indicatorColor: const Color(0xFFFFB74D), // Soft Amber matching user theme
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _selectedIndex = index;
                  // Proactively refresh data when switching back to main tabs (Home, Orders, Pickup)
                  if (index <= 2 && _userId != null) {
                    _databaseService.refreshTracking(_userId!);
                  }
                });
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2),
                  label: 'Orders',
                ),
                NavigationDestination(
                  icon: Icon(Icons.outbox_outlined),
                  selectedIcon: Icon(Icons.outbox),
                  label: 'Pickup',
                ),
                NavigationDestination(
                  icon: Icon(Icons.dns_outlined),
                  selectedIcon: Icon(Icons.dns),
                  label: 'Dropbox',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _getSelectedTab(),
    );
  }

  Widget? _getFloatingActionButton() {
    if (_selectedIndex == 0) {
      return FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const OwnerVerifyScreen(),
            ),
          );
        },
        heroTag: 'home_verify_fab',
        child: const Icon(Icons.qr_code_scanner),
      );
    } else if (_selectedIndex == 1) {
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

  Widget _buildMiniStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetailerJungle(List<TrackingModel> orders) {
    // Platform detection logic
    final Map<String, int> counts = {
      'Shopee': 0,
      'Lazada': 0,
      'TikTok': 0,
      'Amazon': 0,
      'Others': 0,
    };

    for (var order in orders) {
      final name = order.shopName.toLowerCase();
      if (name.contains('shopee')) counts['Shopee'] = counts['Shopee']! + 1;
      else if (name.contains('lazada')) counts['Lazada'] = counts['Lazada']! + 1;
      else if (name.contains('tiktok')) counts['TikTok'] = counts['TikTok']! + 1;
      else if (name.contains('amazon')) counts['Amazon'] = counts['Amazon']! + 1;
      else counts['Others'] = counts['Others']! + 1;
    }

    final total = orders.isEmpty ? 1 : orders.length; // Prevent div by zero
    
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D2C24), // Deep Jungle Green
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Jungle subtle leaf pattern - using icons as placeholders
            Positioned(
              right: -20,
              top: -20,
              child: Icon(Icons.eco, size: 100, color: Colors.white.withOpacity(0.05)),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.forest, color: Color(0xFF10B981), size: 24),
                      const SizedBox(width: 12),
                      const Text(
                        'Retailer Jungle',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${orders.length} Parcels',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your shopping ecosystem distribution.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 13,
                    ),
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
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                              ),
                              Text(
                                '${entry.value}',
                                style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Stack(
                            children: [
                              Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              FractionallySizedBox(
                                widthFactor: percentage > 0 ? percentage : 0.02,
                                child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF059669), Color(0xFF10B981)],
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF10B981).withOpacity(0.3),
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
                  }).toList(),
                ],
              ),
            ),
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
                  Text(
                    'Dashboard Overview',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.4,
                    children: [
                      _buildMiniStatCard(
                        title: 'Active',
                        value: '$activeDropOffCount',
                        icon: Icons.local_shipping_rounded,
                        color: const Color(0xFF4C51F0),
                      ),
                      _buildMiniStatCard(
                        title: 'Drop Bin',
                        value: '$dropOffBinCount',
                        icon: Icons.inbox_rounded,
                        color: const Color(0xFF10B981),
                      ),
                      _buildMiniStatCard(
                        title: 'Pickups',
                        value: '$activePickupCount',
                        icon: Icons.outbox_rounded,
                        color: const Color(0xFFF59E0B),
                      ),
                      _buildMiniStatCard(
                        title: 'Pick Bin',
                        value: '$pickUpBinCount',
                        icon: Icons.inventory_2_rounded,
                        color: const Color(0xFF8B5CF6),
                      ),
                    ],
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
    Color statusColor;
    switch (order.status) {
      case 'pending':
        statusColor = Colors.orange;
        break;
      case 'in_transit':
        statusColor = Colors.blue;
        break;
      case 'delivered':
        statusColor = Colors.green;
        break;
      case 'awaiting_pickup':
        statusColor = Colors.indigo;
        break;
      case 'ready_for_pickup':
        statusColor = Colors.deepPurple;
        break;
      case 'retrieved':
        statusColor = Colors.grey;
        break;
      case 'done':
        statusColor = Colors.teal;
        break;
      default:
        statusColor = Colors.grey;
    }

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TrackingDetailsScreen(tracking: order),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    order.shopName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    order.getStatusText(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tracking ID: ${order.trackingId}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            if (order.expectedDeliveryDate != null) ...[
              const SizedBox(height: 4),
              Text(
                'Expected: ${order.expectedDeliveryDate}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAllOrdersTab() {
    if (_userId == null) return const Center(child: Text('Not logged in'));

    return StreamBuilder<List<TrackingModel>>(
      stream: _databaseService.getUserTrackingIds(_userId!),
      initialData: _databaseService
          .cachedTracking, // Use cached data to prevent loading state
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red[300],
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading orders',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }

        List<TrackingModel> allOrders = snapshot.data ?? [];

        if (allOrders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No orders yet',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add a tracking ID to get started',
                  style: TextStyle(
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100),
          itemCount: allOrders.length,
          itemBuilder: (context, index) {
            final order = allOrders[index];
            return Card(
              key: ValueKey(order.trackingId),
              margin: const EdgeInsets.only(bottom: 12),
              child: _buildOrderCard(order),
            );
          },
        );
      },
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

    return FutureBuilder<Map<String, dynamic>?>(
      future: _userDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        Map<String, dynamic>? userData = snapshot.data;

        return SingleChildScrollView(
          child: Column(
            children: [
              // Profile Header with Gradient
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFF6F00), // Orange 900
                      Color(0xFFF4511E), // Deep Orange 600
                      Color(0xFFE91E63), // Pink 500
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                    child: Column(
                      children: [
                        // Profile Avatar
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.white,
                            child: Text(
                              (userData?['fullName']?[0]?.toUpperCase() ??
                                  userData?['email']?[0]?.toUpperCase() ??
                                  'U'),
                              style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Name
                        Text(
                          userData?['fullName'] ?? 'User',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Email
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.email_outlined,
                              size: 16,
                              color: Colors.white.withOpacity(0.9),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                userData?['email'] ?? '',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Profile Information Cards
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Contact Information Card
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.contact_phone_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Contact Information',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          _buildInfoTile(
                            context,
                            userData: userData,
                            icon: Icons.phone_outlined,
                            title: 'Phone Number',
                            value: userData?['phoneNumber'] ?? 'Not set',
                            isEmpty: userData?['phoneNumber'] == null ||
                                (userData?['phoneNumber'] as String).isEmpty,
                            isEditable: true,
                            fieldKey: 'phoneNumber',
                          ),
                          const Divider(height: 1),
                          _buildInfoTile(
                            context,
                            userData: userData,
                            icon: Icons.home_outlined,
                            title: 'Address',
                            value: userData?['address'] ?? 'Not set',
                            isEmpty: userData?['address'] == null ||
                                (userData?['address'] as String).isEmpty,
                            isEditable: true,
                            fieldKey: 'address',
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Account Information Card
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.account_circle_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Account Information',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          _buildInfoTile(
                            context,
                            icon: Icons.email_outlined,
                            title: 'Email Address',
                            value: userData?['email'] ?? 'Not available',
                            isEmpty: false,
                          ),
                          const Divider(height: 1),
                          _buildInfoTile(
                            context,
                            icon: Icons.admin_panel_settings_outlined,
                            title: 'Role',
                            value: userData?['role'] ?? 'user',
                            isEmpty: false,
                          ),
                          const Divider(height: 1),
                          _buildInfoTile(
                            context,
                            icon: Icons.verified_user_outlined,
                            title: 'Account Status',
                            value: 'Verified',
                            isEmpty: false,
                            showValueIcon: true,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    if (userData?['role'] == 'admin') ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    const AdminDashboardScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.admin_panel_settings),
                          label: const Text('Open Admin Dashboard'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const RiderManagementScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.motorcycle),
                          label: const Text('Manage Delivery Riders'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout),
                        label: const Text('Logout'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade600,
                          side: BorderSide(color: Colors.red.shade600),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 22,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 16,
                          color: isEmpty ? Colors.grey[400] : Colors.grey[900],
                          fontWeight:
                              isEmpty ? FontWeight.normal : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (showValueIcon)
                      Icon(
                        Icons.check_circle,
                        size: 18,
                        color: Colors.green[600],
                      ),
                    if (isEditable && _userId != null)
                      IconButton(
                        icon: Icon(
                          Icons.edit,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: () => _showEditDialog(
                          context,
                          title,
                          fieldKey!,
                          value,
                          isEmpty,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Edit $title',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
