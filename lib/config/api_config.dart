class ApiConfig {
  // LOCAL TESTING: 10.0.2.2 is the localhost for Android Emulator
  // LOCAL TESTING: For real devices, use your PC's IP (e.g., 192.168.18.78)
  static const String baseUrl = 'http://10.0.2.2:5000/api';
  
  // Socket.IO connects to the root server URL (no /api)
  static const String socketUrl = 'http://10.0.2.2:5000';
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
