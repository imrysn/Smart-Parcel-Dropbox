import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Google Authentication Service
/// Handles Google Sign-In with Firebase Authentication
class GoogleAuthService {

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;



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



      // Create user document in Firestore if it's a new user
      if (userCredential.additionalUserInfo?.isNewUser ?? false) {
        await _createUserDocument(userCredential.user!);
      }



      return userCredential;
    } catch (e) {
      print('Error signing in with Google: $e');
      return null;
    }

  }

  /// Creates user document in Firestore
  Future<void> _createUserDocument(User user) async {

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'provider': 'google',
        'createdAt': FieldValue.serverTimestamp(),
        'trackingNumbers': [], // Empty array for tracking numbers
      });

    } catch (e) {
      print('Error creating user document: $e');
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
