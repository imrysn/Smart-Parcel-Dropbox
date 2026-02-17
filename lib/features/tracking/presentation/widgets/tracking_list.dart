import 'package:flutter/material.dart';
import '../../domain/entities/tracking.dart';
import 'tracking_card.dart';

/// Tracking list widget
/// 
/// Displays a list of tracking items
class TrackingList extends StatelessWidget {
  final List<Tracking> trackings;
  final void Function(Tracking)? onTrackingTap;

  const TrackingList({
    super.key,
    required this.trackings,
    this.onTrackingTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: trackings.length,
      itemBuilder: (context, index) {
        final tracking = trackings[index];
        return TrackingCard(
          key: ValueKey(tracking.trackingId),
          tracking: tracking,
          onTap: onTrackingTap != null ? () => onTrackingTap!(tracking) : null,
        );
      },
    );
  }
}
