/// Model for user data
class UserModel {
  final String uid;
  final String email;
  final String fullName;
  final String phoneNumber;
  final String address;
  final String role; // user, courier, or admin
  final DateTime? createdAt;

  UserModel({
    required this.uid,
    required this.email,
    required this.fullName,
    required this.phoneNumber,
    required this.address,
    required this.role,
    this.createdAt,
  });

  /// Create UserModel from Map
  factory UserModel.fromMap(Map<String, dynamic> data) {
    return UserModel(
      uid: data['uid'] ?? '',
      email: data['email'] ?? '',
      fullName: data['fullName'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      address: data['address'] ?? '',
      role: data['role'] ?? 'user',
      createdAt: data['createdAt']?.toDate(),
    );
  }

  /// Convert to Map
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'address': address,
      'role': role,
      'createdAt': createdAt,
    };
  }
}
