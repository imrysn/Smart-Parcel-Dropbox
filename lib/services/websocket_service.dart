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
  final _trackingStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _esp32StatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _binStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _ownerVerifyAckController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _ownerAccessAlertController =
      StreamController<Map<String, dynamic>>.broadcast();
  // Device registration streams
  final _deviceRegisteredController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _deviceRegistrationFailedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _hardwareConfigAppliedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _deviceUnregisteredController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Public streams
  Stream<void> get trackingUpdates => _trackingUpdateController.stream;
  Stream<Map<String, dynamic>> get notificationUpdates =>
      _notificationController.stream;
  Stream<Map<String, dynamic>> get doorStateUpdates =>
      _doorStateController.stream;
  Stream<Map<String, dynamic>> get trackingStatusChanges =>
      _trackingStatusController.stream;
  /// Fires whenever ESP32 connects or disconnects: { connected: bool }
  Stream<Map<String, dynamic>> get esp32StatusUpdates =>
      _esp32StatusController.stream;
  /// Fires on every sensorUpdate from ESP32: { US_PICKUP, US_DROPOFF, REED_TOP, REED_PICKUP, REED_RECEIVED }
  Stream<Map<String, dynamic>> get binStatusUpdates =>
      _binStatusController.stream;
  /// Fires when backend confirms owner QR scan result: { approved: bool }
  Stream<Map<String, dynamic>> get ownerVerifyAck =>
      _ownerVerifyAckController.stream;
  /// Fires when the hardware shows the owner QR code (prompts owner to verify)
  Stream<Map<String, dynamic>> get ownerAccessAlerts =>
      _ownerAccessAlertController.stream;
  /// Fires when backend confirms device registration (after QR scan in app)
  Stream<Map<String, dynamic>> get deviceRegisteredStream =>
      _deviceRegisteredController.stream;
  /// Fires when device registration token is invalid or expired
  Stream<Map<String, dynamic>> get deviceRegistrationFailedStream =>
      _deviceRegistrationFailedController.stream;
  /// Fires when the hardware has saved WiFi config and is rebooting
  Stream<Map<String, dynamic>> get hardwareConfigAppliedStream =>
      _hardwareConfigAppliedController.stream;
  /// Fires when backend confirms device unregistration
  Stream<Map<String, dynamic>> get deviceUnregisteredStream =>
      _deviceUnregisteredController.stream;


  bool get isConnected => _socket?.connected ?? false;
  IO.Socket? get socket => _socket;

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

    // Phase 4: Hardware delivery events (ESP32 drop-off / pick-up)
    // Payload: { trackingId, status, mode, timestamp }
    _socket!.on('trackingStatusChanged', (data) {
      debugPrint('📦 Tracking status changed: $data');
      _trackingStatusController.add(data as Map<String, dynamic>);
    });

    // ESP32 connection status
    _socket!.on('esp32Status', (data) {
      debugPrint('🔌 ESP32 status: $data');
      _esp32StatusController.add(data as Map<String, dynamic>);
    });

    // Bin fill level updates from ultrasonic sensors
    _socket!.on('binStatusUpdate', (data) {
      debugPrint('📡 Bin status: $data');
      _binStatusController.add(data as Map<String, dynamic>);
    });

    // Owner QR verify acknowledgement from backend
    _socket!.on('ownerVerifyAck', (data) {
      debugPrint('🔑 Owner verify ack: $data');
      _ownerVerifyAckController.add(data as Map<String, dynamic>);
    });

    // Hardware entered owner verification — prompt owner to open app & scan
    _socket!.on('ownerAccessAlert', (data) {
      debugPrint('🔔 ownerAccessAlert received');
      _ownerAccessAlertController.add(
          (data as Map<String, dynamic>? ?? {'timestamp': DateTime.now().toIso8601String()}));
    });

    // Device registration confirmed (after app QR scan)
    _socket!.on('deviceRegistered', (data) {
      debugPrint('✅ deviceRegistered: $data');
      _deviceRegisteredController.add(data as Map<String, dynamic>);
    });

    // Device registration failed (invalid/expired token)
    _socket!.on('deviceRegistrationFailed', (data) {
      debugPrint('❌ deviceRegistrationFailed: $data');
      _deviceRegistrationFailedController.add(data as Map<String, dynamic>);
    });

    // Hardware saved WiFi config (device will reboot)
    _socket!.on('hardwareConfigApplied', (data) {
      debugPrint('⚙️ hardwareConfigApplied: $data');
      _hardwareConfigAppliedController.add(data as Map<String, dynamic>);
    });

    // Device unregistration confirmed
    _socket!.on('deviceUnregistered', (data) {
      debugPrint('🗑️ deviceUnregistered: $data');
      _deviceUnregisteredController.add(data as Map<String, dynamic>);
    });
  }

  /// Emit an event to the server
  void emit(String event, dynamic data) {
    if (_socket?.connected ?? false) {
      debugPrint('📤 Emitting event: $event ($data)');
      _socket!.emit(event, data);
    } else {
      debugPrint('⚠️ Cannot emit event: WebSocket not connected');
    }
  }

  /// Register a tracking ID on the ESP32 hardware (relayed via backend).
  ///
  /// Call this when a user schedules a delivery or pickup so the hardware
  /// knows which barcode to accept at the door.
  ///
  /// [trackingId] — the parcel tracking ID (matches the barcode)
  /// [mode]       — "drop_off" (delivery) or "pick_up" (retrieval)
  void emitRegisterTracking(String trackingId, String mode) {
    emit('registerTracking', {
      'trackingId': trackingId,
      'mode': mode,
    });
    debugPrint('📋 Emitted registerTracking: $trackingId ($mode)');
  }

  /// Manually control a specific door/lock on the hardware.
  ///
  /// Replaces ESP32_DoorControl.ino's HTTP POST /door endpoint.
  /// Use for admin/emergency access — bypasses the normal scan flow.
  ///
  /// [type]   — "top" (parcel entry), "pickup" (pickup bin), "received" (received bin)
  /// [action] — "open" (unlock solenoid) or "close" (lock solenoid)
  void emitControlDoor(String type, String action) {
    emit('controlDoor', {
      'type': type,
      'action': action,
    });
    debugPrint('🚪 Emitted controlDoor: $type → $action');
  }

  /// Request the current door states and parcel sensor readings from hardware.
  ///
  /// Replaces ESP32_DoorControl.ino's HTTP GET /status endpoint.
  /// The hardware will respond by emitting a [doorStateUpdates] event.
  void requestDoorStatus() {
    emit('getStatus', null);
    debugPrint('📊 Emitted getStatus request');
  }

  /// Query current ESP32 connection state from the backend.
  /// Backend responds with an [esp32StatusUpdates] event immediately.
  /// Call this on screen open to get the current state without waiting for
  /// a future connect/disconnect transition.
  void requestEsp32Status() {
    emit('getEsp32Status', null);
    debugPrint('📊 Emitted getEsp32Status request');
  }

  /// Send the scanned owner QR token to the backend for validation.
  /// Backend will validate and relay result to the ESP32.
  void emitVerifyOwnerQR(String token) {
    emit('verifyOwnerQR', {'token': token});
    debugPrint('🔑 Emitted verifyOwnerQR: $token');
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
    _trackingStatusController.close();
    _esp32StatusController.close();
    _binStatusController.close();
    _ownerVerifyAckController.close();
    _ownerAccessAlertController.close();
    _deviceRegisteredController.close();
    _deviceRegistrationFailedController.close();
    _hardwareConfigAppliedController.close();
    _deviceUnregisteredController.close();
  }

  /// Reset singleton instance
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }
}
