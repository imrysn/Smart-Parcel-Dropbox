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
  int _selectedFilter = 0; // 0: All, 1: Unread, 2: Deliveries, 3: Security

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

  Future<void> _markAllRead() async {
    if (_userId == null) return;
    await _databaseService.markAllNotificationsAsRead(_userId!);
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All notifications marked as read'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: UserTheme.statusSuccess,
        duration: Duration(seconds: 2),
      ),
    );
  }

  List<NotificationModel> _applyFilter(List<NotificationModel> all) {
    switch (_selectedFilter) {
      case 1:
        return all.where((n) => !n.isRead).toList();
      case 2:
        return all.where((n) => n.isDeliveryAlert).toList();
      case 3:
        return all.where((n) => n.isSecurityAlert).toList();
      default:
        return all;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return Container(
        decoration: UserUi.pageBackground(context),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: UserTheme.appBarGradient(
            title: 'Notifications',
            centerTitle: false,
            context: context,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: _buildLoadingSkeletons(),
        ),
      );
    }

    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: UserTheme.appBarGradient(
          title: 'Notifications',
          centerTitle: false,
          context: context,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            _buildMarkAllAction(),
            const SizedBox(width: 8),
          ],
        ),
        body: StreamBuilder<List<NotificationModel>>(
          stream: _databaseService.getUserNotifications(_userId!),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return _buildLoadingSkeletons();
            }

            final allNotifications = snapshot.data ?? [];
            final unreadCount = allNotifications.where((n) => !n.isRead).length;
            final filtered = _applyFilter(allNotifications);
            final showBottomSpinner =
                _databaseService.hasMoreNotifications && _selectedFilter == 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (allNotifications.isNotEmpty) _buildFilterBar(unreadCount),
                Expanded(
                  child: filtered.isEmpty
                      ? _buildEmptyState(hasAnyNotifications: allNotifications.isNotEmpty)
                      : RefreshIndicator(
                          color: UserTheme.primaryOrange,
                          onRefresh: _onRefresh,
                          child: ListView.builder(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: UserUi.listPadding(context, top: 6, bottom: 40),
                            itemCount: filtered.length + (showBottomSpinner ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == filtered.length) {
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

                              final item = filtered[index];
                              final groupLabel = item.getDateGroupLabel();
                              final showGroupHeader = index == 0 ||
                                  filtered[index - 1].getDateGroupLabel() != groupLabel;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (showGroupHeader)
                                    _buildGroupHeader(groupLabel, isFirst: index == 0),
                                  _buildNotificationCard(item),
                                ],
                              );
                            },
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoadingSkeletons() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: UserUi.listPadding(context, top: 16, bottom: 24),
      itemCount: 5,
      itemBuilder: (context, _) => UserUi.shimmerCard(context, height: 96),
    );
  }

  Widget _buildMarkAllAction() {
    return StreamBuilder<int>(
      stream: _databaseService.getUnreadNotificationsCount(_userId!),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Center(
          child: TextButton.icon(
            onPressed: _markAllRead,
            icon: const Icon(Icons.done_all_rounded, size: 17, color: UserTheme.primaryOrange),
            label: const Text(
              'Mark all read',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: UserTheme.primaryOrange,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              backgroundColor: UserTheme.primaryOrange.withValues(alpha: 0.10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterBar(int unreadCount) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final padding = UserUi.listPadding(context, top: 8, bottom: 8);
    final items = <String>[
      'All',
      unreadCount > 0 ? 'Unread ($unreadCount)' : 'Unread',
      'Deliveries',
      'Security',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.only(
        left: padding.left,
        right: padding.right,
        top: 6,
        bottom: 10,
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final selected = _selectedFilter == i;
          return Padding(
            padding: EdgeInsets.only(right: i == items.length - 1 ? 0 : 8),
            child: InkWell(
              onTap: () => setState(() => _selectedFilter = i),
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? UserTheme.primaryOrange
                      : (isDark ? UserTheme.nightCard : UserTheme.dayCard),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? UserTheme.primaryOrange
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.07)),
                  ),
                ),
                child: Text(
                  items[i],
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white
                        : (isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildGroupHeader(String label, {bool isFirst = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 4 : 12, bottom: 10, left: 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
        ),
      ),
    );
  }

  Widget _buildEmptyState({required bool hasAnyNotifications}) {
    final title = hasAnyNotifications
        ? (_selectedFilter == 1 ? 'No unread alerts' : 'Nothing in this filter')
        : 'All caught up!';
    final subtitle = hasAnyNotifications
        ? 'Try switching filters or pull down to refresh.'
        : 'Your parcel deliveries, courier dispatches, and box alerts will show up here.';

    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        color: UserTheme.primaryOrange,
        onRefresh: _onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: UserUi.emptyState(
                context,
                icon: hasAnyNotifications
                    ? Icons.filter_list_off_rounded
                    : Icons.notifications_none_rounded,
                title: title,
                subtitle: subtitle,
                actionLabel: hasAnyNotifications && _selectedFilter != 0 ? 'Show All' : null,
                onActionTap: hasAnyNotifications && _selectedFilter != 0
                    ? () => setState(() => _selectedFilter = 0)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(NotificationModel notification) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = Color(notification.getColorValue());
    final isRead = notification.isRead;
    final cardColor = isDark ? UserTheme.nightCard : UserTheme.dayCard;
    final surfaceColor = isDark ? UserTheme.nightSurface : UserTheme.daySurface;
    final titleColor = isDark
        ? (isRead ? UserTheme.nightTextSecondary : UserTheme.nightTextPrimary)
        : (isRead ? UserTheme.dayTextSecondary : UserTheme.dayTextPrimary);
    final bodyColor = isDark
        ? (isRead ? UserTheme.nightTextMuted : UserTheme.nightTextSecondary)
        : (isRead ? UserTheme.dayTextMuted : UserTheme.dayTextSecondary);

    final iconBg = isRead
        ? surfaceColor
        : accentColor.withValues(alpha: isDark ? 0.18 : 0.11);
    final iconFg = isRead
        ? (isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary)
        : accentColor;

    final cardContent = Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(UserTheme.radiusL),
        border: Border.all(
          color: isRead
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.05))
              : accentColor.withValues(alpha: isDark ? 0.35 : 0.24),
          width: isRead ? 1 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : (isRead ? 0.02 : 0.04)),
            blurRadius: isRead ? 8 : 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(UserTheme.radiusL),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _handleNotificationTap(notification),
            splashColor: accentColor.withValues(alpha: 0.08),
            highlightColor: accentColor.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      _getIcon(notification.getIconName()),
                      color: iconFg,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                notification.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                  color: titleColor,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              notification.getCompactTimestamp(),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                                color: isRead
                                    ? (isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted)
                                    : accentColor,
                              ),
                            ),
                            if (!isRead) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: accentColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          notification.message,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: bodyColor,
                          ),
                        ),
                        if (notification.trackingId != null &&
                            notification.trackingId!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: UserTheme.primaryOrange.withValues(alpha: isDark ? 0.14 : 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.qr_code_2_rounded,
                                  size: 13,
                                  color: UserTheme.primaryOrange,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  notification.trackingId!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: UserTheme.primaryOrange,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('notif_${notification.id.isNotEmpty ? notification.id : notification.timestamp.millisecondsSinceEpoch}'),
      direction: (isRead || notification.id.isEmpty)
          ? DismissDirection.none
          : DismissDirection.endToStart,
      confirmDismiss: (_) async {
        if (notification.id.isEmpty) return false;
        if (_selectedFilter == 1) {
          // Unread tab removes the item after the slide-out animation completes.
          return true;
        }
        // Let the card spring back before flipping its visual state to read.
        Future.delayed(const Duration(milliseconds: 220), () {
          if (mounted) {
            _databaseService.markNotificationAsRead(notification.id);
          }
        });
        return false;
      },
      onDismissed: (_) {
        if (notification.id.isNotEmpty) {
          _databaseService.markNotificationAsRead(notification.id);
        }
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: UserTheme.statusSuccess.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(UserTheme.radiusL),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_rounded, color: UserTheme.statusSuccess, size: 18),
            SizedBox(width: 6),
            Text(
              'Mark read',
              style: TextStyle(
                color: UserTheme.statusSuccess,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
      child: cardContent,
    );
  }

  IconData _getIcon(String name) {
    switch (name) {
      case 'qr_code_scanner':
        return Icons.qr_code_scanner_rounded;
      case 'check_circle':
        return Icons.verified_user_rounded;
      case 'cancel':
        return Icons.gpp_bad_rounded;
      case 'local_shipping':
        return Icons.local_shipping_rounded;
      case 'update':
        return Icons.sync_rounded;
      case 'inventory':
        return Icons.inventory_2_rounded;
      case 'check_box':
        return Icons.task_alt_rounded;
      case 'group':
        return Icons.group_rounded;
      default:
        return Icons.notifications_active_rounded;
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

    // 3. Pickup notifications -> Orders page (Index 1) > Outbound subpage (Index 2)
    // Checked before generic 'registered'/'status_update' rules so pickup alerts stay on Outbound.
    if (typeLower.contains('pickup') || titleLower.contains('pickup') || messageLower.contains('pickup')) {
      if (mounted) {
        Navigator.of(context).pop({'tabIndex': 1, 'subTabIndex': 2}); // Orders > Outbound tab
      }
      return;
    }

    // 4. Check for "Delivery Registered" -> Orders page (Index 1) > PENDING subpage (Index 0)
    if (titleLower.contains('registered') ||
        messageLower.contains('registered for drop off') ||
        typeLower == 'delivery' ||
        typeLower == 'status_update') {
      if (mounted) {
        Navigator.of(context).pop({'tabIndex': 1, 'subTabIndex': 0}); // Orders > Pending tab
      }
      return;
    }

    // 5. Check for "Parcel Retrieved" -> Orders page (Index 1) > RETRIEVED subpage (Index 3)
    if (titleLower.contains('retrieved') ||
        messageLower.contains('collected') ||
        typeLower == 'parcel_retrieved') {
      if (mounted) {
        Navigator.of(context).pop({'tabIndex': 1, 'subTabIndex': 3}); // Orders > Retrieved tab
      }
      return;
    }

    // 6. Access / Scan / Dropbox notifications -> Dropbox Control page (Index 2)
    if (mounted) {
      Navigator.of(context).pop({'tabIndex': 2}); // Dropbox Control tab
    }
  }
}
