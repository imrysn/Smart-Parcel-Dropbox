import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/scan_log_model.dart';
import '../../models/tracking_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../login_screen.dart';

/// Admin Dashboard - Manage users, tracking IDs, and logs (matches Firestore rules)
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _databaseService = DatabaseService();
  late Future<Map<String, dynamic>?> _currentUserFuture;

  @override
  void initState() {
    super.initState();
    final uid = _authService.currentUser?.uid;
    _currentUserFuture = uid != null
        ? _databaseService.getUserData(uid)
        : Future<Map<String, dynamic>?>.value(null);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _currentUserFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final userData = snapshot.data;
        final user = _authService.currentUser;

        if (user == null || userData == null) {
          return const Scaffold(
            body: Center(child: Text('Please sign in to access admin tools')),
          );
        }

        if ((userData['role'] ?? '') != 'admin') {
          return Scaffold(
            appBar: AppBar(title: const Text('Admin Dashboard')),
            body: const Center(
              child: Text('Access denied. Admin role required.'),
            ),
          );
        }

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Admin Dashboard'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
                  onPressed: _logout,
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.group_outlined), text: 'Users'),
                  Tab(icon: Icon(Icons.inventory_outlined), text: 'Tracking'),
                  Tab(icon: Icon(Icons.history), text: 'Logs'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _buildUsersTab(),
                _buildTrackingTab(),
                _buildLogsTab(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUsersTab() {
    return StreamBuilder<List<UserModel>>(
      stream: _databaseService.getAllUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          return const Center(child: Text('No users found'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(
                    user.fullName.isNotEmpty
                        ? user.fullName[0].toUpperCase()
                        : user.email[0].toUpperCase(),
                  ),
                ),
                title: Text(
                  user.fullName.isNotEmpty ? user.fullName : user.email,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(user.email), Text('Role: ${user.role}')],
                ),
                trailing: DropdownButton<String>(
                  value: user.role,
                  items: const [
                    DropdownMenuItem(value: 'user', child: Text('User')),
                    DropdownMenuItem(value: 'courier', child: Text('Courier')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _updateUserRole(user.uid, value);
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTrackingTab() {
    const statuses = ['pending', 'in_transit', 'delivered', 'retrieved'];
    return StreamBuilder<List<TrackingModel>>(
      stream: _databaseService.getAllTrackingIds(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return const Center(child: Text('No tracking IDs found'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final tracking = items[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
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
                            tracking.shopName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        DropdownButton<String>(
                          value: tracking.status,
                          items: statuses
                              .map(
                                (status) => DropdownMenuItem(
                                  value: status,
                                  child: Text(status),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              _updateTrackingStatus(tracking.trackingId, value);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Tracking ID: ${tracking.trackingId}'),
                    Text('User ID: ${tracking.userId}'),
                    if (tracking.expectedDeliveryDate != null)
                      Text('ETA: ${tracking.expectedDeliveryDate}'),
                    Text('Status: ${tracking.getStatusText()}'),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLogsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Scan Logs', Icons.qr_code),
          StreamBuilder<List<ScanLogModel>>(
            stream: _databaseService.getScanLogs(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Error: ${snapshot.error}'),
                );
              }
              final logs = snapshot.data ?? [];
              if (logs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No scan logs found'),
                );
              }
              return Column(
                children: logs
                    .map(
                      (log) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            log.accessGranted
                                ? Icons.check_circle
                                : Icons.cancel,
                            color: log.accessGranted
                                ? Colors.green
                                : Colors.red,
                          ),
                          title: Text(log.scannedCode),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(log.getFullFormattedDateTime()),
                              if (log.trackingId != null)
                                Text('Tracking: ${log.trackingId}'),
                              if (log.userId != null)
                                Text('User: ${log.userId}'),
                              if (log.reason != null)
                                Text('Reason: ${log.reason}'),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 16),
          _buildSectionTitle('Delivery Logs', Icons.local_shipping_outlined),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _databaseService.getAllDeliveryLogs(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('Error: ${snapshot.error}'),
                );
              }
              final logs = snapshot.data ?? [];
              if (logs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No delivery logs found'),
                );
              }
              return Column(
                children: logs
                    .map(
                      (log) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(
                            'Tracking: ${log['trackingId'] ?? 'N/A'}',
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (log['userId'] != null)
                                Text('User: ${log['userId']}'),
                              if (log['eventType'] != null)
                                Text('Event: ${log['eventType']}'),
                              if (log['details'] != null)
                                Text('Details: ${log['details']}'),
                              if (log['timestamp'] != null)
                                Text(
                                  'Time: ${_formatTimestamp(log['timestamp'])}',
                                ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _updateUserRole(String userId, String role) async {
    try {
      await _databaseService.updateUserRole(userId: userId, role: role);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Role updated to $role')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update role: $e')));
    }
  }

  Future<void> _updateTrackingStatus(String trackingId, String status) async {
    try {
      await _databaseService.updateTrackingStatus(
        trackingId: trackingId,
        status: status,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Status updated to $status')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update status: $e')));
    }
  }

  String _formatTimestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toLocal().toString();
    }
    return value.toString();
  }

  Future<void> _logout() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }
}
