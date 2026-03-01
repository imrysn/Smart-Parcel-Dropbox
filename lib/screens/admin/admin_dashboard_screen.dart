import 'dart:async';
import 'package:flutter/material.dart';

import '../../config/admin_theme.dart';
import '../../models/scan_log_model.dart';
import '../../models/tracking_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/service_locator.dart';
import '../../services/tracking_service.dart';
import '../../services/user_service.dart';
import '../../services/websocket_service.dart';
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
  late TabController _tabController;
  late Future<Map<String, dynamic>?> _currentUserDataFuture;
  String? _userId;

  // Cache streams in state to prevent re-fetching on tab switch
  late Stream<List<UserModel>> _usersStream;
  late Stream<List<TrackingModel>> _trackingStream;
  late Stream<List<ScanLogModel>> _scanLogsStream;
  late Stream<List<Map<String, dynamic>>> _deliveryLogsStream;

  // Real-time tracking state
  StreamSubscription<Map<String, dynamic>>? _trackingStatusSub;
  bool _trackingRefreshing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initData();
  }

  Future<void> _initData() async {
    _userId = await _authService.currentUserId;
    if (_userId != null) {
      _databaseService.initSocket(_userId!);
      _currentUserDataFuture = _databaseService.getUserData(_userId!);
    } else {
      _currentUserDataFuture = Future.value(null);
    }

    // --- Assign streams FIRST before triggering any fetch ---
    // Broadcast streams do not replay; if data is emitted before a
    // StreamBuilder subscribes the widget spins forever.
    final trackingService = getIt<TrackingService>();
    final userService     = getIt<UserService>();
    final ws              = getIt<WebSocketService>();

    _usersStream         = userService.usersStream;
    _trackingStream      = trackingService.trackingStream;
    _scanLogsStream      = _databaseService.getScanLogs();
    _deliveryLogsStream  = _databaseService.getAllDeliveryLogs();

    // Now notify Flutter so StreamBuilders subscribe before we push data
    if (mounted) setState(() {});

    // --- Trigger initial data fetches (emits into already-subscribed streams) ---
    userService.refreshAllUsers().ignore();
    trackingService.refreshAllTracking().ignore();

    // Subscribe to hardware status-change events for automatic tracking refresh
    _trackingStatusSub = ws.trackingStatusChanges.listen((_) async {
      if (!mounted) return;
      setState(() => _trackingRefreshing = true);
      await trackingService.refreshAllTracking();
      if (mounted) setState(() => _trackingRefreshing = false);
    });
  }

  @override
  void dispose() {
    _trackingStatusSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Apply admin theme to entire screen
    return Theme(
      data: AdminTheme.theme,
      child: FutureBuilder<Map<String, dynamic>?>(
        future: _currentUserDataFuture,
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

          if (_userId == null || userData == null) {
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                                  color: Colors.white
                                                      .withOpacity(0.9),
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
                        Tab(
                          icon: Icon(Icons.local_shipping_outlined),
                          text: 'Pickup',
                        ),
                      ],
                    ),
                  ),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: [
                  _KeepAlivePage(child: _buildUsersTab()),
                  _KeepAlivePage(child: _buildTrackingTab()),
                  _KeepAlivePage(child: _buildLogsTab()),
                  _KeepAlivePage(
                    child: PickupScreen(
                      userId: _userId!,
                      databaseService: _databaseService,
                      isAdmin: true,
                    ),
                  ),
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
      stream: _usersStream,
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
                icon:
                    Icon(Icons.arrow_drop_down, color: AdminTheme.primaryBlue),
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
            const SizedBox(width: 8),

            // Delete Button
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: _userId == user.uid
                    ? AdminTheme.textMuted.withOpacity(0.3)
                    : AdminTheme.statusError,
              ),
              tooltip: _userId == user.uid
                  ? 'Cannot delete yourself'
                  : 'Delete user',
              onPressed:
                  _userId == user.uid ? null : () => _confirmDeleteUser(user),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackingTab() {
    return StreamBuilder<List<TrackingModel>>(
      stream: _trackingStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            (snapshot.data == null || snapshot.data!.isEmpty)) {
          return Center(
            child: CircularProgressIndicator(color: AdminTheme.primaryBlue),
          );
        }

        if (snapshot.hasError) {
          return _buildErrorState(
              'Error loading tracking data: ${snapshot.error}');
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
        final pendingCount    = items.where((t) => t.status == 'pending').length;
        final inTransitCount  = items.where((t) => t.status == 'in_transit').length;
        final deliveredCount  = items.where((t) => ['delivered', 'done'].contains(t.status)).length;
        final awaitingCount   = items.where((t) => t.status == 'awaiting_pickup').length;
        final retrievedCount  = items.where((t) => t.status == 'retrieved').length;

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
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.inventory_2_outlined,
                    label: 'Awaiting',
                    value: '$awaitingCount',
                    color: const Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.done_all,
                    label: 'Retrieved',
                    value: '$retrievedCount',
                    color: const Color(0xFF8B5CF6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Section Header with LIVE badge and Refresh button
            Row(
              children: [
                Expanded(
                  child: _buildSectionHeader('Tracking', Icons.inventory_2),
                ),
                // LIVE indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AdminTheme.statusSuccess.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AdminTheme.statusSuccess, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_trackingRefreshing)
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AdminTheme.statusSuccess,
                          ),
                        )
                      else
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AdminTheme.statusSuccess,
                            shape: BoxShape.circle,
                          ),
                        ),
                      const SizedBox(width: 5),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: AdminTheme.statusSuccess,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Manual refresh button
                IconButton(
                  icon: Icon(Icons.refresh, color: AdminTheme.primaryBlue),
                  tooltip: 'Refresh tracking list',
                  onPressed: () async {
                    setState(() => _trackingRefreshing = true);
                    await getIt<TrackingService>().refreshAllTracking();
                    if (mounted) setState(() => _trackingRefreshing = false);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Tracking List (read-only — status driven by hardware)
            ...items.map((tracking) => _buildTrackingCard(tracking)).toList(),
          ],
        );
      },
    );
  }

  Widget _buildTrackingCard(TrackingModel tracking) {
    final statusColor = AdminTheme.getStatusColor(tracking.status);
    final modeLabel = (tracking.mode == 'pick_up' || tracking.mode == 'pickup')
        ? 'PICK UP'
        : 'DROP OFF';
    final modeColor = (tracking.mode == 'pick_up' || tracking.mode == 'pickup')
        ? const Color(0xFF6366F1)
        : AdminTheme.accentTeal;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Status dot
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

                // Mode badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: modeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: modeColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    modeLabel,
                    style: TextStyle(
                      color: modeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Tracking Details
            _buildInfoRow(Icons.qr_code, 'Tracking ID', tracking.trackingId),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.person_outline, 'User ID', tracking.userId),
            if (tracking.expectedDeliveryDate != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.calendar_today,
                'Expected Delivery',
                tracking.expectedDeliveryDate!,
              ),
            ],
            if (tracking.deliveredAt != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.check_circle_outline,
                'Delivered At',
                _formatTimestamp(tracking.deliveredAt!.toIso8601String()),
              ),
            ],
            if (tracking.retrievedAt != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.done_all,
                'Retrieved At',
                _formatTimestamp(tracking.retrievedAt!.toIso8601String()),
              ),
            ],
            const SizedBox(height: 12),

            // Read-only Status Badge — set automatically by hardware
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getStatusIcon(tracking.status), size: 15, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        tracking.getStatusText(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Auto-updated label
                Icon(Icons.sensors, size: 14, color: AdminTheme.textMuted),
                const SizedBox(width: 4),
                Text(
                  'Auto-updated by hardware',
                  style: TextStyle(
                    color: AdminTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
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
            stream: _scanLogsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: CircularProgressIndicator(
                        color: AdminTheme.primaryBlue),
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
                children:
                    logs.take(10).map((log) => _buildScanLogCard(log)).toList(),
              );
            },
          ),

          const SizedBox(height: 24),

          // Delivery Logs Section
          _buildSectionHeader('Delivery Logs', Icons.local_shipping_outlined),
          const SizedBox(height: 12),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _deliveryLogsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: CircularProgressIndicator(
                        color: AdminTheme.primaryBlue),
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
                children: logs
                    .take(10)
                    .map((log) => _buildDeliveryLogCard(log))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScanLogCard(ScanLogModel log) {
    final isGranted = log.accessGranted;
    final statusColor =
        isGranted ? AdminTheme.statusSuccess : AdminTheme.statusError;

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
      case 'awaiting_pickup':
        return Icons.inventory_2_outlined;
      case 'delivered':
      case 'done':
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
      // Refresh user list to update UI
      _databaseService.refreshAllUsers();
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
      // Refresh tracking stream to update UI
      if (mounted) {
        setState(() {
          _trackingStream = _databaseService.getAllTrackingIds();
        });
      }
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
    if (value == null) return 'N/A';
    try {
      final date = DateTime.parse(value.toString()).toLocal();
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return value.toString();
    }
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

  Future<void> _confirmDeleteUser(UserModel user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AdminTheme.backgroundCard,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AdminTheme.statusError),
            const SizedBox(width: 12),
            Text(
              'Delete User',
              style: TextStyle(color: AdminTheme.textPrimary),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to permanently delete this user?',
              style: TextStyle(
                color: AdminTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminTheme.backgroundSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AdminTheme.statusError.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDialogInfoRow(
                      'Name', user.fullName.isNotEmpty ? user.fullName : 'N/A'),
                  const SizedBox(height: 8),
                  _buildDialogInfoRow('Email', user.email),
                  const SizedBox(height: 8),
                  _buildDialogInfoRow('Role', user.role.toUpperCase()),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminTheme.statusError.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AdminTheme.statusError.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: AdminTheme.statusError,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This will permanently delete all user data including tracking IDs, notifications, and logs.',
                      style: TextStyle(
                        color: AdminTheme.statusError,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            child: const Text('Delete User'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _deleteUser(user.uid);
    }
  }

  Widget _buildDialogInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            '$label:',
            style: TextStyle(
              color: AdminTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: AdminTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _deleteUser(String userId) async {
    try {
      await _databaseService.deleteUser(userId);
      // Refresh user list to update UI
      _databaseService.refreshAllUsers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('User deleted successfully'),
          backgroundColor: AdminTheme.statusSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete user: $e'),
          backgroundColor: AdminTheme.statusError,
        ),
      );
    }
  }
}

/// Helper widget to keep tabs alive when switching
class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}
