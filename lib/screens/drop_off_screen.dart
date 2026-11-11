import 'package:flutter/material.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../services/database_service.dart';
import '../models/tracking_model.dart';
import 'tracking_details_screen.dart';
import 'add_tracking_screen.dart';
import '../presentation/components/carrier_badge.dart';
import '../presentation/components/delivery_timeline.dart';

/// Drop Off screen for parcels in delivery flow.
class DropOffScreen extends StatelessWidget {
  final String userId;
  final DatabaseService databaseService;

  const DropOffScreen({
    super.key,
    required this.userId,
    required this.databaseService,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: canPop
            ? UserTheme.appBarGradient(
                context: context,
                title: 'Drop-off Orders',
                centerTitle: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: () => databaseService.refreshTracking(userId),
          color: UserTheme.primaryOrange,
          child: StreamBuilder<List<TrackingModel>>(
            stream: databaseService.getActiveOrders(userId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return UserUi.emptyState(
                  context,
                  icon: Icons.error_outline_rounded,
                  title: 'Oops!',
                  subtitle: 'Something went wrong while loading drop offs.',
                );
              }

              final orders = snapshot.data ?? [];
              if (orders.isEmpty) {
                return UserUi.emptyState(
                  context,
                  icon: Icons.inventory_2_outlined,
                  title: 'No drop offs',
                  subtitle: 'Incoming drop-off parcels will appear here.',
                  actionLabel: 'Add Tracking',
                  onActionTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddTrackingScreen()),
                  ),
                );
              }

              return ListView.builder(
                padding: UserUi.listPadding(context, top: 16, bottom: 120),
                itemCount: orders.length,
                itemBuilder: (context, index) => _DropOffCard(order: orders[index]),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DropOffCard extends StatelessWidget {
  final TrackingModel order;

  const _DropOffCard({required this.order});

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = UserTheme.getStatusColor(order.status);

    int stageIndex = 0;
    if (order.status == 'in_transit') stageIndex = 1;
    else if (order.status == 'delivered') stageIndex = 2;
    else if (order.status == 'done' || order.status == 'retrieved') stageIndex = 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: UserUi.surfaceCard(
        context,
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => TrackingDetailsScreen(tracking: order),
            ),
          ),
          borderRadius: BorderRadius.circular(UserTheme.radiusL),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: CarrierBadge(shopName: order.shopName)),
                    const SizedBox(width: 8),
                    UserUi.statusPill(
                      label: order.getStatusText(),
                      color: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.trackingId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? UserTheme.nightTextSecondary
                              : UserTheme.dayTextSecondary,
                        ),
                      ),
                    ),
                    if (order.registeredAt != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        _formatDate(order.registeredAt),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                DeliveryTimeline(stageIndex: stageIndex),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
