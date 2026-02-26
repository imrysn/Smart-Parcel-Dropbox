import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/tracking_model.dart';
import 'tracking_details_screen.dart';
import 'add_pickup_screen.dart';

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
    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: () => widget.databaseService.refreshTracking(widget.userId),
        child: StreamBuilder<List<TrackingModel>>(
          stream: widget.isAdmin
              ? widget.databaseService.getAllTrackingIds().map((list) => list
                  .where((t) =>
                      t.mode == 'pickup' &&
                      ['pending', 'ready_for_pickup', 'retrieved']
                          .contains(t.status))
                  .toList())
              : widget.databaseService.getActivePickups(widget.userId),
          initialData: widget.databaseService.cachedTracking
              .where((t) =>
                  t.mode == 'pickup' &&
                  (widget.isAdmin || t.userId == widget.userId) &&
                  ['pending', 'ready_for_pickup'].contains(t.status))
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
                        'No Pickups Registered',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Items you register for rider collection will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const AddPickupScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Register First Pickup'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: pickups.length,
              itemBuilder: (context, index) {
                final pickup = pickups[index];
                return _buildPickupCard(pickup);
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const AddPickupScreen(),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add Pickup'),
        heroTag: 'pickup_fab',
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
      case 'pending':
        return Colors.orange;
      case 'ready_for_pickup':
        return Colors.deepPurple;
      case 'retrieved':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.month}/${date.day}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
