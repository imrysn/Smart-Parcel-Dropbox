import 'package:flutter/material.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../services/database_service.dart';
import '../models/tracking_model.dart';
import 'tracking_details_screen.dart';
import 'owner_verify_screen.dart';

/// Pickup Screen - Manages items waiting to be picked up by couriers
class PickupScreen extends StatefulWidget {
  final String userId;
  final DatabaseService databaseService;
  final bool isAdmin;

  const PickupScreen({
    super.key,
    required this.userId,
    required this.databaseService,
    this.isAdmin = false,
  });

  @override
  State<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends State<PickupScreen> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 80.0),
          child: FloatingActionButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const OwnerVerifyScreen(),
                ),
              );
            },
            heroTag: 'pickup_verify_fab',
            child: const Icon(Icons.qr_code_scanner),
          ),
        ),
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
        stream: widget.isAdmin
            ? widget.databaseService.getAllTrackingIds().map((list) => list
                .where((t) =>
                    (t.mode == 'pickup' || t.mode == 'pick_up') &&
                    ['pending', 'awaiting_pickup', 'ready_for_pickup', 'retrieved', 'done']
                        .contains(t.status))
                .toList())
            : widget.databaseService.getActivePickups(widget.userId),
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
            return UserUi.emptyState(
              context,
              icon: Icons.outbox_rounded,
              title: 'Empty queue',
              subtitle: 'Register a pickup at the dropbox to see it here.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 120),
            itemCount: pickups.length,
            itemBuilder: (context, index) => _buildPickupCard(pickups[index]),
          );
        },
      ),
    );
  }

  Widget _buildPickupCard(TrackingModel pickup) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _getStatusColor(pickup.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: UserUi.surfaceCard(
        context,
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => TrackingDetailsScreen(tracking: pickup)),
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
                        pickup.shopName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        UserUi.statusPill(label: pickup.getStatusText().toUpperCase(), color: statusColor),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded, 
                            color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                            size: 20,
                          ),
                          onPressed: () => _confirmDelete(pickup),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Delete Pickup',
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.tag_rounded, size: 14, color: UserTheme.primaryOrange),
                    const SizedBox(width: 8),
                    Text(
                      pickup.trackingId,
                      style: TextStyle(
                        color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded, size: 14, color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
                    const SizedBox(width: 8),
                    Text(
                      'Registered: ${_formatDate(pickup.registeredAt)}',
                      style: TextStyle(
                        color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'awaiting_pickup': return Colors.indigo;
      case 'ready_for_pickup': return Colors.deepPurple;
      case 'pending': return UserTheme.primaryOrange;
      case 'retrieved': return Colors.grey;
      case 'done': return UserTheme.statusSuccess;
      default: return Colors.grey;
    }
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
