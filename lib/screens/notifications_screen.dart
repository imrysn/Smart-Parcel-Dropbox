import 'package:flutter/material.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../models/notification_model.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final AuthService _authService = AuthService();
  String? _userId;

  @override
  void initState() {
    super.initState();
    _initUser();
  }

  Future<void> _initUser() async {
    _userId = await _authService.currentUserId;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return Container(
        decoration: UserUi.pageBackground(context),
        child: const Scaffold(backgroundColor: Colors.transparent, body: Center(child: CircularProgressIndicator(color: UserTheme.primaryOrange))),
      );
    }

    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: UserTheme.appBarGradient(
          title: 'Notifications',
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            _buildUnreadBadge(),
            _buildActionMenu(),
          ],
        ),
        body: StreamBuilder<List<NotificationModel>>(
          stream: _databaseService.getUserNotifications(_userId!),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: UserTheme.primaryOrange));
            }

            final notifications = snapshot.data ?? [];
            if (notifications.isEmpty) {
              return UserUi.emptyState(
                context,
                icon: Icons.notifications_off_rounded,
                title: 'All caught up!',
                subtitle: 'Your recent alerts and parcel updates will show up here.',
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              itemCount: notifications.length,
              itemBuilder: (context, index) => _buildNotificationCard(notifications[index]),
            );
          },
        ),
      ),
    );
  }

  Widget _buildUnreadBadge() {
    return StreamBuilder<int>(
      stream: _databaseService.getUnreadNotificationsCount(_userId!),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
            child: Text('$count NEW', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
        );
      },
    );
  }

  Widget _buildActionMenu() {
    return PopupMenuButton(
      icon: const Icon(Icons.tune_rounded, size: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        PopupMenuItem(
          onTap: () async {
            await Future.delayed(const Duration(milliseconds: 100));
            await _databaseService.markAllNotificationsAsRead(_userId!);
          },
          child: const Row(
            children: [
              Icon(Icons.done_all_rounded, size: 20, color: UserTheme.statusSuccess),
              SizedBox(width: 12),
              Text('Mark all read', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationCard(NotificationModel notification) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = Color(notification.getColorValue());
    final statusColor = notification.isRead ? (isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted) : baseColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: UserUi.surfaceCard(
        context,
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () {
            if (!notification.isRead) _databaseService.markNotificationAsRead(notification.id);
          },
          borderRadius: BorderRadius.circular(UserTheme.radiusL),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: !notification.isRead ? Border(left: BorderSide(color: baseColor, width: 4)) : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                  child: Icon(_getIcon(notification.getIconName()), color: statusColor, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: notification.isRead ? FontWeight.w700 : FontWeight.w900,
                                color: isDark ? (notification.isRead ? UserTheme.nightTextSecondary : UserTheme.nightTextPrimary) : (notification.isRead ? UserTheme.dayTextSecondary : UserTheme.dayTextPrimary),
                              ),
                            ),
                          ),
                          if (!notification.isRead)
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: baseColor, shape: BoxShape.circle, boxShadow: [BoxShadow(color: baseColor.withOpacity(0.4), blurRadius: 6, spreadRadius: 1)])),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        notification.message,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded, size: 12, color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
                          const SizedBox(width: 4),
                          Text(
                            notification.getFormattedDateTime(),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
                          ),
                          if (notification.trackingId != null) ...[
                            const SizedBox(width: 12),
                            Icon(Icons.qr_code_rounded, size: 12, color: UserTheme.primaryOrange.withOpacity(0.6)),
                            const SizedBox(width: 4),
                            Text(
                              notification.trackingId!,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: UserTheme.primaryOrange, letterSpacing: 0.5),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIcon(String name) {
    switch (name) {
      case 'qr_code_scanner': return Icons.qr_code_scanner_rounded;
      case 'check_circle': return Icons.check_circle_rounded;
      case 'cancel': return Icons.cancel_rounded;
      case 'local_shipping': return Icons.local_shipping_rounded;
      case 'update': return Icons.update_rounded;
      case 'inventory': return Icons.inventory_2_rounded;
      case 'check_box': return Icons.check_box_rounded;
      default: return Icons.notifications_rounded;
    }
  }
}
