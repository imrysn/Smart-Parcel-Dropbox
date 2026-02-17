import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/injection.dart';
import '../../domain/entities/tracking.dart';
import '../../domain/usecases/get_active_orders_usecase.dart';
import '../../domain/usecases/register_tracking_usecase.dart';
import '../../domain/usecases/get_tracking_by_id_usecase.dart';
import '../../domain/usecases/update_tracking_status_usecase.dart';

// ========== Use Case Providers ==========

final getActiveOrdersUseCaseProvider = Provider<GetActiveOrdersUseCase>(
  (ref) => getIt<GetActiveOrdersUseCase>(),
);

final registerTrackingUseCaseProvider = Provider<RegisterTrackingUseCase>(
  (ref) => getIt<RegisterTrackingUseCase>(),
);

final getTrackingByIdUseCaseProvider = Provider<GetTrackingByIdUseCase>(
  (ref) => getIt<GetTrackingByIdUseCase>(),
);

final updateTrackingStatusUseCaseProvider =
    Provider<UpdateTrackingStatusUseCase>(
  (ref) => getIt<UpdateTrackingStatusUseCase>(),
);

// ========== State Providers ==========

/// Provider for current user ID (will be replaced with auth provider)
final currentUserIdProvider = StateProvider<String?>((ref) => null);

/// Active orders stream provider
final activeOrdersProvider = StreamProvider.autoDispose<List<Tracking>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value([]);

  final useCase = ref.watch(getActiveOrdersUseCaseProvider);
  return useCase(userId).map((either) {
    return either.fold(
      (failure) {
        debugPrint('Error loading active orders: ${failure.message}');
        throw Exception(failure.message);
      },
      (trackings) => trackings,
    );
  });
});

/// Tracking by ID provider (family for different tracking IDs)
final trackingByIdProvider =
    FutureProvider.autoDispose.family<Tracking, String>((ref, trackingId) async {
  final useCase = ref.watch(getTrackingByIdUseCaseProvider);
  final result = await useCase(trackingId);

  return result.fold(
    (failure) => throw Exception(failure.message),
    (tracking) => tracking,
  );
});

// ========== State Notifier Providers ==========

/// Tracking registration state notifier
final trackingRegistrationProvider =
    StateNotifierProvider<TrackingRegistrationNotifier, AsyncValue<void>>(
  (ref) => TrackingRegistrationNotifier(
    ref.watch(registerTrackingUseCaseProvider),
  ),
);

class TrackingRegistrationNotifier extends StateNotifier<AsyncValue<void>> {
  final RegisterTrackingUseCase _registerUseCase;

  TrackingRegistrationNotifier(this._registerUseCase)
      : super(const AsyncValue.data(null));

  Future<void> registerTracking({
    required String userId,
    required String trackingId,
    required String shopName,
    String? expectedDeliveryDate,
  }) async {
    state = const AsyncValue.loading();

    final result = await _registerUseCase(
      userId: userId,
      trackingId: trackingId,
      shopName: shopName,
      expectedDeliveryDate: expectedDeliveryDate,
    );

    state = result.fold(
      (failure) => AsyncValue.error(failure.message, StackTrace.current),
      (_) => const AsyncValue.data(null),
    );
  }
}

/// Tracking status update notifier
final trackingStatusUpdateProvider =
    StateNotifierProvider<TrackingStatusUpdateNotifier, AsyncValue<void>>(
  (ref) => TrackingStatusUpdateNotifier(
    ref.watch(updateTrackingStatusUseCaseProvider),
  ),
);

class TrackingStatusUpdateNotifier extends StateNotifier<AsyncValue<void>> {
  final UpdateTrackingStatusUseCase _updateUseCase;

  TrackingStatusUpdateNotifier(this._updateUseCase)
      : super(const AsyncValue.data(null));

  Future<void> updateStatus({
    required String trackingId,
    required String status,
  }) async {
    state = const AsyncValue.loading();

    final result = await _updateUseCase(
      trackingId: trackingId,
      status: status,
    );

    state = result.fold(
      (failure) => AsyncValue.error(failure.message, StackTrace.current),
      (_) => const AsyncValue.data(null),
    );
  }
}
