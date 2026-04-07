/// Model for user data
class UserModel {
  final String uid;
  final String email;
  final String fullName;
  final String phoneNumber;
  final String address;
  final String role; // user, courier, or admin
  final String status; // active, pending, rejected
  final DateTime? createdAt;
  final String? hmacKey; // Phase 4: Cryptographic symmetric key

  UserModel({
    required this.uid,
    required this.email,
    required this.fullName,
    required this.phoneNumber,
    required this.address,
    required this.role,
    this.status = 'active', // Default to active for existing users
    this.createdAt,
    this.hmacKey,
  });

  /// Create UserModel from Map
  factory UserModel.fromMap(Map<String, dynamic> data) {
    return UserModel(
      uid: data['_id'] ?? data['uid'] ?? '', // MongoDB uses _id, fallback to uid
      email: data['email'] ?? '',
      fullName: data['fullName'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      address: data['address'] ?? '',
      role: data['role'] ?? 'user',
      status: data['status'] ?? 'active', // Default to active if not specified
      createdAt: data['createdAt'] != null ? DateTime.tryParse(data['createdAt'].toString()) : null,
      hmacKey: data['hmacKey'],
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
      'status': status,
      'createdAt': createdAt?.toIso8601String(),
      'hmacKey': hmacKey,
    };
  }
}
