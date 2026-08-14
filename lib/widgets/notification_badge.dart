import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../screens/notifications_screen.dart';

typedef TabSelectionCallback = void Function(int tabIndex, {int? subTabIndex});

/// Notification Badge Widget
/// 
/// Isolated widget that only rebuilds when notification count changes
/// Prevents entire AppBar from rebuilding
class NotificationBadge extends StatelessWidget {
  final String userId;
  final DatabaseService databaseService;
  final TabSelectionCallback? onSelectTab;

  const NotificationBadge({
    super.key,
    required this.userId,
    required this.databaseService,
    this.onSelectTab,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: databaseService.getUnreadNotificationsCount(userId),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Notifications',
              onPressed: () async {
                final result = await Navigator.of(context).push<Map<String, dynamic>>(
                  MaterialPageRoute(
                    builder: (context) => const NotificationsScreen(),
                  ),
                );
                if (result != null && onSelectTab != null) {
                  final int tabIndex = result['tabIndex'] ?? 0;
                  final int? subTabIndex = result['subTabIndex'];
                  onSelectTab!(tabIndex, subTabIndex: subTabIndex);
                }
              },
            ),
            if (unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
