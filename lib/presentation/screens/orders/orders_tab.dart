import 'package:flutter/material.dart';
import '../../../models/tracking_model.dart';
import '../../../screens/add_pickup_screen.dart';
import '../../../screens/add_tracking_screen.dart';
import '../../../services/database_service.dart';
import '../../../widgets/user_ui.dart';
import '../../components/order_card.dart';

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
    final actionColor = UserUi.dashboardColors(context).foreground;

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
              subtitle: 'Check your connection and try again.',
              actionLabel: 'Retry',
              onActionTap: () => databaseService.refreshTracking(userId),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            (snapshot.data ?? []).isEmpty) {
          return Padding(
            padding: UserUi.listPadding(context, top: 12, bottom: 120),
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
                .push(
                    MaterialPageRoute(builder: (_) => const AddPickupScreen()))
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
                .push(
                    MaterialPageRoute(builder: (_) => const AddPickupScreen()))
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

        final (filters, selectedFilter, onFilterChanged) = ordersMode == 0
            ? (
                [
                  ('All', inboundOrders.length),
                  ('In Box', inBoxCount),
                  ('Pending', pendingCount),
                  ('Retrieved', retrievedCount),
                ],
                inboundFilterIndex,
                onInboundFilterChanged,
              )
            : (
                [
                  ('All', outboundOrders.length),
                  ('Awaiting Pickup', awaitingPickupCount),
                  ('Completed', completedPickupCount),
                ],
                outboundFilterIndex,
                onOutboundFilterChanged,
              );

        final contentKey = (ordersMode, selectedFilter, filtered.isEmpty);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildModeSelector(context),
            Padding(
              padding: UserUi.listPadding(
                context,
                top: 4,
                bottom: UserUi.dashboardSpacing,
              ),
              child: Wrap(
                spacing: UserUi.sS,
                children: [
                  for (final (index, (label, count)) in filters.indexed)
                    UserUi.dashboardFilterChip(
                      context,
                      label: '$label ($count)',
                      selected: selectedFilter == index,
                      onSelected: (_) => onFilterChanged(index),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => databaseService.refreshTracking(userId),
                color: actionColor,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: filtered.isEmpty
                      ? SingleChildScrollView(
                          key: ValueKey(contentKey),
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding:
                              UserUi.listPadding(context, top: 16, bottom: 120),
                          child: UserUi.emptyState(
                            context,
                            icon: emptyIcon,
                            title: emptyTitle,
                            subtitle: emptySubtitle,
                            actionLabel: emptyActionLabel,
                            onActionTap: emptyActionOnTap,
                          ),
                        )
                      : ListView.builder(
                          key: ValueKey(contentKey),
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

  Widget _buildModeSelector(BuildContext context) {
    final colors = UserUi.dashboardColors(context);

    return Padding(
      padding: UserUi.listPadding(context, top: 12, bottom: 4),
      child: SegmentedButton<int>(
        expandedInsets: EdgeInsets.zero,
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          foregroundColor: colors.foreground,
          backgroundColor: colors.surface,
          selectedForegroundColor: colors.surface,
          selectedBackgroundColor: colors.foreground,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(UserUi.dashboardControlRadius),
          ),
          tapTargetSize: MaterialTapTargetSize.padded,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        segments: const [
          ButtonSegment(
            value: 0,
            label: Text('Deliveries', textAlign: TextAlign.center),
          ),
          ButtonSegment(
            value: 1,
            label: Text('Pickups', textAlign: TextAlign.center),
          ),
        ],
        selected: {ordersMode},
        onSelectionChanged: (selection) {
          onOrdersModeChanged(selection.single);
          databaseService.refreshTracking(userId);
        },
      ),
    );
  }
}
