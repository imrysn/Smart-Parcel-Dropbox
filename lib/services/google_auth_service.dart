import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';

/// Google Auth Service for Smart Parcel Drop Box System
class GoogleAuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    clientId: '946994441160-9g4qcf2oabb1lqdmu5mu4n1ki57qc5r0.apps.googleusercontent.com',
  );

  /// Sign in with Google and return ID token
  Future<String?> signInWithGoogle() async {
    try {
      // Trigger Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        // User canceled the sign-in
        return null;
      }

      // Get authentication details
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      // Return ID token for backend verification
      return googleAuth.idToken;
    } catch (e) {
      debugPrint('Error signing in with Google: $e');
      rethrow;
    }
  }

  /// Get current Google user
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  /// Sign out from Google
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('Error signing out from Google: $e');
    }
  }
}
