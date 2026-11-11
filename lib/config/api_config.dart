class ApiConfig {
  // LOCAL TESTING: Localhost for Windows Desktop app
  static const String baseUrl = 'http://localhost:3000/api';
  
  // Socket.IO connects to the root server URL (no /api)
  static const String socketUrl = 'http://localhost:3000';
  
  static const String users = '$baseUrl/users';
  static const String tracking = '$baseUrl/tracking';
  static const String scanLogs = '$baseUrl/scan-logs';
  static const String notifications = '$baseUrl/notifications';
  static const String deviceControl = '$baseUrl/device-control';
  static const String dropbox = '$baseUrl/dropbox';
  static const String business = '$baseUrl/business';
  static const String tasks = '$baseUrl/tasks';
  static const String financial = '$baseUrl/financial';
  static const String payments = '$baseUrl/payments';

  // User Management Admin Endpoints
  static const String pendingUsers = '$baseUrl/users/pending';
  static const String approveUser = '$baseUrl/users/approve';
  static const String rejectUser = '$baseUrl/users/reject';

  // Public Branded Web Pass for Couriers & Riders
  static const String publicWebDomain = 'https://smart-parcel-dropbox-depth.onrender.com';
  static String passUrl(String trackingId) => '$publicWebDomain/pass/$trackingId';
}
