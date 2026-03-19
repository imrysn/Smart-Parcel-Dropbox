import 'package:flutter/material.dart';
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _buildToggleButton(),
          ),
          Expanded(
            child: _currentTab == 0
                ? _buildPickupList()
                : const RiderManagementScreen(isEmbedded: true),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentTab = 0),
              child: Container(
                decoration: BoxDecoration(
                  color: _currentTab == 0 ? Colors.orange.shade600 : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Pickup Queue',
                  style: TextStyle(
                    color: _currentTab == 0 ? Colors.white : Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentTab = 1),
              child: Container(
                decoration: BoxDecoration(
                  color: _currentTab == 1 ? Colors.orange.shade600 : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Manage Riders',
                  style: TextStyle(
                    color: _currentTab == 1 ? Colors.white : Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickupList() {
    return RefreshIndicator(
      onRefresh: () => widget.databaseService.refreshTracking(widget.userId),
      child: StreamBuilder<List<TrackingModel>>(
        stream: widget.isAdmin
            ? widget.databaseService.getAllTrackingIds().map((list) => list
                .where((t) =>
                    (t.mode == 'pickup' || t.mode == 'pick_up') &&
                    ['pending', 'awaiting_pickup', 'ready_for_pickup', 'retrieved', 'done']
                        .contains(t.status))
                .toList())
            : widget.databaseService.getActivePickups(widget.userId),
        initialData: widget.databaseService.cachedTracking
            .where((t) =>
                (t.mode == 'pickup' || t.mode == 'pick_up') &&
                (widget.isAdmin || t.userId == widget.userId) &&
                ['pending', 'awaiting_pickup', 'ready_for_pickup'].contains(t.status))
            .toList(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 60, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        widget.databaseService.refreshTracking(widget.userId),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final pickups = snapshot.data ?? [];

          if (pickups.isEmpty) {
            return Center(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.outbox_rounded,
                        size: 80,
                        color: Colors.deepPurple.shade300,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'No Pickups Yet',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'Scan a waybill QR code at the dropbox to register a pickup. Items will appear here automatically.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600], fontSize: 15),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.qr_code_scanner, color: Colors.deepPurple.shade300, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Use the box scanner to register',
                            style: TextStyle(color: Colors.deepPurple.shade400, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100),
            itemCount: pickups.length,
            itemBuilder: (context, index) {
              final pickup = pickups[index];
              return _buildPickupCard(pickup);
            },
          );
        },
      ),
    );
  }

  Widget _buildPickupCard(TrackingModel pickup) {
    final statusColor = _getStatusColor(pickup.status);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TrackingDetailsScreen(tracking: pickup),
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      pickup.shopName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      pickup.getStatusText(),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.tag, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    pickup.trackingId,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Registered: ${_formatDate(pickup.registeredAt)}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'awaiting_pickup':
        return Colors.indigo;
      case 'ready_for_pickup':
        return Colors.deepPurple;
      case 'pending':
        return Colors.orange;
      case 'retrieved':
        return Colors.grey;
      case 'done':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.month}/${date.day}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
