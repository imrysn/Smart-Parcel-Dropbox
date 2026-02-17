import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/tracking_model.dart';
import '../models/scan_log_model.dart';
import '../models/notification_model.dart';
import '../models/user_model.dart';
import '../config/api_config.dart';

import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';

/// Database Service for Smart Parcel Drop Box System
/// Handles all Node.js API operations via MongoDB and WebSockets
class DatabaseService {
  static DatabaseService? _instance;

  factory DatabaseService() {
    _instance ??= DatabaseService._internal();
    return _instance!;
  }

  DatabaseService._internal();

  IO.Socket? _socket;
  final _trackingController = StreamController<List<TrackingModel>>.broadcast();
  final _notificationController =
      StreamController<List<NotificationModel>>.broadcast();
  final _doorStateController =
      StreamController<Map<String, dynamic>?>.broadcast();
  final _usersController = StreamController<List<UserModel>>.broadcast();

  // Cache last data to avoid "waiting" connection state on UI
  List<TrackingModel> _lastTrackingList = [];
  List<NotificationModel> _lastNotifications = [];
  Map<String, dynamic>? _lastDoorState;
  List<UserModel> _lastUsersList = [];
  bool _isFetchingUsers = false;
  bool _isFetchingTracking = false;

  // Getters for cached data
  List<TrackingModel> get cachedTracking => _lastTrackingList;
  List<NotificationModel> get cachedNotifications => _lastNotifications;
  Map<String, dynamic>? get cachedDoorState => _lastDoorState;

  void initSocket(String userId) {
    if (_socket != null) {
      if (_socket!.connected) {
        debugPrint('Socket already connected, joining room for $userId');
        _socket!.emit('join', userId);
        return;
      }
      _socket!.dispose();
    }

    _socket = IO.io(ApiConfig.baseUrl.replaceAll('/api', ''), <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    _socket!.onConnect((_) {
      debugPrint('Connected to WebSocket');
      _socket!.emit('join', userId);
    });

    _socket!.onDisconnect((_) => debugPrint('Disconnected from WebSocket'));
    _socket!
        .onConnectError((data) => debugPrint('WebSocket Connect Error: $data'));

    _socket!.on('trackingUpdate', (_) {
      debugPrint('Socket: trackingUpdate received');
      refreshTracking(userId);
    });

    _socket!.on('notificationNew', (data) {
      debugPrint('Socket: notificationNew received');
      refreshNotifications(userId);
    });

    _socket!.on('doorStateUpdate', (data) {
      debugPrint('Socket: doorStateUpdate received: $data');
      _lastDoorState = data;
      _doorStateController.add(data);
    });
  }

  void dispose() {
    _socket?.dispose();
    _trackingController.close();
    _notificationController.close();
    _doorStateController.close();
    _usersController.close();
  }

  /// Reset singleton instance (call on logout)
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }

  /// Register a new tracking ID for a user
  Future<void> registerTrackingId({
    required String userId,
    required String trackingId,
    required String shopName,
    String? expectedDeliveryDate,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.tracking),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'trackingId': trackingId,
          'userId': userId,
          'shopName': shopName,
          'expectedDeliveryDate': expectedDeliveryDate,
        }),
      );

      if (response.statusCode != 201) {
        final error = jsonDecode(response.body);
        throw error['message'] ?? 'Failed to register tracking ID';
      }

      // Success! Manually refresh tracking data immediately
      await refreshTracking(userId);
    } catch (e) {
      throw 'Failed to register tracking ID: $e';
    }
  }

  /// Refresh tracking data (called by socket or manually)
  Future<void> refreshTracking(String userId) async {
    try {
      final response =
          await http.get(Uri.parse('${ApiConfig.tracking}/user/$userId'));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        final list = data.map((json) => TrackingModel.fromMap(json)).toList();
        _lastTrackingList = list;
        _trackingController.add(list);
      }
    } catch (e) {
      debugPrint('Error refreshing tracking: $e');
    }
  }

  /// Get all tracking IDs for a specific user
  Stream<List<TrackingModel>> getUserTrackingIds(String userId) {
    // Only fetch if cache is empty, otherwise rely on WebSocket updates
    if (_lastTrackingList.isEmpty) {
      refreshTracking(userId);
    }
    return _trackingController.stream;
  }

  /// Get active orders (not retrieved yet)
  Stream<List<TrackingModel>> getActiveOrders(String userId) {
    return getUserTrackingIds(userId).map((list) => list
        .where((t) => ['pending', 'in_transit', 'delivered'].contains(t.status))
        .toList());
  }

  /// Verify tracking ID (used by courier/drop box system)
  Future<Map<String, dynamic>?> verifyTrackingId(String trackingId) async {
    try {
      final response =
          await http.get(Uri.parse('${ApiConfig.tracking}/$trackingId'));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      throw 'Failed to verify tracking ID: $e';
    }
  }

  /// Update tracking status
  Future<void> updateTrackingStatus({
    required String trackingId,
    required String status,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('${ApiConfig.tracking}/$trackingId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      );
      if (response.statusCode != 200) {
        throw 'Failed to update status';
      }
    } catch (e) {
      throw 'Failed to update tracking status: $e';
    }
  }

  /// Log delivery event
  Future<void> logDeliveryEvent({
    required String trackingId,
    required String userId,
    required String
        eventType, // scanned, door_opened, parcel_inserted, door_closed
    String? details,
  }) async {
    // Implement API call if needed, or simply skip if not critical
  }

  /// Get all delivery logs (Admin)
  Stream<List<Map<String, dynamic>>> getAllDeliveryLogs() {
    return Stream.fromFuture(_fetchAllDeliveryLogs()).asBroadcastStream();
  }

  Future<List<Map<String, dynamic>>> _fetchAllDeliveryLogs() async {
    try {
      final response =
          await http.get(Uri.parse('${ApiConfig.baseUrl}/delivery-logs'));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching all delivery logs: $e');
      return [];
    }
  }

  /// Get delivery logs for a tracking ID
  Stream<List<Map<String, dynamic>>> getDeliveryLogs(String trackingId) {
    return Stream.fromFuture(_fetchDeliveryLogs(trackingId))
        .asBroadcastStream();
  }

  Future<List<Map<String, dynamic>>> _fetchDeliveryLogs(
      String trackingId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/delivery-logs/$trackingId'));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching delivery logs: $e');
      return [];
    }
  }

  /// Check if user exists by email in MongoDB
  Future<bool> checkEmailExists(String email) async {
    try {
      final response =
          await http.get(Uri.parse('${ApiConfig.users}/check-email/$email'));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error checking email: $e');
      return false;
    }
  }

  /// Request password reset - sends code to email
  Future<void> requestPasswordReset(String email) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.users}/request-reset'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw error['message'] ?? 'Failed to request password reset';
      }
    } catch (e) {
      throw 'Failed to request password reset: $e';
    }
  }

  /// Verify reset code
  Future<bool> verifyResetCode(String email, String code) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.users}/verify-reset-code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'code': code}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['valid'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Error verifying reset code: $e');
      return false;
    }
  }

  /// Reset password with code
  Future<void> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.users}/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'code': code,
          'newPassword': newPassword,
        }),
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw error['message'] ?? 'Failed to reset password';
      }
    } catch (e) {
      throw 'Failed to reset password: $e';
    }
  }

  /// Get user data by MongoDB ID
  Future<Map<String, dynamic>?> getUserData(String userId) async {
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.users}/$userId'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        debugPrint('Failed to get user data: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error getting user data: $e');
      return null;
    }
  }

  /// Update user profile
  Future<void> updateUserProfile({
    required String userId,
    String? fullName,
    String? phoneNumber,
    String? address,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('${ApiConfig.users}/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (fullName != null) 'fullName': fullName,
          if (phoneNumber != null) 'phoneNumber': phoneNumber,
          if (address != null) 'address': address,
        }),
      );
      if (response.statusCode != 200) {
        throw 'Failed to update profile';
      }
    } catch (e) {
      throw 'Failed to update user profile: $e';
    }
  }

  /// Log a scan attempt
  Future<void> logScanAttempt({
    required String scannedCode,
    required bool accessGranted,
    String? trackingId,
    String? userId,
    String? reason,
  }) async {
    try {
      await http.post(
        Uri.parse(ApiConfig.scanLogs),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'scannedCode': scannedCode,
          'accessGranted': accessGranted,
          'trackingId': trackingId,
          'userId': userId,
          'reason': reason,
        }),
      );
    } catch (e) {
      debugPrint('Error logging scan: $e');
    }
  }

  /// Get all scan logs
  Stream<List<ScanLogModel>> getScanLogs() {
    return Stream.fromFuture(_fetchScanLogs()).asBroadcastStream();
  }

  Future<List<ScanLogModel>> _fetchScanLogs() async {
    try {
      final response = await http.get(Uri.parse(ApiConfig.scanLogs));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => ScanLogModel.fromMap(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching scan logs: $e');
      return [];
    }
  }

  /// Get scan logs for a specific user
  Stream<List<ScanLogModel>> getUserScanLogs(String userId) {
    return Stream.fromFuture(_fetchUserScanLogs(userId)).asBroadcastStream();
  }

  Future<List<ScanLogModel>> _fetchUserScanLogs(String userId) async {
    final response =
        await http.get(Uri.parse('${ApiConfig.scanLogs}/user/$userId'));
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((e) => ScanLogModel.fromMap(e)).toList();
    }
    return [];
  }

  /// Refresh notifications
  Future<void> refreshNotifications(String userId) async {
    try {
      final response =
          await http.get(Uri.parse('${ApiConfig.notifications}/user/$userId'));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        final list = data.map((e) => NotificationModel.fromMap(e)).toList();
        _lastNotifications = list;
        _notificationController.add(list);
      }
    } catch (e) {
      debugPrint('Error refreshing notifications: $e');
    }
  }

  /// Create a notification
  Future<void> createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    String? trackingId,
    Map<String, dynamic>? data,
  }) async {
    try {
      await http.post(
        Uri.parse(ApiConfig.notifications),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'type': type,
          'title': title,
          'message': message,
          'trackingId': trackingId,
          'data': data,
        }),
      );
    } catch (e) {
      debugPrint('Error creating notification: $e');
    }
  }

  /// Get notifications
  Stream<List<NotificationModel>> getUserNotifications(String userId) {
    if (_lastNotifications.isNotEmpty) {
      Timer.run(() => _notificationController.add(_lastNotifications));
    }
    refreshNotifications(userId);
    return _notificationController.stream;
  }

  /// Get unread count
  Stream<int> getUnreadNotificationsCount(String userId) {
    return getUserNotifications(userId)
        .map((list) => list.where((n) => !n.isRead).length);
  }

  /// Mark as read
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await http
          .patch(Uri.parse('${ApiConfig.notifications}/$notificationId/read'));
    } catch (e) {
      debugPrint('Error marking read: $e');
    }
  }

  /// Mark all read
  Future<void> markAllNotificationsAsRead(String userId) async {
    try {
      await http
          .patch(Uri.parse('${ApiConfig.notifications}/user/$userId/read'));
      refreshNotifications(userId);
    } catch (e) {
      debugPrint('Error marking all read: $e');
    }
  }

  /// Create notification when scan attempt happens
  Future<void> createScanAttemptNotification({
    required String userId,
    required String scannedCode,
    required bool accessGranted,
    String? trackingId,
    String? reason,
  }) async {
    String title;
    String message;
    String type;

    if (accessGranted) {
      type = 'access_granted';
      title = 'Access Granted';
      message = trackingId != null
          ? 'Access granted for tracking ID: $trackingId'
          : 'Access granted for code: $scannedCode';
    } else {
      type = 'access_denied';
      title = 'Access Denied';
      message = reason ?? 'Access denied for code: $scannedCode';
    }

    await createNotification(
      userId: userId,
      type: type,
      title: title,
      message: message,
      trackingId: trackingId,
      data: {
        'scannedCode': scannedCode,
        'accessGranted': accessGranted,
        'reason': reason,
      },
    );
  }

  /// Create notification when parcel is delivered
  Future<void> createDeliveryNotification({
    required String userId,
    required String trackingId,
    required String shopName,
  }) async {
    await createNotification(
      userId: userId,
      type: 'parcel_delivered',
      title: 'Parcel Delivered',
      message: 'Your parcel from $shopName has been delivered to the dropbox.',
      trackingId: trackingId,
      data: {
        'shopName': shopName,
      },
    );
  }

  /// Create notification when tracking status changes
  Future<void> createStatusUpdateNotification({
    required String userId,
    required String trackingId,
    required String status,
    required String shopName,
  }) async {
    String title = 'Status Updated';
    String message =
        'Your order from $shopName is now ${_getStatusText(status)}.';

    await createNotification(
      userId: userId,
      type: 'status_update',
      title: title,
      message: message,
      trackingId: trackingId,
      data: {
        'status': status,
        'shopName': shopName,
      },
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'in_transit':
        return 'In Transit';
      case 'delivered':
        return 'Delivered';
      case 'retrieved':
        return 'Retrieved';
      default:
        return status;
    }
  }

  /// Get all users
  Stream<List<UserModel>> getAllUsers() {
    // Seed stream with cached data immediately to prevent "waiting" state
    if (_lastUsersList.isNotEmpty) {
      _usersController.add(_lastUsersList);
    } else if (!_isFetchingUsers) {
      // Only fetch if not already fetching and cache is empty
      refreshAllUsers();
    }
    return _usersController.stream;
  }

  /// Refresh all users list
  Future<void> refreshAllUsers() async {
    if (_isFetchingUsers) return; // Prevent concurrent fetches
    _isFetchingUsers = true;
    try {
      final users = await _fetchAllUsers();
      _lastUsersList = users;
      _usersController.add(users);
    } finally {
      _isFetchingUsers = false;
    }
  }

  Future<List<UserModel>> _fetchAllUsers() async {
    try {
      final response = await http.get(Uri.parse(ApiConfig.users));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => UserModel.fromMap(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching all users: $e');
      return [];
    }
  }

  /// Update role
  Future<void> updateUserRole({
    required String userId,
    required String role,
  }) async {
    try {
      await http.patch(
        Uri.parse('${ApiConfig.users}/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'role': role}),
      );
    } catch (e) {
      debugPrint('Error updating role: $e');
    }
  }

  /// Get role
  Future<String?> getUserRole(String userId) async {
    final data = await getUserData(userId);
    return data?['role'];
  }

  /// Get all tracking
  Stream<List<TrackingModel>> getAllTrackingIds() {
    return Stream.fromFuture(_fetchAllTracking()).asBroadcastStream();
  }

  Future<List<TrackingModel>> _fetchAllTracking() async {
    try {
      final response = await http.get(Uri.parse(ApiConfig.tracking));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => TrackingModel.fromMap(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching all tracking: $e');
      return [];
    }
  }

  /// Refresh all tracking IDs list
  Future<void> refreshAllTrackingIds() async {
    if (_isFetchingTracking) return; // Prevent concurrent fetches
    _isFetchingTracking = true;
    try {
      final tracking = await _fetchAllTracking();
      _lastTrackingList = tracking;
      _trackingController.add(tracking);
    } finally {
      _isFetchingTracking = false;
    }
  }

  /// Control door
  Future<void> controlDropBoxDoor({
    required String userId,
    required bool open,
    String doorType = 'user', // 'parcel' or 'user'
  }) async {
    try {
      await http.post(
        Uri.parse(ApiConfig.deviceControl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'command': open ? 'open' : 'close',
          'doorType': doorType, // Specify which door to control
        }),
      );
    } catch (e) {
      debugPrint('Error controlling door: $e');
    }
  }

  /// Get door state
  Stream<Map<String, dynamic>?> getDropBoxDoorState() {
    if (_lastDoorState != null) {
      Timer.run(() => _doorStateController.add(_lastDoorState));
    }
    _fetchDoorState().then((data) {
      _lastDoorState = data;
      _doorStateController.add(data);
    });
    return _doorStateController.stream;
  }

  Future<Map<String, dynamic>?> _fetchDoorState() async {
    final response = await http.get(Uri.parse(ApiConfig.deviceControl));
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  /// Delete user
  Future<void> deleteUser(String userId) async {
    try {
      debugPrint('Deleting user: $userId');
      final response =
          await http.delete(Uri.parse('${ApiConfig.users}/$userId'));
      debugPrint('Delete user response: ${response.statusCode}');
      debugPrint('Delete user body: ${response.body}');

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception(
            'Failed to delete user: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Error deleting user: $e');
      rethrow; // Re-throw to let caller handle the error
    }
  }

  /// Get pending users (awaiting admin approval)
  Future<List<UserModel>> getPendingUsers() async {
    try {
      final response = await http.get(Uri.parse(ApiConfig.pendingUsers));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => UserModel.fromMap(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching pending users: $e');
      return [];
    }
  }

  /// Approve pending user
  Future<void> approveUser(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.approveUser}/$userId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to approve user: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error approving user: $e');
      rethrow;
    }
  }

  /// Reject pending user
  Future<void> rejectUser(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.rejectUser}/$userId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to reject user: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error rejecting user: $e');
      rethrow;
    }
  }
}
