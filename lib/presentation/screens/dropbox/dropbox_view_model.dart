import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/service_locator.dart';
import '../../../services/websocket_service.dart';
import '../../../services/auth_service.dart';
import '../../../services/dropbox_service.dart';

/// Single-responsibility ViewModel for DropboxControlScreen hardware state & controls.
class DropboxViewModel extends ChangeNotifier {
  late final WebSocketService _ws;
  StreamSubscription<Map<String, dynamic>>? _esp32Sub;

  bool esp32Connected = false;
  bool isLockdownActive = false;
  final Map<String, bool> doorOpen = {'top': false, 'pickup': false, 'received': false};
  final Map<String, bool> doorProcessing = {'top': false, 'pickup': false, 'received': false};
  final Map<String, bool?> reedState = {'REED_TOP': null, 'REED_PICKUP': null, 'REED_RECEIVED': null};

  String? userId;
  bool hasDropbox = false;
  bool registrationChecked = false;
  int registeredUserCount = 0;

  void init() {
    _ws = getIt<WebSocketService>();
    _initUser();
  }

  Future<void> _initUser() async {
    final auth = getIt<AuthService>();
    userId = await auth.currentUserId;
    if (userId != null) {
      final dropboxService = getIt<DropboxService>();
      final dropbox = await dropboxService.getUserDropbox(userId!);
      hasDropbox = dropbox != null;
      registrationChecked = true;
      if (dropbox != null) {
        registeredUserCount = dropbox.registeredUserCount;
      }
      notifyListeners();
    }
  }

  void toggleLockdown(bool value) {
    isLockdownActive = value;
    notifyListeners();
  }

  void unlockDoor(String doorType) {
    doorProcessing[doorType] = true;
    notifyListeners();

    _ws.controlDoor(doorType);

    // Auto reset processing state after 3 seconds
    Timer(const Duration(seconds: 3), () {
      doorProcessing[doorType] = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _esp32Sub?.cancel();
    super.dispose();
  }
}
