import 'package:flutter/material.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../services/database_service.dart';
import '../models/tracking_model.dart';
import '../presentation/components/carrier_badge.dart';
import '../presentation/components/delivery_timeline.dart';
import 'tracking_details_screen.dart';
import 'owner_verify_screen.dart';
import 'add_pickup_screen.dart';

/// Pickup Screen - Manages items waiting to be picked up by couriers
class PickupScreen extends StatefulWidget {
  final String userId;
  final DatabaseService databaseService;

  const PickupScreen({
    super.key,
    required this.userId,
    required this.databaseService,
  });

  @override
  State<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends State<PickupScreen> {
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
                title: 'Pickups',
                centerTitle: false,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner_rounded, color: UserTheme.primaryOrange, size: 22),
                    tooltip: 'Verify Owner QR',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const OwnerVerifyScreen()),
                      );
                    },
                  ),
                ],
              )
            : null,
        body: SafeArea(
          child: _buildPickupList(),
        ),
      ),
    );
  }

  Widget _buildPickupList() {
    return RefreshIndicator(
      onRefresh: () => widget.databaseService.refreshTracking(widget.userId),
      color: UserTheme.primaryOrange,
      child: StreamBuilder<List<TrackingModel>>(
        initialData: widget.databaseService.cachedTracking
            .where((t) =>
                (t.mode == 'pickup' || t.mode == 'pick_up') &&
                ['pending', 'awaiting_pickup', 'ready_for_pickup', 'retrieved', 'done']
                    .contains(t.status))
            .toList(),
        stream: widget.databaseService.getActivePickups(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return UserUi.emptyState(
              context,
              icon: Icons.error_outline_rounded,
              title: 'Oops!',
              subtitle: 'Something went wrong while loading pickups.',
            );
          }

          final List<TrackingModel> pickups = snapshot.data ?? [];

          // Apply Smart Sorting
          pickups.sort((a, b) {
            // Priority Score: Lower is Higher (Top of list)
            int getScore(String status) {
              if (status == 'awaiting_pickup' || status == 'pending') return 0;
              if (status == 'ready_for_pickup') return 1;
              return 2; // retrieved, done
            }

            int scoreA = getScore(a.status);
            int scoreB = getScore(b.status);

            if (scoreA != scoreB) return scoreA.compareTo(scoreB);

            // Secondary Sort: Newest First
            final timeA = a.registeredAt ?? DateTime(2000);
            final timeB = b.registeredAt ?? DateTime(2000);
            return timeB.compareTo(timeA);
          });

          if (pickups.isEmpty) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 60, bottom: 120),
              child: UserUi.emptyState(
                context,
                icon: Icons.outbox_rounded,
                title: 'No Pickups Scheduled',
                subtitle: 'Parcels staged in your Dropbox for courier collection will appear here.',
                actionLabel: 'Schedule Pickup',
                onActionTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const AddPickupScreen()))
                    .then((_) => widget.databaseService.refreshTracking(widget.userId)),
              ),
            );
          }

          return ListView.builder(
            padding: UserUi.listPadding(context, top: 12, bottom: 120),
            itemCount: pickups.length,
            itemBuilder: (context, index) => _buildPickupCard(pickups[index]),
          );
        },
      ),
    );
  }

  int _pickupStage(String status) {
    if (status == 'ready_for_pickup') return 1;
    if (status == 'done' || status == 'retrieved') return 2;
    return 0;
  }

  Widget _buildPickupCard(TrackingModel pickup) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = UserTheme.getStatusColor(pickup.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: UserUi.surfaceCard(
        context,
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => TrackingDetailsScreen(tracking: pickup)),
            ),
            borderRadius: BorderRadius.circular(UserTheme.radiusL),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: CarrierBadge(shopName: pickup.shopName)),
                      const SizedBox(width: 8),
                      UserUi.statusPill(label: pickup.getStatusText(), color: statusColor),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                          size: 18,
                        ),
                        onPressed: () => _confirmDelete(pickup),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Delete Pickup',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          pickup.trackingId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      if (pickup.registeredAt != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(pickup.registeredAt),
                          style: TextStyle(
                            color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  DeliveryTimeline(
                    stageIndex: _pickupStage(pickup.status),
                    isPickup: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _confirmDelete(TrackingModel tracking) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Pickup?'),
        content: Text('Are you sure you want to remove ${tracking.shopName} (${tracking.trackingId}) from your list?\n\nThis action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();

              // 1. OPTIMISTIC UI FEEDBACK
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deleted ${tracking.trackingId}'),
                    backgroundColor: UserTheme.statusSuccess,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }

              // 2. ASYNC BACKGROUND SYNC
              try {
                await widget.databaseService.deleteTrackingId(
                  userId: widget.userId,
                  trackingId: tracking.trackingId,
                );
              } catch (e) {
                // 3. ROLLBACK / ERROR ALERT
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Network error. Delete failed: $e'),
                      backgroundColor: UserTheme.statusError,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: UserTheme.statusError,
              foregroundColor: Colors.white,
            ),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }
}
