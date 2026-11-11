/// Dropbox — represents a registered Smart Parcel Dropbox hardware unit.
class Dropbox {
  final String deviceId;
  /// All users who have registered this device (multi-user support).
  final List<String> userIds;
  /// The first user who registered this device.
  final String? primaryUserId;
  final String name;
  final bool isRegistered;
  final String status;
  final String? wifiSSID;
  final int pickupCount;
  final int dropoffCount;
  final DateTime? registeredAt;
  final DateTime? lastSeenAt;
  final HardwareDiagnostics? diagnostics;

  const Dropbox({
    required this.deviceId,
    this.userIds = const [],
    this.primaryUserId,
    required this.name,
    required this.isRegistered,
    required this.status,
    this.wifiSSID,
    this.pickupCount = 0,
    this.dropoffCount = 0,
    this.registeredAt,
    this.lastSeenAt,
    this.diagnostics,
  });

  /// Backward-compat accessor — returns primaryUserId or the first entry in userIds.
  String get userId => primaryUserId ?? (userIds.isNotEmpty ? userIds.first : '');

  /// How many users have this device registered.
  int get registeredUserCount => userIds.length;

  factory Dropbox.fromJson(Map<String, dynamic> json) {
    // Parse userIds — the API may return an array or nothing (legacy doc)
    final rawIds = json['userIds'];
    List<String> parsedIds;
    if (rawIds is List) {
      parsedIds = rawIds.map((e) => e.toString()).toList();
    } else if (json['userId'] != null && (json['userId'] as String).isNotEmpty) {
      // Migrate legacy single userId into a list for in-memory use
      parsedIds = [json['userId'] as String];
    } else {
      parsedIds = [];
    }

    return Dropbox(
      deviceId:     json['deviceId'] ?? '',
      userIds:      parsedIds,
      primaryUserId: json['primaryUserId'] as String?,
      name:         json['name'] ?? 'My Smart Parcel Dropbox',
      isRegistered: json['isRegistered'] ?? false,
      status:       json['status'] ?? 'offline',
      wifiSSID:     json['wifiSSID'],
      pickupCount:  json['pickupCount'] ?? 0,
      dropoffCount: json['dropoffCount'] ?? 0,
      registeredAt: json['registeredAt'] != null
          ? DateTime.tryParse(json['registeredAt'])
          : null,
      lastSeenAt: json['lastSeenAt'] != null
          ? DateTime.tryParse(json['lastSeenAt'])
          : null,
      diagnostics: HardwareDiagnostics.tryParse(json['diagnostics']),
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceId':      deviceId,
    'userIds':       userIds,
    'primaryUserId': primaryUserId,
    'name':          name,
    'isRegistered':  isRegistered,
    'status':        status,
    'wifiSSID':      wifiSSID,
    'pickupCount':   pickupCount,
    'dropoffCount':  dropoffCount,
    if (diagnostics != null) 'diagnostics': diagnostics!.toJson(),
  };
}

class HardwareDiagnostics {
  const HardwareDiagnostics({
    required this.firmwareVersion,
    required this.wifiRssi,
    required this.uptimeSeconds,
    required this.reportedAt,
  });

  static const freshness = Duration(seconds: 90);
  final String firmwareVersion;
  final int wifiRssi;
  final int uptimeSeconds;
  final DateTime reportedAt;

  bool isStaleAt(DateTime now) => now.difference(reportedAt) >= freshness;

  static HardwareDiagnostics? tryParse(Object? data) {
    if (data is! Map<String, dynamic>) return null;
    final version = data['firmwareVersion'];
    final rssi = data['wifiRssi'];
    final uptime = data['uptimeSeconds'];
    final timestamp = data['reportedAt'];
    if (version is! String || version.isEmpty || rssi is! int ||
        uptime is! int || uptime < 0 || timestamp is! String) {
      return null;
    }
    final reportedAt = DateTime.tryParse(timestamp);
    if (reportedAt == null) return null;
    return HardwareDiagnostics(
      firmwareVersion: version, wifiRssi: rssi, uptimeSeconds: uptime, reportedAt: reportedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'firmwareVersion': firmwareVersion,
    'wifiRssi': wifiRssi,
    'uptimeSeconds': uptimeSeconds,
    'reportedAt': reportedAt.toIso8601String(),
  };
}

