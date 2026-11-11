import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../config/user_theme.dart';
import '../widgets/user_ui.dart';
import '../models/tracking_model.dart';
import '../services/database_service.dart';
import '../presentation/components/delivery_timeline.dart';
import '../presentation/components/carrier_badge.dart';

class TrackingDetailsScreen extends StatelessWidget {
  final TrackingModel tracking;

  const TrackingDetailsScreen({
    super.key,
    required this.tracking,
  });

  void _showFullscreenBarcodeModal(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? UserTheme.nightCard : UserTheme.dayCard,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              CarrierBadge(shopName: tracking.shopName, fontSize: 18),
              const SizedBox(height: 4),
              Text(
                tracking.trackingId,
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'monospace',
                  color: isDark ? UserTheme.nightTextSecondary : UserTheme.dayTextSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                ),
                child: QrImageView(
                  data: tracking.trackingId,
                  version: QrVersions.auto,
                  size: 210.0,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                ),
              ),
              const SizedBox(height: 24),
              UserUi.premiumButton(
                label: 'Copy Tracking ID',
                icon: Icons.copy_rounded,
                fontSize: 14,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: tracking.trackingId));
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Waybill tracking ID copied to clipboard!'),
                      backgroundColor: UserTheme.statusSuccess,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

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
              UserUi.sectionTitle(context, 'Parcel Information', subtitle: 'Waybill and delivery details'),
              const SizedBox(height: 12),
              UserUi.surfaceCard(
                context,
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildDetailRow(context, 'Merchant / Courier', CarrierBadge.resolveLabel(tracking.shopName)),
                    const Divider(height: 28),
                    _buildDetailRow(context, 'Tracking ID', tracking.trackingId, isMonospace: true),
                    if (tracking.expectedDeliveryDate != null) ...[
                      const Divider(height: 28),
                      _buildDetailRow(context, 'Estimated Arrival', tracking.expectedDeliveryDate!),
                    ],
                    if (tracking.registeredAt != null) ...[
                      const Divider(height: 28),
                      _buildDetailRow(context, 'Registered', _formatDateTime(tracking.registeredAt!)),
                    ],
                    const SizedBox(height: 20),
                    UserUi.premiumButton(
                      label: 'Show Barcode & QR Pass',
                      icon: Icons.qr_code_2_rounded,
                      fontSize: 14,
                      onTap: () => _showFullscreenBarcodeModal(context),
                    ),
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
                        return _buildTimelineItem(context, entry.value, isLast);
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
    final isPickup = tracking.mode == 'pickup' || tracking.mode == 'pick_up';
    final statusColor = UserTheme.getStatusColor(tracking.status);

    int stageIndex = 0;
    if (isPickup) {
      if (tracking.status == 'ready_for_pickup') {
        stageIndex = 1;
      } else if (tracking.status == 'done' || tracking.status == 'retrieved') {
        stageIndex = 2;
      }
    } else {
      if (tracking.status == 'in_transit') {
        stageIndex = 1;
      } else if (tracking.status == 'delivered') {
        stageIndex = 2;
      } else if (tracking.status == 'done' || tracking.status == 'retrieved') {
        stageIndex = 3;
      }
    }

    return UserUi.surfaceCard(
      context,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: CarrierBadge(shopName: tracking.shopName, fontSize: 16)),
              const SizedBox(width: 12),
              UserUi.statusPill(label: tracking.getStatusText(), color: statusColor),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            tracking.getStatusText(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _getStatusDescription(tracking.status),
            style: TextStyle(
              fontSize: 13.5,
              color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          DeliveryTimeline(stageIndex: stageIndex, isPickup: isPickup),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value, {
    bool isMonospace = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextSecondary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              fontFamily: isMonospace ? 'monospace' : null,
              color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineItem(BuildContext context, Map<String, dynamic> log, bool isLast) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rawTs = log['timestamp']?.toString() ?? '';
    final time = DateTime.tryParse(rawTs) ?? DateTime.now();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 4,
                height: 14,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: UserTheme.primaryOrange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: UserTheme.primaryOrange.withValues(alpha: 0.2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _getLogTitle(log['eventType']),
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: isDark ? UserTheme.nightTextPrimary : UserTheme.dayTextPrimary),
                      ),
                      Text(
                        '${time.hour}:${time.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: UserTheme.primaryOrange),
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
                    style: TextStyle(fontSize: 11.5, color: isDark ? UserTheme.nightTextMuted : UserTheme.dayTextMuted, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
