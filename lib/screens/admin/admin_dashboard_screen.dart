import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../config/admin_theme.dart';
import '../../models/scan_log_model.dart';
import '../../models/tracking_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../login_screen.dart';

/// Admin Dashboard - Professional slate blue theme
/// Distinct from user's luxury gold theme
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final DatabaseService _databaseService = DatabaseService();
  late Future<Map<String, dynamic>?> _currentUserFuture;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final uid = _authService.currentUser?.uid;
    _currentUserFuture = uid != null
        ? _databaseService.getUserData(uid)
        : Future<Map<String, dynamic>?>.value(null);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Apply admin theme to entire screen
    return Theme(
      data: AdminTheme.theme,
      child: FutureBuilder<Map<String, dynamic>?>(
        future: _currentUserFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              backgroundColor: AdminTheme.backgroundLight,
              body: Center(
                child: CircularProgressIndicator(
                  color: AdminTheme.primaryBlue,
                ),
              ),
            );
          }

          final userData = snapshot.data;
          final user = _authService.currentUser;

          if (user == null || userData == null) {
            return Scaffold(
              backgroundColor: AdminTheme.backgroundLight,
              body: Center(
                child: Text(
                  'Please sign in to access admin tools',
                  style: TextStyle(color: AdminTheme.textPrimary),
                ),
              ),
            );
          }

          if ((userData['role'] ?? '') != 'admin') {
            return Scaffold(
              backgroundColor: AdminTheme.backgroundLight,
              appBar: AppBar(
                title: const Text('Admin Dashboard'),
                backgroundColor: AdminTheme.primaryBlue,
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 64,
                      color: AdminTheme.statusError,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Access Denied',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Admin role required',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          }

          return Scaffold(
            backgroundColor: AdminTheme.backgroundLight,
            body: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverAppBar(
                    floating: true,
                    pinned: true,
                    expandedHeight: 120,
                    backgroundColor: AdminTheme.primaryBlue,
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AdminTheme.primaryBlueDark,
                              AdminTheme.primaryBlue,
                            ],
                          ),
                        ),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.admin_panel_settings,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Admin Dashboard',
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineMedium
                                                ?.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'System Management',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Colors.white.withOpacity(0.9),
                                                  letterSpacing: 0.5,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.logout),
                                      tooltip: 'Logout',
                                      onPressed: _logout,
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    bottom: TabBar(
                      controller: _tabController,
                      tabs: const [
                        Tab(
                          icon: Icon(Icons.group_outlined),
                          text: 'Users',
                        ),
                        Tab(
                          icon: Icon(Icons.inventory_outlined),
                          text: 'Tracking',
                        ),
                        Tab(
                          icon: Icon(Icons.history),
                          text: 'Logs',
                        ),
                      ],
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildUsersTab(),
                  _buildTrackingTab(),
                  _buildLogsTab(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUsersTab() {
    return StreamBuilder<List<UserModel>>(
      stream: _databaseService.getAllUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: AdminTheme.primaryBlue),
          );
        }

        if (snapshot.hasError) {
          return _buildErrorState('Error loading users: ${snapshot.error}');
        }

        final users = snapshot.data ?? [];
        
        if (users.isEmpty) {
          return _buildEmptyState(
            icon: Icons.group_outlined,
            title: 'No Users Found',
            message: 'No registered users in the system',
          );
        }

        // Calculate statistics
        final adminCount = users.where((u) => u.role == 'admin').length;
        final userCount = users.where((u) => u.role == 'user').length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Statistics Cards
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.people,
                    label: 'Total Users',
                    value: '${users.length}',
                    color: AdminTheme.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.admin_panel_settings,
                    label: 'Admins',
                    value: '$adminCount',
                    color: AdminTheme.roleAdmin,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.person,
                    label: 'Users',
                    value: '$userCount',
                    color: AdminTheme.roleUser,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Section Header
            _buildSectionHeader('User Management', Icons.group),
            const SizedBox(height: 12),
            
            // User List
            ...users.map((user) => _buildUserCard(user)).toList(),
          ],
        );
      },
    );
  }

  Widget _buildUserCard(UserModel user) {
    final roleColor = AdminTheme.getRoleColor(user.role);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: roleColor.withOpacity(0.2),
                shape: BoxShape.circle,
                border: Border.all(color: roleColor, width: 2),
              ),
              child: Center(
                child: Text(
                  user.fullName.isNotEmpty
                      ? user.fullName[0].toUpperCase()
                      : user.email[0].toUpperCase(),
                  style: TextStyle(
                    color: roleColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            
            // User Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName.isNotEmpty ? user.fullName : user.email,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: roleColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: roleColor, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              user.role == 'admin'
                                  ? Icons.admin_panel_settings
                                  : Icons.person,
                              size: 14,
                              color: roleColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              user.role.toUpperCase(),
                              style: TextStyle(
                                color: roleColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
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
            
            // Role Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AdminTheme.backgroundSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFE2E8F0).withOpacity(0.3),
                ),
              ),
              child: DropdownButton<String>(
                value: user.role,
                underline: const SizedBox(),
                dropdownColor: AdminTheme.backgroundCard,
                icon: Icon(Icons.arrow_drop_down, color: AdminTheme.primaryBlue),
                style: TextStyle(color: AdminTheme.textPrimary, fontSize: 14),
                items: const [
                  DropdownMenuItem(
                    value: 'user',
                    child: Text('User'),
                  ),
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text('Admin'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null && value != user.role) {
                    _updateUserRole(user.uid, value);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackingTab() {
    const statuses = ['pending', 'in_transit', 'delivered', 'retrieved'];
    
    return StreamBuilder<List<TrackingModel>>(
      stream: _databaseService.getAllTrackingIds(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: AdminTheme.primaryBlue),
          );
        }

        if (snapshot.hasError) {
          return _buildErrorState('Error loading tracking data: ${snapshot.error}');
        }

        final items = snapshot.data ?? [];
        
        if (items.isEmpty) {
          return _buildEmptyState(
            icon: Icons.inventory_outlined,
            title: 'No Tracking IDs',
            message: 'No tracking IDs found in the system',
          );
        }

        // Calculate statistics
        final pendingCount = items.where((t) => t.status == 'pending').length;
        final inTransitCount = items.where((t) => t.status == 'in_transit').length;
        final deliveredCount = items.where((t) => t.status == 'delivered').length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Statistics Cards
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.pending_actions,
                    label: 'Pending',
                    value: '$pendingCount',
                    color: AdminTheme.statusWarning,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.local_shipping,
                    label: 'In Transit',
                    value: '$inTransitCount',
                    color: AdminTheme.statusInfo,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.check_circle,
                    label: 'Delivered',
                    value: '$deliveredCount',
                    color: AdminTheme.statusSuccess,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Section Header
            _buildSectionHeader('Tracking Management', Icons.inventory_2),
            const SizedBox(height: 12),
            
            // Tracking List
            ...items.map((tracking) => _buildTrackingCard(tracking, statuses)).toList(),
          ],
        );
      },
    );
  }

  Widget _buildTrackingCard(TrackingModel tracking, List<String> statuses) {
    final statusColor = AdminTheme.getStatusColor(tracking.status);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Status Indicator
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                
                // Shop Name
                Expanded(
                  child: Text(
                    tracking.shopName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                
                // Status Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AdminTheme.backgroundSurface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFE2E8F0).withOpacity(0.3),
                    ),
                  ),
                  child: DropdownButton<String>(
                    value: tracking.status,
                    underline: const SizedBox(),
                    dropdownColor: AdminTheme.backgroundCard,
                    icon: Icon(Icons.arrow_drop_down, color: statusColor),
                    style: TextStyle(color: statusColor, fontSize: 13),
                    items: statuses
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(
                              status.replaceAll('_', ' ').toUpperCase(),
                              style: TextStyle(
                                color: AdminTheme.getStatusColor(status),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null && value != tracking.status) {
                        _updateTrackingStatus(tracking.trackingId, value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Tracking Details
            _buildInfoRow(
              Icons.qr_code,
              'Tracking ID',
              tracking.trackingId,
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.person_outline,
              'User ID',
              tracking.userId,
            ),
            if (tracking.expectedDeliveryDate != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.calendar_today,
                'Expected Delivery',
                tracking.expectedDeliveryDate!,
              ),
            ],
            const SizedBox(height: 12),
            
            // Status Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getStatusIcon(tracking.status),
                    size: 16,
                    color: statusColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    tracking.getStatusText(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
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

  Widget _buildLogsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scan Logs Section
          _buildSectionHeader('Scan Logs', Icons.qr_code_scanner),
          const SizedBox(height: 12),
          StreamBuilder<List<ScanLogModel>>(
            stream: _databaseService.getScanLogs(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: AdminTheme.primaryBlue),
                  ),
                );
              }
              
              if (snapshot.hasError) {
                return _buildErrorCard('Error loading scan logs');
              }
              
              final logs = snapshot.data ?? [];
              
              if (logs.isEmpty) {
                return _buildEmptyCard('No scan logs found');
              }
              
              return Column(
                children: logs.take(10).map((log) => _buildScanLogCard(log)).toList(),
              );
            },
          ),
          
          const SizedBox(height: 24),
          
          // Delivery Logs Section
          _buildSectionHeader('Delivery Logs', Icons.local_shipping_outlined),
          const SizedBox(height: 12),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _databaseService.getAllDeliveryLogs(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: AdminTheme.primaryBlue),
                  ),
                );
              }
              
              if (snapshot.hasError) {
                return _buildErrorCard('Error loading delivery logs');
              }
              
              final logs = snapshot.data ?? [];
              
              if (logs.isEmpty) {
                return _buildEmptyCard('No delivery logs found');
              }
              
              return Column(
                children: logs.take(10).map((log) => _buildDeliveryLogCard(log)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScanLogCard(ScanLogModel log) {
    final isGranted = log.accessGranted;
    final statusColor = isGranted ? AdminTheme.statusSuccess : AdminTheme.statusError;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isGranted ? Icons.check_circle : Icons.cancel,
                color: statusColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.scannedCode,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    log.getFullFormattedDateTime(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (log.trackingId != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Tracking: ${log.trackingId}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AdminTheme.primaryBlue,
                          ),
                    ),
                  ],
                  if (log.reason != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Reason: ${log.reason}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AdminTheme.statusWarning,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryLogCard(Map<String, dynamic> log) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AdminTheme.statusInfo.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                color: AdminTheme.statusInfo,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (log['trackingId'] != null)
                    Text(
                      'Tracking: ${log['trackingId']}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                    ),
                  if (log['eventType'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Event: ${log['eventType']}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (log['details'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      log['details'],
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AdminTheme.textMuted,
                          ),
                    ),
                  ],
                  if (log['timestamp'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatTimestamp(log['timestamp']),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper Widgets
  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminTheme.backgroundCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
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
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AdminTheme.primaryBlue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: AdminTheme.primaryBlue,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AdminTheme.textMuted),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AdminTheme.textPrimary,
                  fontFamily: 'monospace',
                ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 80,
              color: AdminTheme.textMuted.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 80,
              color: AdminTheme.statusError,
            ),
            const SizedBox(height: 16),
            Text(
              'Error',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: AdminTheme.statusError),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AdminTheme.statusError,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.pending_actions;
      case 'in_transit':
        return Icons.local_shipping;
      case 'delivered':
        return Icons.check_circle;
      case 'retrieved':
        return Icons.done_all;
      default:
        return Icons.help_outline;
    }
  }

  // Actions
  Future<void> _updateUserRole(String userId, String role) async {
    try {
      await _databaseService.updateUserRole(userId: userId, role: role);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Role updated to $role'),
          backgroundColor: AdminTheme.statusSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update role: $e'),
          backgroundColor: AdminTheme.statusError,
        ),
      );
    }
  }

  Future<void> _updateTrackingStatus(String trackingId, String status) async {
    try {
      await _databaseService.updateTrackingStatus(
        trackingId: trackingId,
        status: status,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status updated to $status'),
          backgroundColor: AdminTheme.statusSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: AdminTheme.statusError,
        ),
      );
    }
  }

  String _formatTimestamp(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate().toLocal();
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return value.toString();
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AdminTheme.backgroundCard,
        title: Text(
          'Logout',
          style: TextStyle(color: AdminTheme.textPrimary),
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: AdminTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminTheme.statusError,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }
}
