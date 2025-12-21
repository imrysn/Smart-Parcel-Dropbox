import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Authentication Service for Smart Parcel Drop Box System
/// Handles user registration, login, and authentication state
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
        // If the account already exists in Auth, check if they can log in
        // This handles cases where an admin deleted the Firestore doc but not the Auth account
        try {
          userCredential = await _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );

          // Check if document exists in Firestore
          final doc = await _firestore.collection('users').doc(userCredential.user!.uid).get();
          if (doc.exists) {
            // Account is active and has data, so it really is "already in use"
            throw _handleAuthException(e);
          }
          // If it doesn't exist, we continue to create the document below
        } catch (signInError) {
          // If sign-in fails, it means either:
          // 1. Wrong password for existing account
          // 2. Some other error
          // In either case, we should respect the original 'email-already-in-use' error
          throw _handleAuthException(e);
        }
      } else {
        throw _handleAuthException(e);
      }
    }

    try {
      // Create or re-create user document in Firestore
      await _firestore.collection('users').doc(userCredential!.user!.uid).set({
        'uid': userCredential.user!.uid,
        'email': email,
        'fullName': fullName,
        'phoneNumber': phoneNumber,
        'address': address,
        'createdAt': FieldValue.serverTimestamp(),
        'role': 'user', // user, courier, or admin
        'trackingNumbers': [], // Empty array for tracking numbers
      });

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
