import 'package:flutter/material.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../services/database_service.dart';
import '../models/tracking_model.dart';
import 'tracking_details_screen.dart';
import 'admin/rider_management_screen.dart';

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
  int _currentTab = 0; // 0 = Pickup, 1 = Riders

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: _buildToggleButton(),
            ),
            Expanded(
              child: _currentTab == 0
                  ? _buildPickupList()
                  : const RiderManagementScreen(isEmbedded: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return UserUi.glassCard(
      context,
      blur: 8,
      borderRadius: 16,
      padding: const EdgeInsets.all(4),
      color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
      child: Row(
        children: [
          _buildTabItem(0, 'PICKUP QUEUE', Icons.hourglass_empty_rounded),
          _buildTabItem(1, 'MANAGE RIDERS', Icons.motorcycle_rounded),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, String label, IconData icon) {
    final isSelected = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: isSelected ? UserTheme.sunsetGradient : null,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected ? [BoxShadow(color: UserTheme.primaryOrange.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? Colors.white : UserTheme.primaryOrange.withOpacity(0.5)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted),
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPickupList() {
    return RefreshIndicator(
      onRefresh: () => widget.databaseService.refreshTracking(widget.userId),
      color: UserTheme.primaryOrange,
      child: StreamBuilder<List<TrackingModel>>(
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

          final pickups = snapshot.data ?? [];

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
                    UserUi.statusPill(label: pickup.getStatusText().toUpperCase(), color: statusColor),
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
}
