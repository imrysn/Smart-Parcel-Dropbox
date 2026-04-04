import 'package:flutter/material.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../services/database_service.dart';
import '../models/tracking_model.dart';
import 'tracking_details_screen.dart';

/// Drop Off screen for parcels in delivery flow.
class DropOffScreen extends StatelessWidget {
  final String userId;
  final DatabaseService databaseService;
  final bool isAdmin;

  const DropOffScreen({
    super.key,
    required this.userId,
    required this.databaseService,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
          onRefresh: () async {
            if (isAdmin) {
              await databaseService.refreshAllTrackingIds();
            } else {
              await databaseService.refreshTracking(userId);
            }
          },
          color: UserTheme.primaryOrange,
          child: StreamBuilder<List<TrackingModel>>(
            stream: isAdmin
                ? databaseService.getAllTrackingIds().map(
                      (list) => list
                          .where(
                            (t) =>
                                t.mode == 'drop_off' &&
                                [
                                  'pending',
                                  'in_transit',
                                  'delivered',
                                  'awaiting_pickup',
                                  'done',
                                ].contains(t.status),
                          )
                          .toList(),
                    )
                : databaseService.getActiveOrders(userId),
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
                );
              }

              return ListView.builder(
                padding:
                    const EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 120),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = UserTheme.getStatusColor(order.status);

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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        order.shopName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? UserTheme.nightTextPrimary
                              : UserTheme.dayTextPrimary,
                        ),
                      ),
                    ),
                    UserUi.statusPill(
                      label: order.getStatusText(),
                      color: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.qr_code_2_rounded,
                      size: 14,
                      color: UserTheme.primaryOrange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        order.trackingId,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: isDark
                              ? UserTheme.nightTextSecondary
                              : UserTheme.dayTextSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
