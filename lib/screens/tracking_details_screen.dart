import 'package:flutter/material.dart';
import '../models/tracking_model.dart';
import '../services/database_service.dart';

/// Tracking Details Screen - Show detailed information about a parcel
class TrackingDetailsScreen extends StatelessWidget {
  final TrackingModel tracking;

  const TrackingDetailsScreen({
    super.key,
    required this.tracking,
  });

  @override
  Widget build(BuildContext context) {
    final DatabaseService databaseService = DatabaseService();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Tracking Details'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildStatusIcon(tracking.status),
                    const SizedBox(height: 16),
                    Text(
                      tracking.getStatusText(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getStatusMessage(tracking.status),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Parcel Information
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Parcel Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(
                      icon: Icons.store_outlined,
                      label: 'Shop/Platform',
                      value: tracking.shopName,
                    ),
                    const Divider(height: 24),
                    _buildInfoRow(
                      icon: Icons.qr_code_2,
                      label: 'Tracking ID',
                      value: tracking.trackingId,
                    ),
                    if (tracking.expectedDeliveryDate != null) ...[
                      const Divider(height: 24),
                      _buildInfoRow(
                        icon: Icons.calendar_today_outlined,
                        label: 'Expected Delivery',
                        value: tracking.expectedDeliveryDate!,
                      ),
                    ],
                    if (tracking.registeredAt != null) ...[
                      const Divider(height: 24),
                      _buildInfoRow(
                        icon: Icons.access_time,
                        label: 'Registered At',
                        value: _formatDateTime(tracking.registeredAt!),
                      ),
                    ],
                    if (tracking.deliveredAt != null) ...[
                      const Divider(height: 24),
                      _buildInfoRow(
                        icon: Icons.check_circle_outline,
                        label: 'Delivered At',
                        value: _formatDateTime(tracking.deliveredAt!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Delivery Logs
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Delivery Logs',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream:
                          databaseService.getDeliveryLogs(tracking.trackingId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        List<Map<String, dynamic>> logs = snapshot.data ?? [];

                        if (logs.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: Text(
                                'No delivery logs yet',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: logs.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 24),
                          itemBuilder: (context, index) {
                            Map<String, dynamic> log = logs[index];
                            return _buildLogItem(log);
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(String status) {
    IconData icon;
    Color color;

    switch (status) {
      case 'pending':
        icon = Icons.schedule;
        color = Colors.orange;
        break;
      case 'in_transit':
        icon = Icons.local_shipping_outlined;
        color = Colors.blue;
        break;
      case 'delivered':
        icon = Icons.inventory_2;
        color = Colors.green;
        break;
      case 'retrieved':
        icon = Icons.check_circle;
        color = Colors.grey;
        break;
      default:
        icon = Icons.help_outline;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 48,
        color: color,
      ),
    );
  }

  String _getStatusMessage(String status) {
    switch (status) {
      case 'pending':
        return 'Your parcel is registered and waiting for pickup';
      case 'in_transit':
        return 'Your parcel is on its way';
      case 'delivered':
        return 'Your parcel has been delivered to the drop box';
      case 'retrieved':
        return 'You have retrieved your parcel';
      default:
        return '';
    }
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _getLogIcon(log['eventType']),
          size: 20,
          color: Colors.grey[600],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getLogTitle(log['eventType']),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (log['details'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  log['details'],
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                _formatDateTime(DateTime.parse(log['timestamp'].toString())),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getLogIcon(String eventType) {
    switch (eventType) {
      case 'scanned':
        return Icons.qr_code_scanner;
      case 'door_opened':
        return Icons.lock_open;
      case 'parcel_inserted':
        return Icons.input;
      case 'door_closed':
        return Icons.lock;
      default:
        return Icons.circle;
    }
  }

  String _getLogTitle(String eventType) {
    switch (eventType) {
      case 'scanned':
        return 'Parcel Scanned';
      case 'door_opened':
        return 'Drop Box Opened';
      case 'parcel_inserted':
        return 'Parcel Inserted';
      case 'door_closed':
        return 'Drop Box Closed';
      default:
        return eventType;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
