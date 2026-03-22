/// Dropbox — represents a registered Smart Parcel Dropbox hardware unit.
class Dropbox {
  final String deviceId;
  final String userId;
  final String name;
  final bool isRegistered;
  final String status;
  final String? wifiSSID;
  final DateTime? registeredAt;
  final DateTime? lastSeenAt;

  const Dropbox({
    required this.deviceId,
    required this.userId,
    required this.name,
    required this.isRegistered,
    required this.status,
    this.wifiSSID,
    this.registeredAt,
    this.lastSeenAt,
  });

  factory Dropbox.fromJson(Map<String, dynamic> json) {
    return Dropbox(
      deviceId:     json['deviceId'] ?? '',
      userId:       json['userId'] ?? '',
      name:         json['name'] ?? 'My Smart Parcel Dropbox',
      isRegistered: json['isRegistered'] ?? false,
      status:       json['status'] ?? 'offline',
      wifiSSID:     json['wifiSSID'],
      registeredAt: json['registeredAt'] != null
          ? DateTime.tryParse(json['registeredAt'])
          : null,
      lastSeenAt: json['lastSeenAt'] != null
          ? DateTime.tryParse(json['lastSeenAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceId':     deviceId,
    'userId':       userId,
    'name':         name,
    'isRegistered': isRegistered,
    'status':       status,
    'wifiSSID':     wifiSSID,
  };
}
