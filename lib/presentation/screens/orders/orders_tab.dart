import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../config/user_theme.dart';
import '../../../models/tracking_model.dart';
import '../../../screens/add_pickup_screen.dart';
import '../../../screens/add_tracking_screen.dart';
import '../../../services/database_service.dart';
import '../../../widgets/user_ui.dart';
import '../../components/order_card.dart';

/// Orders Tab
///
/// Preserves the dedicated 2-mode segment control and sub-category filter layout,
/// with UI styling (buttons, chips, icons, and empty state) synchronized with the Home Tab.
class OrdersTab extends StatelessWidget {
  final String userId;
  final DatabaseService databaseService;
  final int ordersMode;
  final int inboundFilterIndex;
  final int outboundFilterIndex;
  final ValueChanged<int> onOrdersModeChanged;
  final ValueChanged<int> onInboundFilterChanged;
  final ValueChanged<int> onOutboundFilterChanged;

  const OrdersTab({
    super.key,
    required this.userId,
    required this.databaseService,
    required this.ordersMode,
    required this.inboundFilterIndex,
    required this.outboundFilterIndex,
    required this.onOrdersModeChanged,
    required this.onInboundFilterChanged,
    required this.onOutboundFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<List<TrackingModel>>(
      stream: databaseService.getUserTrackingIds(userId),
      initialData: databaseService.cachedTracking,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: UserUi.emptyState(
              context,
              icon: Icons.cloud_off_rounded,
              title: 'Could not load orders',
              subtitle: 'Check your connection and pull down to refresh.',
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            (snapshot.data ?? []).isEmpty) {
          return Padding(
            padding: UserUi.listPadding(context, top: 16, bottom: 120),
            child: UserUi.shimmerList(context, count: 5),
          );
        }

        final allOrders = snapshot.data ?? [];

        // Partition inbound deliveries vs outbound pickups
        final inboundOrders = allOrders
            .where((o) => o.mode == 'drop_off' || o.mode.isEmpty)
            .toList();
        final outboundOrders = allOrders
            .where((o) => o.mode == 'pickup' || o.mode == 'pick_up')
            .toList();

        // Compute counts for filter indicators
        final inBoxCount =
            inboundOrders.where((o) => o.status == 'delivered').length;
        final pendingCount = inboundOrders
            .where((o) => o.status == 'pending' || o.status == 'in_transit')
            .length;
        final retrievedCount = inboundOrders
            .where((o) => o.status == 'retrieved' || o.status == 'done')
            .length;

        final awaitingPickupCount = outboundOrders
            .where((o) =>
                o.status == 'awaiting_pickup' ||
                o.status == 'pending' ||
                o.status == 'ready_for_pickup')
            .length;
        final completedPickupCount = outboundOrders
            .where((o) => o.status == 'retrieved' || o.status == 'done')
            .length;

        List<TrackingModel> filtered;
        String emptyTitle;
        String emptySubtitle;
        IconData emptyIcon;
        String? emptyActionLabel;
        VoidCallback? emptyActionOnTap;

        if (ordersMode == 0) {
          // ─── INBOUND DELIVERIES ───
          if (inboundFilterIndex == 1) {
            filtered =
                inboundOrders.where((o) => o.status == 'delivered').toList();
            emptyTitle = 'No Parcels in Box';
            emptySubtitle =
                'When a courier delivers a parcel, it will be securely locked inside.';
            emptyIcon = Icons.inbox_rounded;
            emptyActionLabel = 'View Pending';
            emptyActionOnTap = () => onInboundFilterChanged(2);
          } else if (inboundFilterIndex == 2) {
            filtered = inboundOrders
                .where((o) => o.status == 'pending' || o.status == 'in_transit')
                .toList();
            emptyTitle = 'No Pending Parcels';
            emptySubtitle =
                'Parcels you register will appear here until they arrive at your Dropbox.';
            emptyIcon = Icons.pending_actions_rounded;
            emptyActionLabel = 'Add Tracking';
            emptyActionOnTap = () => Navigator.of(context)
                .push(MaterialPageRoute(
                    builder: (_) => const AddTrackingScreen()))
                .then((_) => databaseService.refreshTracking(userId));
          } else if (inboundFilterIndex == 3) {
            filtered = inboundOrders
                .where((o) => o.status == 'retrieved' || o.status == 'done')
                .toList();
            emptyTitle = 'No Retrieval History';
            emptySubtitle =
                'Completed deliveries and collected parcels will be archived here.';
            emptyIcon = Icons.history_rounded;
          } else {
            filtered = inboundOrders;
            emptyTitle = 'No Deliveries Found';
            emptySubtitle =
                'Register incoming tracking IDs to track your parcel deliveries.';
            emptyIcon = Icons.inventory_2_outlined;
            emptyActionLabel = 'Add Tracking';
            emptyActionOnTap = () => Navigator.of(context)
                .push(MaterialPageRoute(
                    builder: (_) => const AddTrackingScreen()))
                .then((_) => databaseService.refreshTracking(userId));
          }
        } else {
          // ─── OUTBOUND PICKUPS ───
          if (outboundFilterIndex == 1) {
            filtered = outboundOrders
                .where((o) =>
                    o.status == 'awaiting_pickup' ||
                    o.status == 'pending' ||
                    o.status == 'ready_for_pickup')
                .toList();
            emptyTitle = 'No Awaiting Pickups';
            emptySubtitle =
                'Parcels waiting in your Dropbox for courier collection will appear here.';
            emptyIcon = Icons.schedule_rounded;
            emptyActionLabel = 'Schedule Pickup';
            emptyActionOnTap = () => Navigator.of(context)
                .push(MaterialPageRoute(
                    builder: (_) => const AddPickupScreen()))
                .then((_) => databaseService.refreshTracking(userId));
          } else if (outboundFilterIndex == 2) {
            filtered = outboundOrders
                .where((o) => o.status == 'retrieved' || o.status == 'done')
                .toList();
            emptyTitle = 'No Completed Pickups';
            emptySubtitle =
                'Parcels collected by riders from your Dropbox will be archived here.';
            emptyIcon = Icons.history_rounded;
          } else {
            filtered = outboundOrders;
            emptyTitle = 'No Pickups Scheduled';
            emptySubtitle =
                'Schedule couriers to pick up returns or outbound parcels from your Dropbox.';
            emptyIcon = Icons.outbox_rounded;
            emptyActionLabel = 'Schedule Pickup';
            emptyActionOnTap = () => Navigator.of(context)
                .push(MaterialPageRoute(
                    builder: (_) => const AddPickupScreen()))
                .then((_) => databaseService.refreshTracking(userId));
          }
        }

        // Smart Priority Sorting: Active first, then newest
        filtered.sort((a, b) {
          int getScore(String status) {
            if (status == 'pending' ||
                status == 'in_transit' ||
                status == 'awaiting_pickup') {
              return 0;
            }
            if (status == 'ready_for_pickup' || status == 'delivered') {
              return 1;
            }
            return 2;
          }

          final scoreA = getScore(a.status);
          final scoreB = getScore(b.status);
          if (scoreA != scoreB) return scoreA.compareTo(scoreB);

          final timeA = a.registeredAt ?? DateTime(2000);
          final timeB = b.registeredAt ?? DateTime(2000);
          return timeB.compareTo(timeA);
        });

        return Column(
          children: [
            // ── Primary 2-Mode Segment Control (DELIVERIES vs PICKUPS) with Sliding Indicator Animation ──
            _buildSegmentedToggle(context, isDark),

            // ── Sub-Category Filters (Synced with Home Tab Styling & Orange Accent) ──
            UserUi.responsiveContainer(
              context,
              maxWidth: 600,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                  horizontal: UserUi.horizontalGutter(context),
                  vertical: 6,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<int>(ordersMode),
                    child: Row(
                      children: ordersMode == 0
                          ? [
                              _buildFilterChip(
                                context,
                                'All',
                                0,
                                inboundFilterIndex,
                                onInboundFilterChanged,
                                count: inboundOrders.length,
                              ),
                              const SizedBox(width: 8),
                              _buildFilterChip(
                                context,
                                'In Box',
                                1,
                                inboundFilterIndex,
                                onInboundFilterChanged,
                                count: inBoxCount,
                              ),
                              const SizedBox(width: 8),
                              _buildFilterChip(
                                context,
                                'Pending',
                                2,
                                inboundFilterIndex,
                                onInboundFilterChanged,
                                count: pendingCount,
                              ),
                              const SizedBox(width: 8),
                              _buildFilterChip(
                                context,
                                'Retrieved',
                                3,
                                inboundFilterIndex,
                                onInboundFilterChanged,
                                count: retrievedCount,
                              ),
                            ]
                          : [
                              _buildFilterChip(
                                context,
                                'All',
                                0,
                                outboundFilterIndex,
                                onOutboundFilterChanged,
                                count: outboundOrders.length,
                              ),
                              const SizedBox(width: 8),
                              _buildFilterChip(
                                context,
                                'Awaiting Pickup',
                                1,
                                outboundFilterIndex,
                                onOutboundFilterChanged,
                                count: awaitingPickupCount,
                              ),
                              const SizedBox(width: 8),
                              _buildFilterChip(
                                context,
                                'Completed',
                                2,
                                outboundFilterIndex,
                                onOutboundFilterChanged,
                                count: completedPickupCount,
                              ),
                            ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 4),

            // ── Dynamic List Stream & Empty State with Smooth Transitions ──
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => databaseService.refreshTracking(userId),
                color: UserTheme.primaryOrange,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: filtered.isEmpty
                      ? SingleChildScrollView(
                          key: ValueKey<String>('empty_${ordersMode}_${ordersMode == 0 ? inboundFilterIndex : outboundFilterIndex}'),
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(top: 50, bottom: 120),
                          child: _buildEmptyState(
                            context: context,
                            icon: emptyIcon,
                            title: emptyTitle,
                            subtitle: emptySubtitle,
                            actionLabel: emptyActionLabel,
                            onActionTap: emptyActionOnTap,
                            isDark: isDark,
                          ),
                        )
                      : ListView.builder(
                          key: ValueKey<String>('list_${ordersMode}_${ordersMode == 0 ? inboundFilterIndex : outboundFilterIndex}'),
                          padding:
                              UserUi.listPadding(context, top: 4, bottom: 120),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final order = filtered[index];
                            return OrderCard(
                              order: order,
                              onDelete: () =>
                                  OrderCard.showDeleteConfirmationDialog(
                                context: context,
                                userId: userId,
                                databaseService: databaseService,
                                tracking: order,
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Primary 2-Mode Segment Control with smooth sliding indicator animation
  Widget _buildSegmentedToggle(BuildContext context, bool isDark) {
    return Padding(
      padding: UserUi.listPadding(context, top: 12, bottom: 6),
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(UserTheme.radiusL),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Stack(
          children: [
            // Smooth Sliding Orange Indicator Capsule
            AnimatedAlign(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: ordersMode == 0
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Container(
                  decoration: BoxDecoration(
                    color: UserTheme.primaryOrange,
                    borderRadius: BorderRadius.circular(UserTheme.radiusM),
                    boxShadow: [
                      BoxShadow(
                        color: UserTheme.primaryOrange.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Interactive Tab Items with Icons & Labels
            Row(
              children: [
                _buildModeItem(
                  context,
                  0,
                  'DELIVERIES',
                  Icons.inventory_2_outlined,
                ),
                _buildModeItem(
                  context,
                  1,
                  'PICKUPS',
                  Icons.local_shipping_outlined,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Mode Item inside the Segmented Toggle with animated text & icon
  Widget _buildModeItem(
    BuildContext context,
    int index,
    String label,
    IconData icon,
  ) {
    final isSelected = ordersMode == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (ordersMode != index) {
              HapticFeedback.selectionClick();
              onOrdersModeChanged(index);
              databaseService.refreshTracking(userId);
            }
          },
          borderRadius: BorderRadius.circular(UserTheme.radiusM),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedTheme(
                  data: Theme.of(context),
                  child: Icon(
                    icon,
                    size: 16,
                    color: isSelected
                        ? Colors.white
                        : (isDark
                            ? UserTheme.nightTextSecondary
                            : UserTheme.dayTextSecondary),
                  ),
                ),
                const SizedBox(width: 7),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    letterSpacing: 0.5,
                    color: isSelected
                        ? Colors.white
                        : (isDark
                            ? UserTheme.nightTextSecondary
                            : UserTheme.dayTextSecondary),
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Refined filter chip: uses orange accent & soft glow (no jarring jet black)
  Widget _buildFilterChip(
    BuildContext context,
    String label,
    int index,
    int selectedIndex,
    ValueChanged<int> onSelect, {
    int? count,
  }) {
    final isSelected = selectedIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => onSelect(index),
      borderRadius: BorderRadius.circular(UserTheme.radiusM),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? UserTheme.primaryOrange
              : (isDark ? UserTheme.nightCard : UserTheme.dayCard),
          borderRadius: BorderRadius.circular(UserTheme.radiusM),
          border: Border.all(
            color: isSelected
                ? UserTheme.primaryOrange
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06)),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: UserTheme.primaryOrange.withValues(alpha: 0.28),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : (isDark
                        ? UserTheme.nightTextSecondary
                        : UserTheme.dayTextSecondary),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 5),
              Text(
                '($count)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.90)
                      : (isDark
                          ? UserTheme.nightTextMuted
                          : UserTheme.dayTextMuted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Vibrant Empty State: refined icon container with subtle glow & Home Tab style action button
  Widget _buildEmptyState({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onActionTap,
    required bool isDark,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: UserUi.horizontalGutter(context),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 50,
                color: UserTheme.primaryOrange,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? UserTheme.nightTextPrimary
                      : UserTheme.dayTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? UserTheme.nightTextSecondary
                      : UserTheme.dayTextSecondary,
                  height: 1.5,
                  fontSize: 13,
                ),
              ),
              if (actionLabel != null && onActionTap != null) ...[
                const SizedBox(height: 24),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onActionTap,
                    borderRadius: BorderRadius.circular(UserTheme.radiusL),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 13),
                      decoration: BoxDecoration(
                        color: UserTheme.primaryOrange,
                        borderRadius: BorderRadius.circular(UserTheme.radiusL),
                        boxShadow: [
                          BoxShadow(
                            color:
                                UserTheme.primaryOrange.withValues(alpha: 0.32),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            ordersMode == 0
                                ? Icons.add_box_outlined
                                : Icons.local_shipping_outlined,
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            actionLabel,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
