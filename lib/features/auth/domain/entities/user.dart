import 'package:equatable/equatable.dart';

/// User entity - Domain layer
class User extends Equatable {
  final String id;
  final String email;
  final String? fullName;
  final String? phoneNumber;
  final String? address;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const User({
    required this.id,
    required this.email,
    this.fullName,
    this.phoneNumber,
    this.address,
    required this.createdAt,
    this.updatedAt,
  });

  @override
  List<Object?> get props => [
        id,
        email,
        fullName,
        phoneNumber,
        address,
        createdAt,
        updatedAt,
      ];

  /// Get display name (full name or email)
  String get displayName => fullName ?? email.split('@').first;

  /// Check if profile is complete
  bool get isProfileComplete =>
      fullName != null && phoneNumber != null && address != null;

  User copyWith({
    String? id,
    String? email,
    String? fullName,
    String? phoneNumber,
    String? address,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
