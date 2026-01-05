class ApiConfig {
  // Use '10.0.2.2' to access your machine's localhost from the Android Emulator
  // Use your computer's local IP (e.g., '192.168.1.5') if testing on a real device
  static const String baseUrl = 'https://smart-parcel-dropbox.onrender.com/api';
  
  static const String users = '$baseUrl/users';
  static const String tracking = '$baseUrl/tracking';
  static const String scanLogs = '$baseUrl/scan-logs';
  static const String notifications = '$baseUrl/notifications';
  static const String deviceControl = '$baseUrl/device-control';
}
