import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/tracking_model.dart';
import '../models/scan_log_model.dart';
import '../models/notification_model.dart';
import '../models/user_model.dart';
import 'service_locator.dart';
import 'websocket_service.dart';
import 'tracking_service.dart';
import 'user_service.dart';
import 'scan_log_service.dart';
import 'device_control_service.dart';
import 'notification_service.dart';

/// Database Service - FACADE for backward compatibility
///
/// ⚠️ DEPRECATED: This class is maintained only for backward compatibility
/// during the migration to SRP-compliant services.
///
/// New code should use the individual services directly:
/// - WebSocketService
/// - TrackingService
/// - UserService
/// - ScanLogService
/// - DeviceControlService
/// - NotificationService
@deprecated
class DatabaseService {
  static DatabaseService? _instance;

  factory DatabaseService() {
    _instance ??= DatabaseService._internal();
    return _instance!;
  }

  DatabaseService._internal() {
    debugPrint(
        '⚠️ DatabaseService (facade) initialized - consider migrating to new services');
  }

  // Lazy getters for new services
  WebSocketService get _ws => getIt<WebSocketService>();
  TrackingService get _tracking => getIt<TrackingService>();
  UserService get _user => getIt<UserService>();
  ScanLogService get _scanLog => getIt<ScanLogService>();
  DeviceControlService get _device => getIt<DeviceControlService>();
  NotificationService get _notification => getIt<NotificationService>();

  // ========== WebSocket Methods ==========

  void initSocket(String userId) {
    _ws.connect(userId);

    // Wire up WebSocket events to services
    _ws.trackingUpdates.listen((_) => _tracking.refreshTracking(userId));
    _ws.notificationUpdates
        .listen((_) => _notification.refreshNotifications(userId));
    _ws.doorStateUpdates.listen((state) => _device.updateDoorState(state));

    // ── Phase 4: Hardware delivery events ──────────────────────────────────
    // Fired by backend when ESP32 emits statusUpdate after a drop-off/pick-up.
    // Payload: { trackingId, status, mode, timestamp }
    _ws.trackingStatusChanges.listen((data) {
      debugPrint('Socket: trackingStatusChanged received: $data');

      final trackingId = (data['trackingId'] ?? '').toString();
      final status = (data['status'] ?? '').toString();

      // 1. Refresh the tracking list so the home screen updates immediately
      _tracking.refreshTracking(userId);

      // 2. Show a local system tray/push notification
      _notification.showDeliveryNotification(
        trackingId: trackingId,
        status: status,
      );
    });
  }

  void dispose() {
    _ws.disconnect();
  }

  static void reset() {
    WebSocketService.reset();
    TrackingService.reset();
    UserService.reset();
    ScanLogService.reset();
    DeviceControlService.reset();
    NotificationService.reset();
    _instance = null;
  }

  // ========== Tracking Methods ==========

  Future<void> registerTrackingId({
    required String userId,
    required String trackingId,
    required String shopName,
    String? expectedDeliveryDate,
  }) =>
      _tracking.registerTrackingId(
        userId: userId,
        trackingId: trackingId,
        shopName: shopName,
        expectedDeliveryDate: expectedDeliveryDate,
      );

  Future<void> refreshTracking(String userId) =>
      _tracking.refreshTracking(userId);

  Stream<List<TrackingModel>> getUserTrackingIds(String userId) =>
      _tracking.getUserTrackingIds(userId);

  Stream<List<TrackingModel>> getActiveOrders(String userId) =>
      _tracking.getActiveOrders(userId);

  Future<Map<String, dynamic>?> verifyTrackingId(String trackingId) =>
      _tracking.verifyTrackingId(trackingId);

  Future<void> updateTrackingStatus({
    required String trackingId,
    required String status,
  }) =>
      _tracking.updateTrackingStatus(trackingId: trackingId, status: status);

  Stream<List<TrackingModel>> getAllTrackingIds() =>
      Stream.fromFuture(_tracking.getAllTrackingIds());

  Future<void> refreshAllTrackingIds() async {
    // Not needed with new architecture
  }

  List<TrackingModel> get cachedTracking => _tracking.cachedTracking;

  // ========== User Methods ==========

  Future<Map<String, dynamic>?> getUserData(String userId) =>
      _user.getUserData(userId);

  Future<void> updateUserProfile({
    required String userId,
    String? fullName,
    String? phoneNumber,
    String? address,
  }) =>
      _user.updateUserProfile(
        userId: userId,
        fullName: fullName,
        phoneNumber: phoneNumber,
        address: address,
      );

  Stream<List<UserModel>> getAllUsers() => _user.getAllUsers();

  Future<void> refreshAllUsers() => _user.refreshAllUsers();

  Future<void> updateUserRole({
    required String userId,
    required String role,
  }) =>
      _user.updateUserRole(userId: userId, role: role);

  Future<String?> getUserRole(String userId) => _user.getUserRole(userId);

  Future<void> deleteUser(String userId) => _user.deleteUser(userId);

  Future<List<UserModel>> getPendingUsers() => _user.getPendingUsers();

  Future<void> approveUser(String userId) => _user.approveUser(userId);

  Future<void> rejectUser(String userId) => _user.rejectUser(userId);

  Future<bool> checkEmailExists(String email) => _user.checkEmailExists(email);

  Future<void> requestPasswordReset(String email) =>
      _user.requestPasswordReset(email);

  Future<bool> verifyResetCode(String email, String code) =>
      _user.verifyResetCode(email, code);

  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) =>
      _user.resetPasswordWithCode(
        email: email,
        code: code,
        newPassword: newPassword,
      );

  // ========== Scan Log Methods ==========

  Future<void> logScanAttempt({
    required String scannedCode,
    required bool accessGranted,
    String? trackingId,
    String? userId,
    String? reason,
  }) =>
      _scanLog.logScanAttempt(
        scannedCode: scannedCode,
        accessGranted: accessGranted,
        trackingId: trackingId,
        userId: userId,
        reason: reason,
      );

  Stream<List<ScanLogModel>> getScanLogs() =>
      Stream.fromFuture(_scanLog.getScanLogs());

  Stream<List<ScanLogModel>> getUserScanLogs(String userId) =>
      Stream.fromFuture(_scanLog.getUserScanLogs(userId));

  Stream<List<Map<String, dynamic>>> getAllDeliveryLogs() =>
      Stream.fromFuture(_scanLog.getAllDeliveryLogs());

  Stream<List<Map<String, dynamic>>> getDeliveryLogs(String trackingId) =>
      Stream.fromFuture(_scanLog.getDeliveryLogs(trackingId));

  Future<void> logDeliveryEvent({
    required String trackingId,
    required String userId,
    required String eventType,
    String? details,
  }) async {
    // Not implemented in new architecture
  }

  // ========== Device Control Methods ==========

  Future<void> controlDropBoxDoor({
    required String userId,
    required bool open,
    String doorType = 'user',
  }) =>
      _device.controlDropBoxDoor(
        userId: userId,
        open: open,
        doorType: doorType,
      );

  Stream<Map<String, dynamic>?> getDropBoxDoorState() =>
      _device.getDropBoxDoorState();

  Map<String, dynamic>? get cachedDoorState => _device.cachedDoorState;

  // ========== Notification Methods ==========

  Future<void> refreshNotifications(String userId) =>
      _notification.refreshNotifications(userId);

  Future<void> createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    String? trackingId,
    Map<String, dynamic>? data,
  }) =>
      _notification.createNotification(
        userId: userId,
        type: type,
        title: title,
        message: message,
        trackingId: trackingId,
        data: data,
      );

  Stream<List<NotificationModel>> getUserNotifications(String userId) =>
      _notification.getUserNotifications(userId);

  Stream<int> getUnreadNotificationsCount(String userId) =>
      _notification.getUnreadNotificationsCount(userId);

  Future<void> markNotificationAsRead(String notificationId) =>
      _notification.markNotificationAsRead(notificationId);

  Future<void> markAllNotificationsAsRead(String userId) =>
      _notification.markAllNotificationsAsRead(userId);

  Future<void> createScanAttemptNotification({
    required String userId,
    required String scannedCode,
    required bool accessGranted,
    String? trackingId,
    String? reason,
  }) =>
      _notification.createScanAttemptNotification(
        userId: userId,
        scannedCode: scannedCode,
        accessGranted: accessGranted,
        trackingId: trackingId,
        reason: reason,
      );

  Future<void> createDeliveryNotification({
    required String userId,
    required String trackingId,
    required String shopName,
  }) =>
      _notification.createDeliveryNotification(
        userId: userId,
        trackingId: trackingId,
        shopName: shopName,
      );

  Future<void> createStatusUpdateNotification({
    required String userId,
    required String trackingId,
    required String status,
    required String shopName,
  }) =>
      _notification.createStatusUpdateNotification(
        userId: userId,
        trackingId: trackingId,
        status: status,
        shopName: shopName,
      );

  List<NotificationModel> get cachedNotifications =>
      _notification.cachedNotifications;
}
