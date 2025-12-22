import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
/// Authentication Service for Smart Parcel Drop Box System
/// Handles user registration, login, and authentication state
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in with email and password
  Future<UserCredential?> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Register new user
  Future<UserCredential?> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
    required String address,
  }) async {
    UserCredential? userCredential;

    try {
      // First, try to create a new user account
      userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        try {
          userCredential = await _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
        } catch (signInError) {
          throw _handleAuthException(e);
        }
      } else {
        throw _handleAuthException(e);
      }
    }

    try {
      // Create or re-create user document in Node.js Backend
      print('Attempting to sync user to backend: ${ApiConfig.users}');
      final response = await http.post(
        Uri.parse(ApiConfig.users),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': userCredential!.user!.uid,
          'email': email,
          'fullName': fullName,
          'phoneNumber': phoneNumber,
          'address': address,
          'role': 'user',
        }),
      );

      print('Backend sync response: ${response.statusCode}');
      print('Backend sync body: ${response.body}');

      if (response.statusCode != 201 && response.statusCode != 400) {
        throw 'Failed to sync user profile with backend: ${response.body}';
      }

      return userCredential;
    } catch (e) {
      throw 'Failed to create user profile: $e';
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // Handle authentication exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'user-disabled':
        return 'This account has been disabled.';
      default:
        return 'Authentication error: ${e.message}';
    }
  }
}
