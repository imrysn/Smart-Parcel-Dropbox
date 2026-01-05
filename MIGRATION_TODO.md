# URGENT: Complete MongoDB Migration - Remaining Tasks

## Current Status
✅ Backend is 100% MongoDB-ready
✅ AuthService rewritten for MongoDB
✅ LoginScreen updated
✅ Password reset flow updated
❌ Several screens still reference old Firebase Auth

## Compilation Errors to Fix

### 1. Remove Firebase Auth Import from All Screens
Replace:
```dart
import 'package:firebase_auth/firebase_auth.dart';
```
With: Nothing (remove the line)

### 2. Replace All `currentUser` References

The new AuthService doesn't have a `currentUser` getter. Instead, use:

**OLD CODE:**
```dart
final user = _authService.currentUser;
final uid = user?.uid;
```

**NEW CODE:**
```dart
final userId = await _authService.currentUserId;
```

### 3. Files That Need Updating

#### A. `lib/screens/home_screen.dart`
- Line 2: Remove `import 'package:firebase_auth/firebase_auth.dart';`
- Line 33: Change `User? _currentUser;` to `String? _currentUserId;`
- Line 46: Change `_currentUser = _authService.currentUser;` to `_currentUserId = await _authService.currentUserId;`
- Line 65-71: Replace `_currentUser!.uid` with `_currentUserId!`
- Line 232: Replace `_authService.currentUser?.uid` with `await _authService.currentUserId`
- Line 382-389: Remove StreamBuilder<User?> and use FutureBuilder or direct userId
- Line 573-580: Same as above

#### B. `lib/screens/admin/admin_dashboard_screen.dart`
- Remove Firebase Auth import
- Line 37: Replace `_authService.currentUser?.uid` with `await _authService.currentUserId`
- Line 41: Update to use userId instead of uid
- Line 78: Replace `_authService.currentUser` with `await _authService.currentUserId`
- Line 450, 454, 457: Replace `_authService.currentUser?.uid` with current user ID

#### C. `lib/screens/splash_screen.dart`
- Remove Firebase Auth import
- Line 98: Replace `FirebaseAuth.instance.currentUser` with `await _authService.isLoggedIn`
- Update logic to check for JWT token instead of Firebase user

#### D. `lib/screens/notifications_screen.dart`
- Remove Firebase Auth import
- Line 21: Replace `_authService.currentUser` with `await _authService.currentUserId`

#### E. `lib/screens/logs_screen.dart`
- Remove Firebase Auth import
- Line 28: Replace `FirebaseAuth.instance.currentUser` with `await _authService.currentUserId`
- Line 60: Update to use userId

#### F. `lib/screens/add_tracking_screen.dart`
- Remove Firebase Auth import
- Line 33: Replace `FirebaseAuth.instance.currentUser` with `await _authService.currentUserId`

#### G. `lib/screens/register_screen.dart`
- Update to use new `registerWithEmailAndPassword` method
- Handle returned user data properly

### 4. Update Main.dart

Remove all Firebase initialization:
```dart
// REMOVE THESE:
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

// REMOVE:
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
```

### 5. Quick Fix Script

Create a simple find-replace:

1. **Find:** `FirebaseAuth.instance.currentUser`
   **Replace:** `await AuthService().currentUserId`

2. **Find:** `_authService.currentUser?.uid`
   **Replace:** `await _authService.currentUserId`

3. **Find:** `_authService.currentUser`
   **Replace:** `await _authService.currentUserId`

4. **Find:** `import 'package:firebase_auth/firebase_auth.dart';`
   **Replace:** (delete line)

5. **Find:** `User? user`
   **Replace:** `String? userId`

6. **Find:** `user.uid`
   **Replace:** `userId`

### 6. Testing Checklist

After fixing all files:
- [ ] App compiles without errors
- [ ] Login works
- [ ] Registration works
- [ ] Password reset works
- [ ] Home screen loads
- [ ] Profile tab works
- [ ] Admin dashboard works (if admin)
- [ ] Logout works

### 7. Environment Setup

Make sure `server/.env` has:
```
PORT=5000
MONGODB_URI=mongodb://localhost:27017/smart_parcel
JWT_SECRET=your-super-secret-jwt-key-minimum-32-characters-long
EMAIL_USER=your-gmail@gmail.com
EMAIL_PASS=your-gmail-app-password
```

### 8. Start Backend

```bash
cd server
npm run dev
```

### 9. Run App

```bash
flutter run
```

## Why This Happened

The old system used Firebase Auth which had a synchronous `currentUser` getter. The new MongoDB system uses JWT tokens stored in secure storage, which requires async operations (`await`).

## Next Steps

1. Fix all the files listed above
2. Remove Firebase dependencies from pubspec.yaml (optional, can do later)
3. Test the entire flow
4. Update documentation

## Need Help?

If you want me to fix all these files automatically, just say "fix all screens" and I'll update them one by one.
