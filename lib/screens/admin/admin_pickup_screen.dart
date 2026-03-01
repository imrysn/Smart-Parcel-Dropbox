import 'package:flutter/material.dart';

import '../../config/admin_theme.dart';
import '../../models/tracking_model.dart';
import '../../services/service_locator.dart';
import '../../services/tracking_service.dart';

/// Admin Pickup Screen - shows all pickup-mode tracking items across all users.
/// Displayed as the 4th tab inside the Admin Dashboard.
class PickupScreen extends StatefulWidget {
  final String userId;
  final bool isAdmin;

  const PickupScreen({
    super.key,
    required this.userId,
    // databaseService kept as optional named param for forward compatibility
    // ignore: avoid_unused_constructor_parameters
    databaseService,
    this.isAdmin = false,
  });

  @override
  State<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends State<PickupScreen> {
  late Stream<List<TrackingModel>> _pickupStream;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Use the centralised TrackingService stream; filter by mode in builder.
    _pickupStream = getIt<TrackingService>().trackingStream;
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await getIt<TrackingService>().refreshAllTracking();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final trackingService = getIt<TrackingService>();
    
    return StreamBuilder<List<TrackingModel>>(
      stream: _pickupStream,
      initialData: trackingService.cachedTracking,
      builder: (context, snapshot) {
        // Only show spinner if we absolutely have no data and are waiting
        if (snapshot.connectionState == ConnectionState.waiting &&
            (snapshot.data == null || snapshot.data!.isEmpty)) {
          return Center(
            child: CircularProgressIndicator(color: AdminTheme.primaryBlue),
          );
        }

        if (snapshot.hasError) {
          return _buildError('Error loading pickups: ${snapshot.error}');
        }

        // Filter to pickup-mode items only
        final allItems = snapshot.data ?? [];
        final pickups = allItems
            .where((t) => t.mode == 'pickup' || t.mode == 'pick_up')
            .toList();

        return RefreshIndicator(
          onRefresh: _refresh,
          color: AdminTheme.primaryBlue,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Stat row ──────────────────────────────────────────────
              _buildStatRow(pickups),
              const SizedBox(height: 24),

              // ── Section header ────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _buildSectionHeader(
                        'All Pickups', Icons.local_shipping_outlined),
                  ),
                  if (_refreshing)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      icon:
                          Icon(Icons.refresh, color: AdminTheme.primaryBlue),
                      tooltip: 'Refresh',
                      onPressed: _refresh,
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // ── List or empty state ───────────────────────────────────
              if (pickups.isEmpty)
                _buildEmpty()
              else
                ...pickups.map(_buildPickupCard),
            ],
          ),
        );
      },
    );
  }

  // ── Stat row ──────────────────────────────────────────────────────────────

  Widget _buildStatRow(List<TrackingModel> pickups) {
    final pending =
        pickups.where((t) => t.status == 'pending').length;
    final ready =
        pickups.where((t) => t.status == 'ready_for_pickup').length;
    final retrieved =
        pickups.where((t) => t.status == 'retrieved').length;

    return Row(
      children: [
        Expanded(
          child: _buildStat(
            icon: Icons.pending_actions,
            label: 'Pending',
            value: '$pending',
            color: AdminTheme.statusWarning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStat(
            icon: Icons.inventory_2_outlined,
            label: 'Ready',
            value: '$ready',
            color: const Color(0xFF6366F1),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStat(
            icon: Icons.done_all,
            label: 'Picked Up',
            value: '$retrieved',
            color: AdminTheme.statusSuccess,
          ),
        ),
      ],
    );
  }

  Widget _buildStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AdminTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Pickup card ───────────────────────────────────────────────────────────

  Widget _buildPickupCard(TrackingModel tracking) {
    final statusColor = _statusColor(tracking.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withOpacity(0.45),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tracking.shopName,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                // Status badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: statusColor.withOpacity(0.6)),
                  ),
                  child: Text(
                    tracking.getStatusText(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Details
            _infoRow(Icons.qr_code, 'Tracking ID', tracking.trackingId),
            const SizedBox(height: 6),
            _infoRow(Icons.person_outline, 'User ID', tracking.userId),
            if (tracking.registeredAt != null) ...[
              const SizedBox(height: 6),
              _infoRow(
                Icons.calendar_today,
                'Registered',
                _fmt(tracking.registeredAt!.toIso8601String()),
              ),
            ],
            if (tracking.retrievedAt != null) ...[
              const SizedBox(height: 6),
              _infoRow(
                Icons.done_all,
                'Picked Up At',
                _fmt(tracking.retrievedAt!.toIso8601String()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _statusColor(String status) {
    switch (status) {
      case 'ready_for_pickup':
        return const Color(0xFF6366F1);
      case 'retrieved':
        return AdminTheme.statusSuccess;
      default:
        return AdminTheme.statusWarning;
    }
  }

  String _fmt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}  '
          '${_pad(dt.hour)}:${_pad(dt.minute)}';
    } catch (_) {
      return iso;
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AdminTheme.primaryBlue, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: AdminTheme.textPrimary,
              ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AdminTheme.textMuted),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: AdminTheme.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: AdminTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(Icons.local_shipping_outlined,
                size: 64, color: AdminTheme.textMuted.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              'No Pickups Found',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AdminTheme.textMuted,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'No pickup-mode tracking items in the system',
              style: TextStyle(color: AdminTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: AdminTheme.statusError),
            const SizedBox(height: 12),
            Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: AdminTheme.statusError)),
          ],
        ),
      ),
    );
  }
}
