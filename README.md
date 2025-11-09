# Smart Parcel Drop Box System - Mobile Application

**An IoT-based parcel drop box system for secure contactless deliveries**

*Undergraduate Thesis Project*  
Cavite State University – Bacoor City Campus  
Bachelor of Science in Computer Science

## 📱 About

This mobile application is part of the Smart Parcel Drop Box System that integrates IoT technology with a user-friendly mobile interface to provide secure, contactless parcel delivery solutions.

### Team Members
- Bryan Bergonia
- Brant Yadi B. Cordova
- Raysan N. Perez

### Submission Date
June 2025

## 🎯 Features

### User Features
- **User Authentication**: Secure login and registration
- **Track Orders**: Register and monitor tracking IDs from shopping platforms
- **Real-Time Notifications**: Push notifications for delivery updates
- **Active Orders Dashboard**: View all pending and delivered parcels
- **Delivery History**: Access complete delivery logs
- **Profile Management**: Update personal information

### Security Features
- Firebase Authentication integration
- Secure data storage in Cloud Firestore
- Real-time synchronization between mobile app and IoT drop box
- Tamper-proof delivery verification

## 🛠️ Technology Stack

### Frontend
- **Framework**: Flutter
- **Language**: Dart
- **UI**: Material Design 3

### Backend Services
- **Authentication**: Firebase Authentication
- **Database**: Cloud Firestore
- **Push Notifications**: Firebase Cloud Messaging (FCM)
- **Cloud Platform**: Firebase (Google Cloud)

### Dependencies
```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^3.15.2
  firebase_auth: ^5.7.0
  cloud_firestore: ^5.6.12
  firebase_messaging: ^15.2.10
  cupertino_icons: ^1.0.8
```

## 📋 Prerequisites

Before you begin, ensure you have:

1. **Flutter SDK** installed (version 3.9.2 or higher)
2. **Android Studio** or **VS Code** with Flutter extensions
3. **Firebase Project** set up with:
   - Authentication enabled (Email/Password)
   - Cloud Firestore database created
   - Firebase Cloud Messaging configured
4. **Android Device** or **Emulator** for testing

## 🚀 Installation & Setup

### 1. Clone the Repository

```bash
git clone <repository-url>
cd smart_parcel_dropbox
```

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Firebase Configuration

The project already includes Firebase configuration:
- `android/app/google-services.json` - Android configuration
- `lib/config/firebase_options.dart` - Firebase options

**Note**: If you're setting up your own Firebase project, replace these files with your own configuration.

### 4. Run the Application

```bash
# Check connected devices
flutter devices

# Run on connected device/emulator
flutter run

# Run in release mode
flutter run --release
```

## 📁 Project Structure

```
lib/
├── config/
│   └── firebase_options.dart          # Firebase configuration
├── models/
│   ├── tracking_model.dart            # Tracking data model
│   └── user_model.dart                # User data model
├── screens/
│   ├── splash_screen.dart             # Initial loading screen
│   ├── login_screen.dart              # User login
│   ├── register_screen.dart           # User registration
│   ├── home_screen.dart               # Main dashboard
│   ├── add_tracking_screen.dart       # Add new tracking ID
│   └── tracking_details_screen.dart   # Parcel details & logs
├── services/
│   ├── auth_service.dart              # Authentication logic
│   ├── database_service.dart          # Firestore operations
│   └── notification_service.dart      # Push notifications
├── widgets/
│   └── (reusable UI components)
└── main.dart                          # Application entry point
```

## 🔥 Firebase Setup Guide

### Firestore Database Structure

```
users/
  {userId}/
    - uid: string
    - email: string
    - fullName: string
    - phoneNumber: string
    - address: string
    - role: string (user/courier)
    - createdAt: timestamp

tracking_ids/
  {trackingId}/
    - trackingId: string
    - userId: string
    - shopName: string
    - status: string (pending/in_transit/delivered/retrieved)
    - registeredAt: timestamp
    - expectedDeliveryDate: string
    - deliveredAt: timestamp
    - retrievedAt: timestamp

delivery_logs/
  {logId}/
    - trackingId: string
    - userId: string
    - eventType: string (scanned/door_opened/parcel_inserted/door_closed)
    - details: string
    - timestamp: timestamp
```

### Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users collection
    match /users/{userId} {
      allow read: if request.auth != null && request.auth.uid == userId;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Tracking IDs collection
    match /tracking_ids/{trackingId} {
      allow read: if request.auth != null && 
                     resource.data.userId == request.auth.uid;
      allow create: if request.auth != null;
      allow update: if request.auth != null;
    }
    
    // Delivery logs collection
    match /delivery_logs/{logId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null;
    }
  }
}
```

## 📱 How to Use

### For Recipients (End Users)

1. **Register**: Create an account with email, password, and personal details
2. **Login**: Sign in with your credentials
3. **Add Tracking ID**: 
   - Click the "Add Tracking ID" button
   - Enter your tracking number from the shopping platform
   - Add shop name and expected delivery date
4. **Monitor Deliveries**: View real-time status updates on your dashboard
5. **Receive Notifications**: Get push notifications when parcels are delivered
6. **View Details**: Tap on any order to see detailed delivery logs

### For Couriers

The courier interface will be integrated with the IoT drop box system to:
- Scan QR/barcode on parcels
- Verify tracking IDs against the database
- Trigger automatic notifications to recipients

## 🔧 Development

### Adding New Features

1. Create new models in `lib/models/`
2. Add services in `lib/services/`
3. Build UI screens in `lib/screens/`
4. Update Firebase security rules as needed

### Testing

```bash
# Run tests
flutter test

# Run widget tests
flutter test test/widget_test.dart
```

### Building for Release

```bash
# Android APK
flutter build apk --release

# Android App Bundle (for Play Store)
flutter build appbundle --release
```

## 🎓 Thesis Integration

This mobile application addresses the following thesis objectives:

1. ✅ **Secure Authentication**: Email/password authentication with Firebase
2. ✅ **Remote Access Control**: Real-time database synchronization
3. ✅ **Push Notifications**: Delivery status updates via FCM
4. ✅ **User-Friendly Interface**: Intuitive Material Design 3 UI
5. ✅ **Delivery Tracking**: Complete tracking ID management system
6. ✅ **Cloud-Based Storage**: AWS-compatible Firebase infrastructure

## 📊 System Requirements

### Minimum Requirements
- Android 5.0 (API level 21) or higher
- 2GB RAM
- 100MB free storage
- Internet connection (Wi-Fi or mobile data)

### Recommended
- Android 8.0 (API level 26) or higher
- 4GB RAM
- Stable internet connection

## 🔒 Security Considerations

- All authentication handled by Firebase Auth
- Passwords are never stored locally
- Data encrypted in transit (HTTPS)
- Firestore security rules prevent unauthorized access
- User data isolated per account

## 🐛 Troubleshooting

### Common Issues

**1. "FlutterFire not configured"**
```bash
# Solution: Firebase is already configured manually
# No action needed if firebase_options.dart exists
```

**2. "Build failed" errors**
```bash
flutter clean
flutter pub get
flutter run
```

**3. "Firebase connection issues"**
- Check internet connection
- Verify google-services.json is in android/app/
- Ensure Firebase project is active

**4. "Push notifications not working"**
- Check FCM configuration in Firebase Console
- Verify device has Google Play Services
- Test on physical device (not emulator)

## 📞 Support

For issues related to this thesis project, contact:

- Bryan Bergonia
- Brant Yadi B. Cordova
- Raysan N. Perez

**Institution**: Cavite State University – Bacoor City Campus  
**Department**: Computer Studies  
**Program**: BS Computer Science

## 📄 License

This project is developed as an undergraduate thesis and is subject to academic use restrictions.

## 🙏 Acknowledgments

- Cavite State University – Bacoor City Campus
- Department of Computer Studies
- Thesis advisors and panel members
- Flutter and Firebase communities

---

**Version**: 1.0.0  
**Last Updated**: November 2025  
**Status**: Development/Thesis Defense Phase
