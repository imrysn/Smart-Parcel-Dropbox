import 'package:flutter/material.dart';
import '../config/user_theme.dart';
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
        final iconColor = IconTheme.of(context).color;
        return Semantics(
          button: true,
          label: 'Notifications',
          child: Tooltip(
            message: 'Notifications',
            child: InkResponse(
              radius: 22,
              onTap: () async {
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
              child: SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.notifications_outlined, color: iconColor),
                    if (unreadCount > 0)
                      Positioned(
                        right: 4,
                        top: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: UserTheme.statusError,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            unreadCount > 99 ? '99+' : '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
