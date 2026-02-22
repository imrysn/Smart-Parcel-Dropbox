class ApiConfig {
  // LOCAL TESTING: PC must be connected to the Android hotspot
  static const String baseUrl = 'http://192.180.100.130:3000/api';
  // PRODUCTION (Render.com): uncomment below and comment above when deploying
  // static const String baseUrl = 'http://192.180.100.130:3000/api';

  // Socket.IO connects to the root server URL (no /api)
  static const String socketUrl = 'https://smart-parcel-dropbox.onrender.com';
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
