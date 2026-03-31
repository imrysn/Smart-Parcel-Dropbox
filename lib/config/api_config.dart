class ApiConfig {
  // LOCAL TESTING: PC must be connected to the Android hotspot
  // LOCAL TESTING: PC IP on your current network/hotspot
  static const String baseUrl = 'http://192.168.18.78:5000/api';
  
  // Socket.IO connects to the root server URL (no /api)
  // IMPORTANT: For local hotspot testing, use http:// and your PC's IP
  static const String socketUrl = 'http://192.168.18.78:5000';
  // static const String socketUrl = 'https://smart-parcel-dropbox.onrender.com';  // production
  
  static const String users = '$baseUrl/users';
  static const String tracking = '$baseUrl/tracking';
  static const String scanLogs = '$baseUrl/scan-logs';
  static const String notifications = '$baseUrl/notifications';
  static const String deviceControl = '$baseUrl/device-control';
  static const String dropbox = '$baseUrl/dropbox';

  // User Management Admin Endpoints
  static const String pendingUsers = '$baseUrl/users/pending';
  static const String approveUser = '$baseUrl/users/approve';
  static const String rejectUser = '$baseUrl/users/reject';
}
