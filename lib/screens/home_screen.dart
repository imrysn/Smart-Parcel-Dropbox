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
import 'dropbox_control_screen.dart';
import 'add_pickup_screen.dart';
import '../widgets/notification_badge.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Smart Parcel Drop Box'),
        actions: [
          // Notifications button with badge - isolated widget prevents AppBar rebuilds
          if (_userId != null)
            NotificationBadge(
              userId: _userId!,
              databaseService: _databaseService,
            ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'View Logs',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const LogsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 1 || _selectedIndex == 2
          ? FloatingActionButton.extended(
              onPressed: () {
                if (_selectedIndex == 1) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AddTrackingScreen(),
                    ),
                  );
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AddPickupScreen(),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.add),
              label: Text(_selectedIndex == 1 ? 'Add Tracking ID' : 'Add Pickup Item'),
              heroTag: 'home_fab',
            )
          : null,
      bottomNavigationBar: NavigationBar(
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
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
      body: _getSelectedTab(),
    );
  }

  Widget _buildActiveOrdersTab() {
    if (_userId == null) return const Center(child: Text('Not logged in'));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dropbox Status Card (Enhanced)
          _buildDropboxStatusCard(),
          const SizedBox(height: 16),

          // Quick Stats Card
          StreamBuilder<List<TrackingModel>>(
            stream: _activeOrdersStream,
            initialData: _databaseService.cachedTracking
                .where((t) =>
                    t.mode == 'drop_off' &&
                    ['pending', 'in_transit', 'delivered'].contains(t.status))
                .toList(),
            builder: (context, snapshot) {
              final activeOrders = snapshot.data ?? [];
              final deliveredCount =
                  activeOrders.where((o) => o.status == 'delivered').length;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Quick Stats',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatItem(
                              'Active Orders',
                              '${activeOrders.length}',
                              Icons.local_shipping_outlined,
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildStatItem(
                              'In Drop Box',
                              '$deliveredCount',
                              Icons.inbox,
                              Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // Quick Actions Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.flash_on_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildQuickActionButton(
                    icon: Icons.notifications_outlined,
                    label: 'Notifications',
                    subtitle: 'View delivery updates',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const NotificationsScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildQuickActionButton(
                    icon: Icons.inventory_2_outlined,
                    label: 'View All Orders',
                    subtitle: 'See complete order history',
                    onTap: () {
                      setState(() {
                        _selectedIndex = 1; // Switch to Orders tab
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
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
      case 'ready_for_pickup':
        statusColor = Colors.deepPurple;
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
          padding: const EdgeInsets.all(16),
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
        return _buildPickupTab();
      case 3:
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
                    ],
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
