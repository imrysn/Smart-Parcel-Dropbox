import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/layouts/empty_state.dart';
import '../../../../core/widgets/layouts/error_view.dart';
import '../../../../core/widgets/indicators/shimmer_loader.dart';
import '../providers/tracking_provider.dart';
import '../widgets/tracking_list.dart';

/// Refactored Home Screen using Riverpod and new components
/// 
/// This demonstrates the new architecture:
/// - Riverpod for state management
/// - Repository pattern for data access
/// - Reusable components
/// - Clean separation of concerns
class HomeScreenRefactored extends ConsumerWidget {
  const HomeScreenRefactored({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeOrdersAsync = ref.watch(activeOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Parcel Drop Box'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              // TODO: Navigate to notifications
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              // TODO: Navigate to logs
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              // TODO: Implement logout
            },
          ),
        ],
      ),
      body: activeOrdersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const EmptyState(
              icon: Icons.inbox_outlined,
              title: 'No active orders',
              subtitle: 'Tap the button below to add a tracking ID',
            );
          }
          return TrackingList(
            trackings: orders,
            onTrackingTap: (tracking) {
              // TODO: Navigate to tracking details
              debugPrint('Tapped tracking: ${tracking.trackingId}');
            },
          );
        },
        loading: () => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: 5,
          itemBuilder: (context, index) => const TrackingCardShimmer(),
        ),
        error: (error, stack) => ErrorView(
          message: error.toString(),
          onRetry: () => ref.refresh(activeOrdersProvider),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: Navigate to add tracking screen
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Tracking ID'),
      ),
    );
  }
}
