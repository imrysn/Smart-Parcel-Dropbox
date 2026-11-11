import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/tracking_model.dart';
import 'auth_service.dart';
import 'notification_service.dart';

class DeliveryPushService {
  DeliveryPushService(this._auth, this._notifications);

  static const _installationKey = 'delivery_push_installation';
  static final _eventIdPattern = RegExp(r'^[a-f0-9]{24}$');
  static const _timeout = Duration(seconds: 5);
  final AuthService _auth;
  final NotificationService _notifications;
  final _storage = const FlutterSecureStorage();
  final pendingTap = ValueNotifier<String?>(null);
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Future<bool>? _initialization;
  Future<void> _operations = Future<void>.value();
  String? _activeUserId;
  String? _registeredUserId;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool registeredFor(String userId) => _registeredUserId == userId;

  Future<bool> initialize() => _initialization ??= _initialize();

  Future<bool> _initialize() async {
    if (!_supported) return false;
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      _subscriptions.addAll([
        messaging.onTokenRefresh.listen((_) {
          final userId = _activeUserId;
          if (userId != null) unawaited(sync(userId));
        }),
        FirebaseMessaging.onMessageOpenedApp
            .listen((message) => handleTap(message.data)),
        FirebaseMessaging.onMessage
            .listen((message) => unawaited(_showForeground(message.data))),
      ]);
      final initial = await messaging.getInitialMessage();
      if (initial != null) handleTap(initial.data);
      return true;
    } catch (_) {
      debugPrint(
          'Android push initialization failed. Local delivery alerts remain available.');
      return false;
    }
  }

  void handleTap(Map<String, dynamic> data) {
    final id = data['notificationId'];
    if (data['type'] == 'parcel_delivered' &&
        id is String &&
        _eventIdPattern.hasMatch(id)) {
      pendingTap.value = id;
    }
  }

  Future<TrackingModel?> loadParcel(String eventId, String userId) async {
    if (!_eventIdPattern.hasMatch(eventId) ||
        await _auth.currentUserId != userId) {
      return null;
    }
    final headers = await _auth.getAuthHeaders();
    if (await _auth.currentUserId != userId) return null;
    final response = await http
        .get(
          Uri.parse('${ApiConfig.notifications}/$eventId/parcel'),
          headers: headers,
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200 || await _auth.currentUserId != userId) {
      return null;
    }
    final parcel = TrackingModel.fromMap(
        jsonDecode(response.body) as Map<String, dynamic>);
    return parcel.userId == userId ? parcel : null;
  }

  Future<void> _showForeground(Map<String, dynamic> data) async {
    final userId = _activeUserId;
    final id = data['notificationId'];
    if (userId == null || data['type'] != 'parcel_delivered' || id is! String) {
      return;
    }
    try {
      if (await loadParcel(id, userId) != null && _activeUserId == userId) {
        await _notifications.showParcelDelivered(id);
      }
    } catch (_) {
      debugPrint('Could not verify the foreground parcel alert.');
    }
  }

  Future<void> _serialize(Future<void> Function() action) {
    return _operations = _operations.then((_) async {
      try {
        await action();
      } catch (_) {
        debugPrint('Could not update the delivery push registration.');
      }
    });
  }

  Future<void> sync(String userId) {
    if (!_supported) return Future<void>.value();
    _activeUserId = userId;
    return _serialize(() async {
      if (_activeUserId != userId || !await initialize()) return;
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        _registeredUserId = null;
        await _detach();
        return;
      }
      final token = await messaging.getToken().timeout(_timeout);
      final headers = await _auth.getAuthHeaders();
      if (token == null ||
          _activeUserId != userId ||
          await _auth.currentUserId != userId) {
        return;
      }
      var id = await _storage.read(key: _installationKey);
      if (id == null) {
        final random = Random.secure();
        id = List.generate(16,
                (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
            .join();
        await _storage.write(key: _installationKey, value: id);
      }
      if (_activeUserId != userId) return;
      final response = await http
          .put(
            _uri(id),
            headers: headers,
            body: jsonEncode({'token': token}),
          )
          .timeout(_timeout);
      _registeredUserId =
          response.statusCode == 204 && _activeUserId == userId ? userId : null;
    });
  }

  Uri _uri(String id) =>
      Uri.parse('${ApiConfig.notifications}/push-installations/$id');

  Future<void> _detach() async {
    final id = await _storage.read(key: _installationKey);
    if (id == null) return;
    try {
      final headers = await _auth.getAuthHeaders();
      final response =
          await http.delete(_uri(id), headers: headers).timeout(_timeout);
      if (response.statusCode == 204) return;
    } catch (_) {
      // Try invalidating the Firebase token when SPD is unavailable.
    }
    if (await initialize()) {
      await FirebaseMessaging.instance.deleteToken().timeout(_timeout);
    }
  }

  Future<void> endSession() {
    _activeUserId = null;
    _registeredUserId = null;
    pendingTap.value = null;
    return _supported ? _serialize(_detach) : Future<void>.value();
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    pendingTap.dispose();
  }
}
