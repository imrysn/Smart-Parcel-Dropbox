# Smart Parcel Drop Box - Documentation

## Project Overview

Smart Parcel Drop Box is an IoT-based parcel delivery system designed for contactless deliveries. This Flutter application serves as the mobile client for users to track their parcels, receive notifications, and interact with the smart dropbox system.

**Key Features:**
- User authentication (Email/Password and Google Sign-In)
- Parcel tracking and status updates
- Real-time notifications
- Scan logs and delivery history
- User profile management
- Responsive UI with Material Design 3

## Architecture

### Project Structure

```
lib/
├── config/                 # Firebase configuration
│   ├── firebase_options.dart
│   └── firebase_options.dart.template
├── models/                 # Data models
│   ├── notification_model.dart
│   ├── scan_log_model.dart
│   ├── tracking_model.dart
│   └── user_model.dart
├── screens/                # UI screens
│   ├── add_tracking_screen.dart
│   ├── home_screen.dart
│   ├── login_screen.dart
│   ├── logs_screen.dart
│   ├── notifications_screen.dart
│   ├── register_screen.dart
│   ├── splash_screen.dart
│   └── tracking_details_screen.dart
├── services/               # Business logic and external integrations
│   ├── auth_service.dart
│   ├── database_service.dart
│   ├── error_handler.dart
│   ├── google_auth_service.dart
│   ├── input_validator.dart
│   ├── notification_service.dart
│   └── widgets/            # Reusable UI components (empty)
└── main.dart               # Application entry point
```

### Technology Stack

- **Framework:** Flutter 3.2.0+
- **Language:** Dart
- **Backend:** Firebase (Authentication, Firestore, Cloud Messaging)
- **State Management:** Basic setState with Streams
- **UI:** Material Design 3
- **Platform:** Android (primary), iOS support

### Design Patterns

- **Service Layer Pattern:** Separation of business logic into dedicated service classes
- **Repository Pattern:** Data access abstracted through DatabaseService
- **Observer Pattern:** Stream-based reactive UI updates
- **Factory Pattern:** Model creation from Firestore data

## Core Components

### Authentication System

**AuthService (`lib/services/auth_service.dart`)**
- Handles email/password authentication
- User registration with profile creation
- Password reset functionality
- Firebase Auth integration

**GoogleAuthService (`lib/services/google_auth_service.dart`)**
- Google Sign-In integration
- Automatic user document creation for new users
- Seamless authentication flow

### Database Layer

**DatabaseService (`lib/services/database_service.dart`)**
- Firestore CRUD operations
- Stream-based real-time data updates
- Complex queries for tracking and logs
- Notification management

**Key Collections:**
- `users` - User profiles and authentication data
- `tracking_ids` - Parcel tracking information
- `delivery_logs` - Delivery event history
- `scan_logs` - QR/barcode scan attempts
- `notifications` - In-app notifications

### Notification System

**NotificationService (`lib/services/notification_service.dart`)**
- Firebase Cloud Messaging integration
- Push notification permissions handling
- Background message processing
- Device token management

### Validation and Error Handling

**InputValidator (`lib/services/input_validator.dart`)**
- Comprehensive input validation
- Email, phone, address, and tracking ID validation
- Security-focused input sanitization

**ErrorHandler (`lib/services/error_handler.dart`)**
- Centralized error handling
- Consistent error messaging
- Performance monitoring hooks

### Data Models

**TrackingModel**
- Represents parcel tracking information
- Status management (pending, in_transit, delivered, retrieved)
- Firestore serialization/deserialization

**ScanLogModel**
- Records all dropbox scan attempts
- Access control logging
- Timestamp and user association

**NotificationModel**
- In-app notification structure
- Type-based categorization
- Read status tracking

**UserModel**
- User profile data
- Role-based permissions (user/courier)

## User Interface

### Screen Flow

```
Splash Screen → Login/Register → Home Screen
                      ↓
              Add Tracking → Tracking Details
                      ↓
           Notifications ← Logs Screen
```

### Key Screens

**SplashScreen**
- Brand display and loading animation
- Authentication state check
- Smooth transition to main app

**LoginScreen**
- Email/password authentication
- Google Sign-In option
- Password reset functionality

**HomeScreen**
- Dashboard with active orders
- Bottom navigation (Home, Logs, Profile)
- Real-time order status updates

**TrackingDetailsScreen**
- Detailed parcel information
- Delivery timeline
- Status-specific actions

**AddTrackingScreen**
- New parcel registration
- Shop and date input
- Validation and submission

## Setup and Installation

### Prerequisites

- Flutter SDK 3.2.0 or higher
- Dart SDK 3.0.0 or higher
- Android Studio or VS Code with Flutter extensions
- Firebase project with Authentication, Firestore, and Cloud Messaging enabled

### Firebase Configuration

1. Create a Firebase project at https://console.firebase.google.com/
2. Enable Authentication with Email/Password and Google providers
3. Enable Firestore database
4. Enable Cloud Messaging
5. Generate Firebase configuration files
6. Replace `lib/config/firebase_options.dart.template` with actual configuration

### Installation Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/imrysn/Smart-Parcel-Dropbox.git
   cd smart_parcel_dropbox
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Configure Firebase:
   - Copy `firebase_options.dart.template` to `firebase_options.dart`
   - Add your Firebase project configuration

4. Run the app:
   ```bash
   flutter run
   ```

### Build Configuration

**Android:**
- Minimum SDK: API 21 (Android 5.0)
- Target SDK: API 34 (Android 14)
- Google Play Services required

**iOS:**
- Minimum iOS version: 11.0
- Push notifications capability required

## API Reference

### Authentication APIs

#### AuthService.signInWithEmailAndPassword
```dart
Future<UserCredential?> signInWithEmailAndPassword({
  required String email,
  required String password,
})
```

#### AuthService.registerWithEmailAndPassword
```dart
Future<UserCredential?> registerWithEmailAndPassword({
  required String email,
  required String password,
  required String fullName,
  required String phoneNumber,
  required String address,
})
```

### Database APIs

#### DatabaseService.registerTrackingId
```dart
Future<void> registerTrackingId({
  required String userId,
  required String trackingId,
  required String shopName,
  String? expectedDeliveryDate,
})
```

#### DatabaseService.getUserTrackingIds
```dart
Stream<List<TrackingModel>> getUserTrackingIds(String userId)
```

### Notification APIs

#### DatabaseService.createNotification
```dart
Future<void> createNotification({
  required String userId,
  required String type,
  required String title,
  required String message,
  String? trackingId,
  Map<String, dynamic>? data,
})
```

## Data Flow

### Parcel Registration Flow

1. User enters tracking ID and shop details
2. InputValidator validates the data
3. DatabaseService creates tracking document in Firestore
4. NotificationService sends confirmation notification
5. UI updates to show new tracking item

### Delivery Update Flow

1. IoT device scans QR code
2. Scan logged in `scan_logs` collection
3. If valid, tracking status updated
4. Notification sent to user
5. Real-time UI updates via streams

### Authentication Flow

1. User provides credentials
2. AuthService validates and authenticates
3. User document created/updated in Firestore
4. Navigation to home screen
5. Auth state streams update UI

## Security Considerations

- Firebase Authentication handles user identity securely
- All data transmission encrypted via HTTPS
- Input validation prevents injection attacks
- User-specific data isolation in Firestore
- API keys are client-side public (standard for Firebase)

## Performance Optimization

- Stream-based real-time updates minimize polling
- Efficient Firestore queries with proper indexing
- Lazy loading of data where appropriate
- Optimized widget rebuilds with proper key usage
- Background message handling for notifications

## Testing

### Unit Tests
- Service layer testing with mock Firebase services
- Model serialization/deserialization
- Input validation logic

### Widget Tests
- UI component testing
- Navigation flow testing
- Form validation testing

### Integration Tests
- End-to-end authentication flows
- Database operations
- Notification handling

## Deployment

### Android APK Generation
```bash
flutter build apk --release
```

### iOS App Store Build
```bash
flutter build ios --release
```

### Firebase Configuration for Production
- Update Firebase security rules
- Configure Firestore indexes
- Set up Cloud Functions if needed
- Enable App Check for additional security

## Maintenance

### Regular Tasks
- Update Flutter and Firebase dependencies
- Monitor Firestore performance
- Review and update security rules
- Backup user data and configurations

### Monitoring
- Firebase Crashlytics for error tracking
- Firebase Analytics for user behavior
- Performance monitoring for database queries

## Contributing

### Code Style
- Follow Flutter's effective Dart guidelines
- Use meaningful variable and method names
- Add documentation comments for public APIs
- Maintain consistent formatting with `flutter format`

### Git Workflow
- Feature branches for new development
- Pull requests for code review
- Semantic commit messages
- Regular rebasing with main branch

## Troubleshooting

### Common Issues

**Firebase Configuration Errors**
- Verify `firebase_options.dart` contains correct project configuration
- Check Firebase project settings match the app configuration

**Authentication Issues**
- Ensure Firebase Authentication is enabled in console
- Verify OAuth redirect URIs for Google Sign-In

**Database Connection Issues**
- Check Firestore security rules allow necessary operations
- Verify network connectivity and Firebase project status

**Notification Problems**
- Confirm FCM configuration in Firebase console
- Check device notification permissions

### Debug Mode
- Enable debug logging in services
- Use Flutter DevTools for performance profiling
- Check Firebase console for backend errors

## License

This project is part of an Undergraduate Thesis at Cavite State University - Bacoor Campus.

## Contact

For technical support or questions about this project, please refer to the thesis documentation or contact the development team.
