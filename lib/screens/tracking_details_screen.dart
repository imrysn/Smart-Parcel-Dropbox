import 'package:flutter/material.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../models/tracking_model.dart';
import '../services/database_service.dart';
import '../widgets/fade_animation.dart';

class TrackingDetailsScreen extends StatelessWidget {
  final TrackingModel tracking;

  const TrackingDetailsScreen({
    super.key,
    required this.tracking,
  });

  @override
  Widget build(BuildContext context) {
    final DatabaseService databaseService = DatabaseService();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: UserUi.pageBackground(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: UserTheme.appBarGradient(
          context: context,
          title: 'Parcel Details',
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Status Highlight Card ──
              _buildStatusHeader(context),
              const SizedBox(height: 24),

              // ── Tracking Info Card ──
              UserUi.sectionTitle(context, 'Logistic Data', subtitle: 'Detailed routing information'),
              const SizedBox(height: 12),
              UserUi.surfaceCard(
                context,
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildDetailRow(context, Icons.storefront_rounded, 'Vendor/Shop', tracking.shopName, UserTheme.primaryOrange),
                    const Divider(height: 32),
                    _buildDetailRow(context, Icons.qr_code_scanner_rounded, 'Tracking ID', tracking.trackingId, UserTheme.accentAmberDark),
                    if (tracking.expectedDeliveryDate != null) ...[
                      const Divider(height: 32),
                      _buildDetailRow(context, Icons.calendar_today_rounded, 'Estimate Arrival', tracking.expectedDeliveryDate!, UserTheme.sunsetEnd),
                    ],
                    if (tracking.registeredAt != null) ...[
                      const Divider(height: 32),
                      _buildDetailRow(context, Icons.history_rounded, 'First Entry', _formatDateTime(tracking.registeredAt!), UserTheme.primaryOrange),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ── Delivery Timeline ──
              UserUi.sectionTitle(context, 'Activity Log', subtitle: 'Live hardware events'),
              const SizedBox(height: 12),
              UserUi.surfaceCard(
                context,
                padding: const EdgeInsets.all(20),
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: databaseService.getDeliveryLogs(tracking.trackingId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
                    }

                    final logs = snapshot.data ?? [];
                    if (logs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text('No activity recorded yet.', style: TextStyle(color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted)),
                        ),
                      );
                    }

                    return Column(
                      children: logs.asMap().entries.map((entry) {
                        final isLast = entry.key == logs.length - 1;
                        return _buildTimelineItem(context, entry.value, isLast, entry.key);
                      }).toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = tracking.status == 'delivered' ? UserTheme.statusSuccess : (tracking.status == 'in_transit' ? UserTheme.accentAmberDark : UserTheme.primaryOrange);

    return UserUi.surfaceCard(
      context,
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(_getStatusIcon(tracking.status), size: 40, color: statusColor),
          ),
          const SizedBox(height: 20),
          Text(
            tracking.getStatusText().toUpperCase(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getStatusDescription(tracking.status),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, IconData icon, String label, String value, Color accent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: accent.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: accent, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineItem(BuildContext context, Map<String, dynamic> log, bool isLast, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final time = DateTime.parse(log['timestamp'].toString());

    return FadeAnimation(0.2 + (index * 0.15), IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12, height: 12,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(color: UserTheme.primaryOrange, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: UserTheme.primaryOrange.withOpacity(0.2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _getLogTitle(log['eventType']),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary),
                      ),
                      Text(
                        '${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: UserTheme.primaryOrange),
                      ),
                    ],
                  ),
                  if (log['details'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      log['details'],
                      style: TextStyle(fontSize: 13, color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${time.day} ${_getMonthName(time.month)} ${time.year}',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white24 : Colors.black26, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending': return Icons.hourglass_top_rounded;
      case 'in_transit': return Icons.local_shipping_rounded;
      case 'delivered': return Icons.inventory_2_rounded;
      case 'retrieved': return Icons.verified_rounded;
      default: return Icons.help_outline_rounded;
    }
  }

  String _getStatusDescription(String status) {
    switch (status) {
      case 'pending': return 'Your parcel is registered and waiting for courier drop-off.';
      case 'in_transit': return 'The package is currently moving through the distribution network.';
      case 'delivered': return 'Successfully deposited into your Smart Dropbox. Ready for collection.';
      case 'retrieved': return 'Parcel has been removed from the drop box and received by owner.';
      default: return 'Current status is being updated by the logistics provider.';
    }
  }

  String _getLogTitle(String eventType) {
    switch (eventType) {
      case 'scanned': return 'Logistics Scan';
      case 'door_opened': return 'Compartment Accessed';
      case 'parcel_inserted': return 'Parcel Deposited';
      case 'door_closed': return 'Security Lock Active';
      default: return eventType;
    }
  }

  String _formatDateTime(DateTime dt) => '${dt.day} ${_getMonthName(dt.month)} ${dt.year}, ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }
}
