import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../screens/notifications_screen.dart';

/// Notification Badge Widget
/// 
/// Isolated widget that only rebuilds when notification count changes
/// Prevents entire AppBar from rebuilding
class NotificationBadge extends StatelessWidget {
  final String userId;
  final DatabaseService databaseService;

  const NotificationBadge({
    super.key,
    required this.userId,
    required this.databaseService,
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
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const NotificationsScreen(),
                  ),
                );
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
