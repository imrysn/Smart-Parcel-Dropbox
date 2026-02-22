import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';
import '../config/api_config.dart';

/// WebSocket Service - Handles real-time communication with backend
///
/// Single Responsibility: Manage WebSocket connections and event handling
class WebSocketService {
  static WebSocketService? _instance;

  factory WebSocketService() {
    _instance ??= WebSocketService._internal();
    return _instance!;
  }

  WebSocketService._internal();

  IO.Socket? _socket;
  String? _currentUserId;

  // Event stream controllers
  final _trackingUpdateController = StreamController<void>.broadcast();
  final _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _doorStateController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Public streams
  Stream<void> get trackingUpdates => _trackingUpdateController.stream;
  Stream<Map<String, dynamic>> get notificationUpdates =>
      _notificationController.stream;
  Stream<Map<String, dynamic>> get doorStateUpdates =>
      _doorStateController.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// Initialize WebSocket connection for a user
  void connect(String userId) {
    if (_socket != null) {
      if (_socket!.connected) {
        debugPrint('WebSocket already connected, joining room for $userId');
        _socket!.emit('join', userId);
        _currentUserId = userId;
        return;
      }
      _socket!.dispose();
    }

    _currentUserId = userId;

    _socket = IO.io(
      ApiConfig.baseUrl.replaceAll('/api', ''),
      <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
      },
    );

    _setupEventHandlers(userId);
  }

  /// Setup event handlers for WebSocket
  void _setupEventHandlers(String userId) {
    _socket!.onConnect((_) {
      debugPrint('✅ WebSocket connected');
      _socket!.emit('join', userId);
    });

    _socket!.onDisconnect((_) {
      debugPrint('❌ WebSocket disconnected');
    });

    _socket!.onConnectError((data) {
      debugPrint('⚠️ WebSocket connection error: $data');
    });

    // Tracking updates
    _socket!.on('trackingUpdate', (_) {
      debugPrint('📦 Tracking update received');
      _trackingUpdateController.add(null);
    });

    // Notification updates
    _socket!.on('notificationNew', (data) {
      debugPrint('🔔 New notification received');
      _notificationController.add(data as Map<String, dynamic>);
    });

    // Door state updates
    _socket!.on('doorStateUpdate', (data) {
      debugPrint('🚪 Door state update: $data');
      _doorStateController.add(data as Map<String, dynamic>);
    });
  }

  /// Emit an event to the server
  void emit(String event, dynamic data) {
    if (_socket?.connected ?? false) {
      _socket!.emit(event, data);
    } else {
      debugPrint('⚠️ Cannot emit event: WebSocket not connected');
    }
  }

  /// Disconnect and cleanup
  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _currentUserId = null;
    debugPrint('🔌 WebSocket disconnected and cleaned up');
  }

  /// Dispose all resources
  void dispose() {
    disconnect();
    _trackingUpdateController.close();
    _notificationController.close();
    _doorStateController.close();
  }

  /// Reset singleton instance
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
