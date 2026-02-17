import 'package:flutter/material.dart';
import '../../../../core/widgets/cards/base_card.dart';
import '../../../../core/widgets/misc/status_chip.dart';
import '../../domain/entities/tracking.dart';

/// Tracking card widget
/// 
/// Displays a tracking item in a card format with status chip
class TrackingCard extends StatelessWidget {
  final Tracking tracking;
  final VoidCallback? onTap;

  const TrackingCard({
    super.key,
    required this.tracking,
    this.onTap,
  });

  ChipType _getChipType(TrackingStatus status) {
    switch (status) {
      case TrackingStatus.pending:
        return ChipType.warning;
      case TrackingStatus.inTransit:
        return ChipType.info;
      case TrackingStatus.delivered:
        return ChipType.success;
      case TrackingStatus.retrieved:
        return ChipType.neutral;
    }
  }

  IconData _getStatusIcon(TrackingStatus status) {
    switch (status) {
      case TrackingStatus.pending:
        return Icons.schedule;
      case TrackingStatus.inTransit:
        return Icons.local_shipping;
      case TrackingStatus.delivered:
        return Icons.check_circle;
      case TrackingStatus.retrieved:
        return Icons.done_all;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  tracking.shopName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(
                label: tracking.status.displayName,
                type: _getChipType(tracking.status),
                icon: _getStatusIcon(tracking.status),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.qr_code_2, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                'Tracking ID: ${tracking.trackingId}',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (tracking.expectedDeliveryDate != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  'Expected: ${tracking.expectedDeliveryDate}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
          if (tracking.deliveredAt != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.green[600]),
                const SizedBox(width: 4),
                Text(
                  'Delivered: ${_formatDate(tracking.deliveredAt!)}',
                  style: TextStyle(
                    color: Colors.green[600],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
