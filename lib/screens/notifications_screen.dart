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
  late final ScrollController _scrollController;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _initUser();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _userId == null) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    if (currentScroll >= maxScroll - 200) {
      if (_databaseService.hasMoreNotifications && !_databaseService.isFetchingMoreNotifications) {
        _databaseService.fetchNotifications(_userId!);
      }
    }
  }

  Future<void> _initUser() async {
    _userId = await _authService.currentUserId;
    if (mounted) setState(() {});
  }

  Future<void> _onRefresh() async {
    if (_userId != null) {
      await _databaseService.refreshNotifications(_userId!);
    }
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
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(color: UserTheme.primaryOrange));
            }

            final notifications = snapshot.data ?? [];
            if (notifications.isEmpty) {
              return RefreshIndicator(
                color: UserTheme.primaryOrange,
                onRefresh: _onRefresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Container(
                    height: MediaQuery.of(context).size.height * 0.7,
                    alignment: Alignment.center,
                    child: UserUi.emptyState(
                      context,
                      icon: Icons.notifications_off_rounded,
                      title: 'All caught up!',
                      subtitle: 'Your recent alerts and parcel updates will show up here.',
                    ),
                  ),
                ),
              );
            }

            final showBottomSpinner = _databaseService.hasMoreNotifications;

            return RefreshIndicator(
              color: UserTheme.primaryOrange,
              onRefresh: _onRefresh,
              child: ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                itemCount: notifications.length + (showBottomSpinner ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == notifications.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: UserTheme.primaryOrange,
                          ),
                        ),
                      ),
                    );
                  }
                  return _buildNotificationCard(notifications[index]);
                },
              ),
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
    final isRead = notification.isRead;

    // Custom gradient for icon container
    final iconGradient = LinearGradient(
      colors: isRead
          ? [
              isDark ? Colors.grey.shade700 : Colors.grey.shade400,
              isDark ? Colors.grey.shade800 : Colors.grey.shade500,
            ]
          : [
              baseColor,
              baseColor.withOpacity(0.75),
            ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isRead
            ? (isDark ? const Color(0xFF1E222D) : Colors.white)
            : (isDark ? baseColor.withOpacity(0.10) : baseColor.withOpacity(0.04)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRead
              ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06))
              : baseColor.withOpacity(isDark ? 0.35 : 0.25),
          width: isRead ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isRead
                ? Colors.black.withOpacity(isDark ? 0.2 : 0.03)
                : baseColor.withOpacity(0.12),
            blurRadius: isRead ? 10 : 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _handleNotificationTap(notification),
            splashColor: baseColor.withOpacity(0.1),
            highlightColor: baseColor.withOpacity(0.05),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  // Glowing accent pill bar for unread notifications
                  if (!isRead)
                    Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          bottomLeft: Radius.circular(20),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: baseColor.withOpacity(0.6),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox(width: 4),

                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Modern Icon Container with Gradient & Soft Glow Shadow
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: iconGradient,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: !isRead
                                  ? [
                                      BoxShadow(
                                        color: baseColor.withOpacity(0.35),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              _getIcon(notification.getIconName()),
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Notification Content
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title & Status Pill Row
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        notification.title,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: isRead ? FontWeight.w700 : FontWeight.w800,
                                          color: isDark
                                              ? (isRead ? UserTheme.nightTextSecondary : UserTheme.nightTextPrimary)
                                              : (isRead ? UserTheme.dayTextSecondary : UserTheme.dayTextPrimary),
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (!isRead)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: baseColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: baseColor.withOpacity(0.3),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 5,
                                              height: 5,
                                              decoration: BoxDecoration(
                                                color: baseColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              'NEW',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                                color: baseColor,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 5),

                                // Message Text
                                Text(
                                  notification.message,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.4,
                                    color: isDark
                                        ? (isRead ? UserTheme.nightTextMuted : UserTheme.nightTextSecondary)
                                        : (isRead ? UserTheme.dayTextMuted : UserTheme.dayTextSecondary),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Footer: Time & Tracking Pill Tag
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.schedule_rounded,
                                          size: 13,
                                          color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          notification.getFormattedDateTime(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (notification.trackingId != null && notification.trackingId!.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: UserTheme.primaryOrange.withOpacity(isDark ? 0.15 : 0.08),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: UserTheme.primaryOrange.withOpacity(0.25),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.inventory_2_outlined,
                                              size: 11,
                                              color: UserTheme.primaryOrange,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              notification.trackingId!,
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w800,
                                                color: UserTheme.primaryOrange,
                                                letterSpacing: 0.3,
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
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
      case 'check_box': return Icons.mark_email_read_rounded;
      default: return Icons.notifications_active_rounded;
    }
  }

  Future<void> _handleNotificationTap(NotificationModel notification) async {
    // 1. Mark notification as read
    if (!notification.isRead) {
      _databaseService.markNotificationAsRead(notification.id);
    }

    final titleLower = notification.title.toLowerCase();
    final messageLower = notification.message.toLowerCase();
    final typeLower = notification.type.toLowerCase();

    // 2. Check for "Parcel Delivered" -> Orders page (Index 1) > DELIVERED subpage (Index 1)
    if (titleLower.contains('delivered') ||
        messageLower.contains('dropped off') ||
        typeLower == 'parcel_delivered') {
      if (mounted) {
        Navigator.of(context).pop({'tabIndex': 1, 'subTabIndex': 1}); // Orders > Delivered tab
      }
      return;
    }

    // 3. Check for "Delivery Registered" -> Orders page (Index 1) > PENDING subpage (Index 0)
    if (titleLower.contains('registered') ||
        messageLower.contains('registered for drop off') ||
        typeLower == 'delivery' ||
        typeLower == 'status_update') {
      if (mounted) {
        Navigator.of(context).pop({'tabIndex': 1, 'subTabIndex': 0}); // Orders > Pending tab
      }
      return;
    }

    // 4. Check for "Parcel Retrieved" -> Orders page (Index 1) > RETRIEVED subpage (Index 3)
    if (titleLower.contains('retrieved') ||
        messageLower.contains('collected') ||
        typeLower == 'parcel_retrieved') {
      if (mounted) {
        Navigator.of(context).pop({'tabIndex': 1, 'subTabIndex': 3}); // Orders > Retrieved tab
      }
      return;
    }

    // 5. Pickup / Task notifications -> Tasks page (Index 2)
    if (typeLower.contains('pickup') || titleLower.contains('pickup')) {
      if (mounted) {
        Navigator.of(context).pop({'tabIndex': 2}); // Tasks tab
      }
      return;
    }

    // 6. Access / Scan / Dropbox notifications -> Dropbox Control page (Index 3)
    if (mounted) {
      Navigator.of(context).pop({'tabIndex': 3}); // Dropbox Control tab
    }
  }
}
