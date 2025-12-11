import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/user_model.dart';
import '../models/tracking_model.dart';
import 'logs_screen.dart';

/// Admin dashboard for managing users, tracking IDs, and logs
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Admin Dashboard',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          elevation: 0,
          centerTitle: false,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people_outline), text: 'Users'),
              Tab(icon: Icon(Icons.qr_code_2), text: 'Tracking'),
              Tab(icon: Icon(Icons.history), text: 'Logs'),
            ],
            labelStyle: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        body: const TabBarView(
          children: [
            _UsersTab(),
            _TrackingTab(),
            // Ensure LogsScreen is accessible and passes the isAdmin flag
            LogsScreen(isAdmin: true),
          ],
        ),
      ),
    );
  }
}

class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) {
    final db = DatabaseService();
    return StreamBuilder<List<UserModel>>(
      stream: db.getAllUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _error(snapshot.error);
        }
        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          return _empty('No users found');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 3, // Enhanced elevation
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16), // Increased padding
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24, // Slightly larger avatar
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.15),
                          child: Text(
                            user.fullName.isNotEmpty
                                ? user.fullName[0].toUpperCase()
                                : 'U',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.fullName.isNotEmpty
                                    ? user.fullName
                                    : 'User',
                                style: const TextStyle(
                                  fontSize: 18, // Larger name
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                user.email,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        _RoleBadge(role: user.role, disabled: user.disabled),
                      ],
                    ),
                    const Divider(height: 24), // Separator
                    // User Management Toggles
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _ActionToggle(
                          label: 'Admin Role',
                          value: user.role == 'admin',
                          onChanged: (val) async {
                            final newRole = val ? 'admin' : 'user';
                            await db.setUserRole(
                              userId: user.uid,
                              role: newRole,
                            );
                          },
                        ),
                        _ActionToggle(
                          label: 'Remote Unlock',
                          value: user.canRemoteUnlock,
                          onChanged: (val) async {
                            await db.setUserRemoteUnlock(
                              userId: user.uid,
                              canRemoteUnlock: val,
                            );
                          },
                        ),
                        _ActionToggle(
                          label: user.disabled ? 'Enable User' : 'Disable User',
                          value: !user.disabled,
                          onChanged: (val) async {
                            await db.setUserDisabled(
                              userId: user.uid,
                              disabled: !val,
                            );
                          },
                          // Highlight Disable/Enable action
                          activeColor: user.disabled
                              ? Colors.green
                              : Colors.red,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _empty(String message) {
    return Center(
      child: Text(message, style: TextStyle(color: Colors.grey[600])),
    );
  }

  Widget _error(Object? error) {
    return Center(
      child: Text('Error: $error', style: TextStyle(color: Colors.red[400])),
    );
  }
}

class _TrackingTab extends StatelessWidget {
  const _TrackingTab();

  @override
  Widget build(BuildContext context) {
    final db = DatabaseService();
    return StreamBuilder<List<TrackingModel>>(
      stream: db.getAllTrackingIds(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return Center(
            child: Text(
              'No tracking IDs',
              style: TextStyle(color: Colors.grey[600]),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final t = items[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: Icon(
                  Icons.local_shipping,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                title: Text(
                  t.trackingId,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('${t.shopName} • ${t.getStatusText()}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Assigned User:',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    ),
                    Text(
                      t.userId.substring(0, 6), // Truncate user ID for display
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  final bool disabled;
  const _RoleBadge({required this.role, required this.disabled});

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;
    switch (role) {
      case 'admin':
        color = Colors.deepPurple;
        text = 'Admin';
        break;
      case 'courier':
        color = Colors.orange;
        text = 'Courier';
        break;
      default:
        color = Colors.blue;
        text = 'User';
    }
    if (disabled) {
      color = Colors.grey;
      text = '$text (disabled)';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16), // More rounded corners
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700, // Bolder text
          fontSize: 13, // Slightly larger font
        ),
      ),
    );
  }
}

class _ActionToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;
  const _ActionToggle({
    required this.label,
    required this.value,
    required this.onChanged,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          value ? Icons.check_circle_outline : Icons.cancel_outlined,
          color: value
              ? (activeColor ?? Theme.of(context).colorScheme.primary)
              : Colors.grey,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[800],
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Switch(
          value: value,
          onChanged: (val) {
            onChanged(val);
          },
          activeColor: activeColor ?? Theme.of(context).colorScheme.primary,
        ),
      ],
    );
  }
}
