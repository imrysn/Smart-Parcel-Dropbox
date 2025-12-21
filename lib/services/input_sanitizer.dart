import 'package:flutter/foundation.dart';

/// Input Sanitizer Service for security and data quality
/// Prevents XSS, SQL injection, and cleans user input
class InputSanitizer {
  /// Remove potentially harmful characters and normalize text
  static String sanitizeText(String input) {
    return input
        .trim()
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll(RegExp(r"[^\w\s@.\-,\']"),
            '') // Remove special chars except allowed
        .replaceAll(RegExp(r'\s+'), ' '); // Normalize whitespace
  }

  /// Sanitize email address
  static String sanitizeEmail(String email) {
    return email.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  /// Sanitize tracking ID (uppercase, alphanumeric with dash/underscore)
  static String sanitizeTrackingId(String trackingId) {
    return trackingId
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9\-_]'), '');
  }

  /// Sanitize phone number (keep only digits and +)
  static String sanitizePhone(String phone) {
    return phone.replaceAll(RegExp(r'[^\d+]'), '');
  }

  /// Sanitize shop name
  static String sanitizeShopName(String shopName) {
    return shopName
        .trim()
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r"[^\w\s\-&.,\']"), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Sanitize address
  static String sanitizeAddress(String address) {
    return address
        .trim()
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Check for SQL injection patterns
  static bool containsSqlInjection(String input) {
    final sqlPatterns = [
      RegExp(r"'.*--", caseSensitive: false),
      RegExp(
          r'(union|select|insert|update|delete|drop|create|alter|exec|execute|script|javascript|eval)',
          caseSensitive: false),
      RegExp(r'[;<>]'),
      RegExp(r'(/\*|\*/|@@|@)'),
    ];

    return sqlPatterns.any((pattern) => pattern.hasMatch(input));
  }

  /// Check for XSS patterns
  static bool containsXss(String input) {
    final xssPatterns = [
      RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false),
      RegExp(r'javascript:', caseSensitive: false),
      RegExp(r'on\w+\s*=', caseSensitive: false), // onclick=, onload=, etc.
      RegExp(r'<iframe', caseSensitive: false),
      RegExp(r'<object', caseSensitive: false),
      RegExp(r'<embed', caseSensitive: false),
    ];

    return xssPatterns.any((pattern) => pattern.hasMatch(input));
  }

  /// Validate safe input (no injection attempts)
  static String? validateSafeInput(String? value, {String? fieldName}) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    if (containsSqlInjection(value)) {
      return '${fieldName ?? 'Input'} contains invalid characters (SQL)';
    }

    if (containsXss(value)) {
      return '${fieldName ?? 'Input'} contains invalid characters (XSS)';
    }

    return null;
  }

  /// Escape HTML entities
  static String escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;')
        .replaceAll('/', '&#x2F;');
  }

  /// Sanitize for display (escape HTML)
  static String sanitizeForDisplay(String text) {
    return escapeHtml(sanitizeText(text));
  }

  /// Check if string length is within bounds
  static bool isValidLength(String text, {int min = 0, int max = 1000}) {
    return text.length >= min && text.length <= max;
  }

  /// Remove multiple spaces
  static String normalizeWhitespace(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Sanitize all fields in a map
  static Map<String, dynamic> sanitizeMap(Map<String, dynamic> data) {
    final sanitized = <String, dynamic>{};

    data.forEach((key, value) {
      if (value is String) {
        sanitized[key] = sanitizeText(value);
      } else {
        sanitized[key] = value;
      }
    });

    return sanitized;
  }

  /// Log sanitization attempt if dangerous patterns found
  static void logSuspiciousInput(String input, String source) {
    if (containsSqlInjection(input) || containsXss(input)) {
      debugPrint(
          '⚠️ SECURITY: Suspicious input detected from $source: ${input.substring(0, input.length > 50 ? 50 : input.length)}...');
    }
  }
}
