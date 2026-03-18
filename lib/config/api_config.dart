class ApiConfig {
  // LOCAL TESTING: PC must be connected to the Android hotspot
  // LOCAL TESTING: PC IP on your current network/hotspot
  static const String baseUrl = 'http://10.222.49.205:3000/api';
  
  // Socket.IO connects to the root server URL (no /api)
  // IMPORTANT: For local hotspot testing, use http:// and your PC's IP
  static const String socketUrl = 'http://10.222.49.205:3000';
  // static const String socketUrl = 'https://smart-parcel-dropbox.onrender.com';  // production
  
  static const String users = '$baseUrl/users';
  static const String tracking = '$baseUrl/tracking';
  static const String scanLogs = '$baseUrl/scan-logs';
  static const String notifications = '$baseUrl/notifications';
  static const String deviceControl = '$baseUrl/device-control';
  
  // Google OAuth endpoints
  static const String googleAuth = '$baseUrl/users/google-auth';
  static const String approveUser = '$baseUrl/users/approve';
  static const String rejectUser = '$baseUrl/users/reject';
  static const String pendingUsers = '$baseUrl/users/pending';
}
