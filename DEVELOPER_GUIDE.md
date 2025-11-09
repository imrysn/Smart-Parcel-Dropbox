# 🔧 Developer Cheat Sheet

## Quick Commands Reference

### Essential Flutter Commands

```bash
# Check Flutter installation and dependencies
flutter doctor

# Get/update dependencies
flutter pub get

# Run the app (debug mode)
flutter run

# Run with hot reload enabled (default)
flutter run --hot

# Run in release mode (optimized)
flutter run --release

# Run on specific device
flutter run -d <device-id>

# List connected devices
flutter devices

# View real-time logs
flutter logs

# Clean build cache
flutter clean

# Upgrade packages
flutter pub upgrade

# Analyze code for issues
flutter analyze

# Format code
flutter format lib/

# Build APK (release)
flutter build apk --release

# Build App Bundle (for Play Store)
flutter build appbundle --release

# Build APK (debug)
flutter build apk --debug
```

### Git Commands (for version control)

```bash
# Initialize git
git init

# Add all files
git add .

# Commit changes
git commit -m "Your commit message"

# Check status
git status

# Create new branch
git checkout -b feature-name

# Switch branch
git checkout branch-name

# Push to remote
git push origin branch-name

# Pull latest changes
git pull
```

### Firebase Commands

```bash
# Login to Firebase
firebase login

# List projects
firebase projects:list

# Initialize Firebase in project
firebase init

# Deploy to Firebase Hosting (if using)
firebase deploy
```

## 🔍 Debugging Commands

### Check Device Connection
```bash
# For Android
adb devices

# Restart ADB server
adb kill-server
adb start-server

# Check device logs
adb logcat | grep flutter
```

### Performance Analysis
```bash
# Profile app performance
flutter run --profile

# Analyze build size
flutter build apk --analyze-size

# Check memory usage
flutter run --enable-dart-profiling
```

## 🐛 Common Issues & Solutions

### Issue 1: "Flutter command not found"
**Solution:**
```bash
# Add Flutter to PATH
# Windows: Add C:\flutter\bin to System Environment Variables
# Check installation
where flutter
```

### Issue 2: "Gradle build failed"
**Solution:**
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter run
```

### Issue 3: "Firebase not initialized"
**Solution:**
- Check `firebase_options.dart` exists
- Verify `google-services.json` is in `android/app/`
- Ensure Firebase dependencies are in `pubspec.yaml`

### Issue 4: "No connected devices"
**Solution:**
```bash
# For Android
adb devices
# Enable USB debugging on device

# For emulator
# Open Android Studio → AVD Manager → Start emulator
```

### Issue 5: "Version conflicts"
**Solution:**
```bash
flutter clean
rm pubspec.lock
flutter pub get
```

### Issue 6: "Build stuck or slow"
**Solution:**
```bash
# Disable Gradle daemon
cd android
./gradlew --stop
cd ..
flutter clean
flutter run
```

### Issue 7: "Hot reload not working"
**Solution:**
```bash
# Press 'R' in terminal to hot restart
# Or restart app completely
# Check if changes are in build/ folder (clean if needed)
```

### Issue 8: "Firebase Auth errors"
**Solutions:**
- Check Firebase Console Authentication is enabled
- Verify email/password provider is enabled
- Check Firestore rules allow access
- Ensure package name matches Firebase config

### Issue 9: "Firestore permission denied"
**Solution:**
```javascript
// Update Firestore rules to test mode temporarily
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true; // TEST MODE ONLY!
    }
  }
}
```

### Issue 10: "App crashes on startup"
**Solutions:**
```bash
# Check logs
flutter logs

# Clear app data
adb shell pm clear com.example.smart_parcel_dropbox

# Rebuild
flutter clean
flutter run
```

## 📱 Testing Commands

### Unit Testing
```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/widget_test.dart

# Run with coverage
flutter test --coverage

# View coverage report
genhtml coverage/lcov.info -o coverage/html
```

### Integration Testing
```bash
# Run integration tests
flutter drive --target=test_driver/app.dart
```

## 🔧 VS Code Shortcuts

```
Ctrl+Shift+P - Command Palette
F5 - Start Debugging
Ctrl+F5 - Run Without Debugging
Shift+F5 - Stop Debugging
Ctrl+Shift+` - New Terminal
Ctrl+` - Toggle Terminal

Flutter Commands (Ctrl+Shift+P):
- Flutter: New Project
- Flutter: Run Flutter Doctor
- Flutter: Hot Reload
- Flutter: Hot Restart
```

## 🎯 Code Snippets

### StatefulWidget
```dart
stful + Tab
```

### StatelessWidget
```dart
stless + Tab
```

### Import Material
```dart
import 'package:flutter/material.dart';
```

### Async Function
```dart
Future<void> functionName() async {
  // code
}
```

## 📊 Performance Tips

### 1. Use const constructors
```dart
const Text('Hello')  // Better than Text('Hello')
```

### 2. Avoid rebuilds
```dart
// Use keys when needed
key: ValueKey('unique_key')
```

### 3. ListView optimization
```dart
// Use builder for long lists
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) => ItemWidget(items[index]),
)
```

### 4. Image optimization
```dart
// Use cached network images
Image.network(url, cacheWidth: 300, cacheHeight: 300)
```

## 🔐 Security Checklist

- [ ] Remove all print() statements before release
- [ ] Update Firestore security rules
- [ ] Enable ProGuard for Android
- [ ] Use environment variables for sensitive data
- [ ] Implement proper error handling
- [ ] Add input validation
- [ ] Test on multiple devices
- [ ] Check for memory leaks

## 📦 Build Checklist

Before building release APK:
- [ ] Update version in pubspec.yaml
- [ ] Test on multiple devices
- [ ] Check all features work offline
- [ ] Verify Firebase configuration
- [ ] Test push notifications
- [ ] Update app icons
- [ ] Create signing key
- [ ] Update AndroidManifest.xml
- [ ] Test release build
- [ ] Generate release APK

## 🚀 Deployment Checklist

### Google Play Store:
- [ ] Create developer account
- [ ] Prepare store listing
- [ ] Create screenshots (phone, tablet, TV)
- [ ] Write description
- [ ] Set pricing and distribution
- [ ] Upload APK/Bundle
- [ ] Fill content rating questionnaire
- [ ] Submit for review

### Firebase Deployment:
- [ ] Set up production Firebase project
- [ ] Update security rules
- [ ] Set up Cloud Functions (if needed)
- [ ] Configure monitoring
- [ ] Set up backup
- [ ] Enable analytics

## 📝 Code Style Guide

### Naming Conventions
```dart
// Classes: PascalCase
class MyClass {}

// Variables/Functions: camelCase
String myVariable;
void myFunction() {}

// Constants: lowerCamelCase
const myConstant = 'value';

// Private members: _camelCase
String _privateVariable;
```

### File Naming
```
// Files: snake_case
my_screen.dart
user_service.dart
tracking_model.dart
```

## 🔄 Update Dependencies

```bash
# Check for outdated packages
flutter pub outdated

# Update all dependencies
flutter pub upgrade

# Update specific package
flutter pub upgrade package_name

# Get compatible versions
flutter pub upgrade --major-versions
```

## 📱 Device Emulator Commands

```bash
# List emulators
flutter emulators

# Launch specific emulator
flutter emulators --launch <emulator_id>

# Create new emulator (Android Studio)
# Tools → AVD Manager → Create Virtual Device
```

## 🎨 Asset Management

### Add images
1. Create `assets/images/` folder
2. Add images
3. Update `pubspec.yaml`:
```yaml
flutter:
  assets:
    - assets/images/
```

### Add fonts
1. Create `assets/fonts/` folder
2. Add font files
3. Update `pubspec.yaml`:
```yaml
flutter:
  fonts:
    - family: CustomFont
      fonts:
        - asset: assets/fonts/CustomFont-Regular.ttf
```

## 🌐 Environment Variables

### Create `.env` file:
```
API_KEY=your_api_key
BASE_URL=https://api.example.com
```

### Add to `.gitignore`:
```
.env
```

### Use in code:
```dart
// Add package: flutter_dotenv
import 'package:flutter_dotenv/flutter_dotenv.dart';

await dotenv.load();
String apiKey = dotenv.env['API_KEY']!;
```

## 📊 Monitoring & Analytics

### Enable Firebase Analytics
```dart
// Add to pubspec.yaml
firebase_analytics: ^latest_version

// Initialize
FirebaseAnalytics analytics = FirebaseAnalytics.instance;

// Log events
analytics.logEvent(
  name: 'tracking_added',
  parameters: {'tracking_id': id},
);
```

### Crashlytics
```dart
// Add to pubspec.yaml
firebase_crashlytics: ^latest_version

// Initialize
FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

// Log errors
FirebaseCrashlytics.instance.recordError(error, stackTrace);
```

## 🎯 Quick Tips

1. **Use hot reload**: Press 'r' in terminal for quick updates
2. **Use hot restart**: Press 'R' for full app restart
3. **Check logs**: Always monitor console output
4. **Format code**: Run `flutter format .` regularly
5. **Analyze code**: Run `flutter analyze` before committing
6. **Test on real device**: Emulators don't show all issues
7. **Use breakpoints**: Debug with VS Code debugger
8. **Profile performance**: Use DevTools for optimization

## 🆘 Emergency Commands

If everything breaks:
```bash
# Nuclear option - start fresh
flutter clean
rm -rf build/
rm -rf .dart_tool/
rm pubspec.lock
flutter pub get
flutter run
```

For Android issues:
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
```

For iOS issues (Mac only):
```bash
cd ios
pod deintegrate
pod install
cd ..
flutter clean
flutter pub get
```

---

**Keep this file handy for quick reference during development!** 🚀

**Pro Tip**: Bookmark this file and use Ctrl+F to quickly find commands you need!
