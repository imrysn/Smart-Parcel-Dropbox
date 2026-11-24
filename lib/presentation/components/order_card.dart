import 'package:flutter/material.dart';
import '../../config/user_theme.dart';
import '../../models/tracking_model.dart';
import '../../screens/tracking_details_screen.dart';
import '../../widgets/user_ui.dart';
import 'carrier_badge.dart';
import 'delivery_timeline.dart';

/// Reusable order card displaying carrier badge, status pill, tracking ID,
/// relative timestamp, and live delivery timeline.
class OrderCard extends StatelessWidget {
  final TrackingModel order;
  final bool showDelete;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  const OrderCard({
    super.key,
    required this.order,
    this.showDelete = true,
    this.onDelete,
    this.onTap,
  });

  /// Computes the active stage index and mode for [DeliveryTimeline].
  static ({int stageIndex, bool isPickup}) stageForOrder(TrackingModel order) {
    final isPickup = order.mode == 'pickup' || order.mode == 'pick_up';
    if (isPickup) {
      int stage = 0;
      if (order.status == 'ready_for_pickup') {
        stage = 1;
      } else if (order.status == 'done' || order.status == 'retrieved') {
        stage = 2;
      }
      return (stageIndex: stage, isPickup: true);
    }

    int stage = 0;
    if (order.status == 'in_transit') {
      stage = 1;
    } else if (order.status == 'delivered') {
      stage = 2;
    } else if (order.status == 'done' || order.status == 'retrieved') {
      stage = 3;
    }
    return (stageIndex: stage, isPickup: false);
  }

  /// Formats relative time string.
  static String timeAgo(DateTime? date) {
    if (date == null) return 'Unknown';
    final diff = DateTime.now().difference(date).abs();
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }

  /// Displays delete confirmation dialog and handles async deletion.
  static Future<void> showDeleteConfirmationDialog({
    required BuildContext context,
    required String userId,
    required dynamic databaseService,
    required TrackingModel tracking,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    return UserUi.showDashboardDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete tracking?'),
        scrollable: true,
        content: Text(
          'Are you sure you want to remove ${tracking.shopName} (${tracking.trackingId}) from your list?\n\nThis action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Deleted ${tracking.trackingId}'),
                  backgroundColor: UserTheme.statusSuccess,
                  duration: const Duration(seconds: 2),
                ),
              );

              try {
                await databaseService.deleteTrackingId(
                  userId: userId,
                  trackingId: tracking.trackingId,
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Network error. Delete failed: $e'),
                    backgroundColor: UserTheme.statusError,
                  ),
                );
              }
            },
            style:
                UserUi.dashboardFilledStyle(dialogContext, destructive: true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = UserUi.dashboardColors(context);
    final stage = stageForOrder(order);

    return UserUi.dashboardCard(
      context,
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: UserUi.dashboardSpacing),
      child: InkWell(
        onTap: onTap ??
            () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => TrackingDetailsScreen(tracking: order),
                ),
              );
            },
        borderRadius: BorderRadius.circular(UserUi.dashboardCardRadius),
        child: Padding(
          padding: const EdgeInsets.all(UserUi.dashboardSpacing),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: (stage.isPickup &&
                            order.customerName != null &&
                            order.customerName!.trim().isNotEmpty)
                        ? Text(
                            'To: ${order.customerName!.trim()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: colors.foreground,
                            ),
                          )
                        : CarrierBadge(shopName: order.shopName),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      order.getStatusText(),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: colors.foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  if (showDelete && onDelete != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: colors.secondary,
                        size: 18,
                      ),
                      onPressed: onDelete,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Delete Tracking',
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      (stage.isPickup &&
                              order.courierName != null &&
                              order.courierName!.trim().isNotEmpty)
                          ? '${order.courierName!.trim()} • ${order.trackingId}'
                          : order.trackingId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.secondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: (stage.isPickup &&
                                order.courierName != null &&
                                order.courierName!.trim().isNotEmpty)
                            ? null
                            : 'monospace',
                      ),
                    ),
                  ),
                  if (order.registeredAt != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      timeAgo(order.registeredAt),
                      style: TextStyle(
                        color: colors.secondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              DeliveryTimeline(
                stageIndex: stage.stageIndex,
                isPickup: stage.isPickup,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
