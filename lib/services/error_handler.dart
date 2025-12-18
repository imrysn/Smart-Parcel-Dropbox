import 'package:flutter/foundation.dart';

/// Centralized Error Handling Service
/// Provides consistent error handling across the application
class ErrorHandler {
  /// Handle and log errors consistently
  static void handleError(Object error,
      [StackTrace? stackTrace, String? context]) {
    String errorMessage = _parseError(error);

    if (context != null) {
      debugPrint('[$context] Error: $errorMessage');
    } else {
      debugPrint('Error: $errorMessage');
    }

    if (stackTrace != null && kDebugMode) {
      debugPrint('StackTrace: $stackTrace');
    }
  }

  /// Parse error objects into readable strings
  static String _parseError(Object error) {
    if (error is String) {
      return error;
    } else if (error.toString().contains('Exception:')) {
      return error.toString().split('Exception: ')[1];
    } else {
      return error.toString();
    }
  }

  /// Handle Firebase errors specifically
  static String handleFirebaseError(Object error) {
    String errorMessage = error.toString().toLowerCase();

    // Check for common Firebase error patterns
    if (errorMessage.contains('permission-denied')) {
      return 'Access denied. Please check your permissions.';
    } else if (errorMessage.contains('not-found')) {
      return 'The requested data was not found.';
    } else if (errorMessage.contains('already-exists')) {
      return 'This item already exists.';
    } else if (errorMessage.contains('failed-precondition')) {
      return 'Operation failed. Please try again.';
    } else if (errorMessage.contains('unavailable')) {
      return 'Service temporarily unavailable. Please check your connection.';
    } else {
      return 'An unexpected error occurred. Please try again.';
    }
  }

  /// Log performance metrics
  static void logPerformance(String operation, Duration duration) {
    debugPrint('$operation took ${duration.inMilliseconds}ms');
  }

  /// Validate password strength
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    if (value.length < 8) {
      return 'Password must be at least 8 characters long';
    }

    // Check for at least one uppercase letter
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }

    // Check for at least one lowercase letter
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }

    // Check for at least one digit
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain at least one number';
    }

    return null;
  }
}
