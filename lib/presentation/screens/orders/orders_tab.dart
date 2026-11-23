import 'package:flutter/material.dart';
import '../../../config/user_theme.dart';
import '../../../models/tracking_model.dart';
import '../../../screens/add_pickup_screen.dart';
import '../../../screens/add_tracking_screen.dart';
import '../../../services/database_service.dart';
import '../../../widgets/user_ui.dart';
import '../../components/order_card.dart';

/// Orders Tab
///
/// Manages and filters incoming courier deliveries and outgoing customer pickups.
/// Supports dual-mode segment switching (DELIVERIES vs PICKUPS), status chips,
/// dynamic stream list, and smart sorting.
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

    return Column(
      children: [
        // ── Primary 2-Mode Segment Control (DELIVERIES vs PICKUPS) ──
        Padding(
          padding: UserUi.listPadding(context, top: 12, bottom: 6),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                _buildPrimaryModeItem(context, 0, 'DELIVERIES'),
                _buildPrimaryModeItem(context, 1, 'PICKUPS'),
              ],
            ),
          ),
        ),

        // ── Sub-Category Filters (Clean Text, No Icons) ──
        UserUi.responsiveContainer(
          context,
          maxWidth: 600,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: UserUi.horizontalGutter(context),
              vertical: 6,
            ),
            child: Row(
              children: ordersMode == 0
                  ? [
                      _buildFilterChip(
                        context,
                        'All',
                        0,
                        inboundFilterIndex,
                        onInboundFilterChanged,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        context,
                        'In Box',
                        1,
                        inboundFilterIndex,
                        onInboundFilterChanged,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        context,
                        'Pending',
                        2,
                        inboundFilterIndex,
                        onInboundFilterChanged,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        context,
                        'Retrieved',
                        3,
                        inboundFilterIndex,
                        onInboundFilterChanged,
                      ),
                    ]
                  : [
                      _buildFilterChip(
                        context,
                        'All',
                        0,
                        outboundFilterIndex,
                        onOutboundFilterChanged,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        context,
                        'Awaiting Pickup',
                        1,
                        outboundFilterIndex,
                        onOutboundFilterChanged,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        context,
                        'Completed',
                        2,
                        outboundFilterIndex,
                        onOutboundFilterChanged,
                      ),
                    ],
            ),
          ),
        ),

        const SizedBox(height: 4),

        // ── Dynamic List Stream ──
        Expanded(
          child: StreamBuilder<List<TrackingModel>>(
            stream: databaseService.getUserTrackingIds(userId),
            initialData: databaseService.cachedTracking,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return UserUi.emptyState(
                  context,
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load orders',
                  subtitle: 'Check your connection and pull down to refresh.',
                );
              }

              // Show shimmering skeletons while waiting for first data
              if (snapshot.connectionState == ConnectionState.waiting &&
                  (snapshot.data ?? []).isEmpty) {
                return UserUi.shimmerList(context, count: 5);
              }

              final allOrders = snapshot.data ?? [];
              List<TrackingModel> filtered;
              String emptyTitle;
              String emptySubtitle;
              IconData emptyIcon;
              String? emptyActionLabel;
              VoidCallback? emptyActionOnTap;

              if (ordersMode == 0) {
                // ─── INBOUND DELIVERIES ───
                final inboundOrders = allOrders
                    .where((o) => o.mode == 'drop_off' || o.mode.isEmpty)
                    .toList();

                if (inboundFilterIndex == 1) {
                  // In Box
                  filtered = inboundOrders
                      .where((o) => o.status == 'delivered')
                      .toList();
                  emptyTitle = 'No Parcels in Box';
                  emptySubtitle =
                      'When a courier delivers a parcel, it will be securely locked inside.';
                  emptyIcon = Icons.inbox_rounded;
                  emptyActionLabel = 'View Pending';
                  emptyActionOnTap = () => onInboundFilterChanged(2);
                } else if (inboundFilterIndex == 2) {
                  // Pending
                  filtered = inboundOrders
                      .where((o) =>
                          o.status == 'pending' || o.status == 'in_transit')
                      .toList();
                  emptyTitle = 'No Pending Parcels';
                  emptySubtitle =
                      'Parcels you register will appear here until they arrive at your Dropbox.';
                  emptyIcon = Icons.pending_actions_rounded;
                  emptyActionLabel = 'Add Tracking';
                  emptyActionOnTap = () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const AddTrackingScreen()),
                  );
                } else if (inboundFilterIndex == 3) {
                  // Retrieved
                  filtered = inboundOrders
                      .where((o) =>
                          o.status == 'retrieved' || o.status == 'done')
                      .toList();
                  emptyTitle = 'No Retrieval History';
                  emptySubtitle =
                      'Completed deliveries and collected parcels will be archived here.';
                  emptyIcon = Icons.history_rounded;
                } else {
                  // All Deliveries
                  filtered = inboundOrders;
                  emptyTitle = 'No Deliveries Found';
                  emptySubtitle =
                      'Register incoming tracking IDs to track your parcel deliveries.';
                  emptyIcon = Icons.inventory_2_outlined;
                  emptyActionLabel = 'Add Tracking';
                  emptyActionOnTap = () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const AddTrackingScreen()),
                  );
                }
              } else {
                // ─── PICKUPS ───
                final outboundOrders = allOrders
                    .where((o) => o.mode == 'pickup' || o.mode == 'pick_up')
                    .toList();

                if (outboundFilterIndex == 1) {
                  // Awaiting Pickup
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
                      .push(
                    MaterialPageRoute(
                        builder: (_) => const AddPickupScreen()),
                  )
                      .then((_) => databaseService.refreshTracking(userId));
                } else if (outboundFilterIndex == 2) {
                  // Completed
                  filtered = outboundOrders
                      .where((o) =>
                          o.status == 'retrieved' || o.status == 'done')
                      .toList();
                  emptyTitle = 'No Completed Pickups';
                  emptySubtitle =
                      'Parcels collected by riders from your Dropbox will be archived here.';
                  emptyIcon = Icons.history_rounded;
                } else {
                  // All Pickups
                  filtered = outboundOrders;
                  emptyTitle = 'No Pickups Scheduled';
                  emptySubtitle =
                      'Schedule couriers to pick up returns or outbound parcels from your Dropbox.';
                  emptyIcon = Icons.outbox_rounded;
                  emptyActionLabel = 'Schedule Pickup';
                  emptyActionOnTap = () => Navigator.of(context)
                      .push(
                    MaterialPageRoute(
                        builder: (_) => const AddPickupScreen()),
                  )
                      .then((_) => databaseService.refreshTracking(userId));
                }
              }

              // Smart Sorting: Newest & Most urgent first
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
                  return 2; // delivered, retrieved, done
                }

                int scoreA = getScore(a.status);
                int scoreB = getScore(b.status);
                if (scoreA != scoreB) return scoreA.compareTo(scoreB);

                final timeA = a.registeredAt ?? DateTime(2000);
                final timeB = b.registeredAt ?? DateTime(2000);
                return timeB.compareTo(timeA);
              });

              if (filtered.isEmpty) {
                return RefreshIndicator(
                  onRefresh: () => databaseService.refreshTracking(userId),
                  color: UserTheme.primaryOrange,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 40, bottom: 120),
                    child: UserUi.emptyState(
                      context,
                      icon: emptyIcon,
                      title: emptyTitle,
                      subtitle: emptySubtitle,
                      actionLabel: emptyActionLabel,
                      onActionTap: emptyActionOnTap,
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () => databaseService.refreshTracking(userId),
                color: UserTheme.primaryOrange,
                child: ListView.builder(
                  padding: UserUi.listPadding(context, top: 4, bottom: 120),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final order = filtered[index];
                    return OrderCard(
                      order: order,
                      onDelete: () => OrderCard.showDeleteConfirmationDialog(
                        context: context,
                        userId: userId,
                        databaseService: databaseService,
                        tracking: order,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryModeItem(BuildContext context, int index, String label) {
    final isSelected = ordersMode == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          onOrdersModeChanged(index);
          databaseService.refreshTracking(userId);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? UserTheme.primaryOrange : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: UserTheme.primaryOrange.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 0.6,
                color: isSelected
                    ? Colors.white
                    : (isDark
                        ? UserTheme.nightTextSecondary
                        : UserTheme.dayTextSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    BuildContext context,
    String label,
    int index,
    int selectedIndex,
    ValueChanged<int> onSelect, {
    IconData? icon,
  }) {
    final isSelected = selectedIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => onSelect(index),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white : UserTheme.dayTextPrimary)
              : (isDark ? UserTheme.nightCard : UserTheme.dayCard),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? (isDark ? Colors.white : UserTheme.dayTextPrimary)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06)),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: isSelected
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark
                        ? UserTheme.nightTextMuted
                        : UserTheme.dayTextMuted),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark
                        ? UserTheme.nightTextSecondary
                        : UserTheme.dayTextSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
