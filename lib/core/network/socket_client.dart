import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import '../../config/api_config.dart';

/// Socket.IO client wrapper
/// 
/// Provides WebSocket connectivity with:
/// - Automatic reconnection
/// - Event handling
/// - Connection state management
class SocketClient {
  IO.Socket? _socket;
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  /// Initialize socket connection
  void init(String userId) {
    if (_socket != null) {
      debugPrint('Socket already initialized');
      return;
    }

    _socket = IO.io(
      ApiConfig.socketUrl,   // root URL — Socket.IO doesn't use /api
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setExtraHeaders({'userId': userId})
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('✅ Socket connected');
      _isConnected = true;
      _socket!.emit('join', userId);
    });

    _socket!.onDisconnect((_) {
      debugPrint('❌ Socket disconnected');
      _isConnected = false;
    });

    _socket!.onError((error) {
      debugPrint('⚠️ Socket error: $error');
    });

    _socket!.connect();
  }

  /// Listen to an event
  void on(String event, Function(dynamic) handler) {
    _socket?.on(event, handler);
  }

  /// Emit an event
  void emit(String event, [dynamic data]) {
    if (_isConnected) {
      _socket?.emit(event, data);
    } else {
      debugPrint('⚠️ Cannot emit $event - socket not connected');
    }
  }

  /// Disconnect socket
  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
  }
}
