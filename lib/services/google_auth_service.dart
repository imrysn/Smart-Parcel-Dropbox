import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'database_service.dart';

/// Google Authentication Service
/// Handles Google Sign-In with Firebase Authentication
class GoogleAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);
  final DatabaseService _databaseService = DatabaseService();

  /// Signs in user with Google account
  /// Returns UserCredential if successful, null otherwise
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Trigger the Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      // User canceled the sign-in
      if (googleUser == null) {
        return null;
      }

      // Retrieve authentication details from Google account
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential using Google authentication details
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      // Ensure user document exists in Backend (handles re-registration of deleted accounts)
      final userData = await _databaseService.getUserData(userCredential.user!.uid);
      if (userData == null) {
        await _createUserInBackend(userCredential.user!);
      }

      return userCredential;
    } catch (e) {
      print('Error signing in with Google: $e');
      return null;
    }
  }

  /// Creates user in Node.js backend
  Future<void> _createUserInBackend(User user) async {
    try {
      await http.post(
        Uri.parse(ApiConfig.users),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uid': user.uid,
          'email': user.email,
          'fullName': user.displayName ?? '',
          'phoneNumber': '',
          'address': '',
          'role': 'user',
        }),
      );
    } catch (e) {
      print('Error creating user in backend: $e');
    }
  }

  /// Signs out user from both Google and Firebase
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      print('Error signing out: $e');
    }
  }

  /// Gets current user
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  /// Checks if user is signed in
  bool isSignedIn() {
    return _auth.currentUser != null;
  }
}
