/// Input Validation Service - Comprehensive validation for all user inputs
class InputValidator {
  /// Validate email format and basic rules
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }

    // Check for spaces
    if (value.contains(' ')) {
      return 'Email address cannot contain spaces';
    }

    final email = value.trim();

    // Basic email regex
    final emailRegex =
        RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      return 'Please enter a valid email address';
    }

    // Length checks
    if (email.length < 5) {
      return 'Email must be at least 5 characters long';
    }

    if (email.length > 254) {
      return 'Email address is too long';
    }

    // Check for multiple @ symbols
    if (email.split('@').length > 2) {
      return 'Invalid email format';
    }

    return null;
  }

  /// Validate full name
  static String? validateFullName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Full name is required';
    }

    final name = value.trim();

    // Length checks
    if (name.length < 2) {
      return 'Full name must be at least 2 characters long';
    }

    if (name.length > 100) {
      return 'Full name is too long';
    }

    // Check for valid characters (letters, spaces, hyphens, apostrophes)
    final nameRegex = RegExp(r"^[a-zA-Z\s\-']+$");
    if (!nameRegex.hasMatch(name)) {
      return 'Full name can only contain letters, spaces, hyphens, and apostrophes';
    }

    // Check for reasonable word count (1-5 words)
    final words =
        name.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    if (words.length < 1) {
      return 'Please enter a valid full name';
    }

    if (words.length > 5) {
      return 'Full name seems too long';
    }

    return null;
  }

  /// Validate phone number
  static String? validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }

    final phone =
        value.replaceAll(RegExp(r'[^\d]'), ''); // Remove all non-digits

    // Philippine phone number validation (basic)
    if (phone.startsWith('09')) {
      if (phone.length != 11) {
        return 'Philippine mobile number must be 11 digits';
      }
    } else if (phone.startsWith('639')) {
      if (phone.length != 12) {
        return 'Philippine mobile number must be 12 digits';
      }
    } else {
      // Landline or other international
      if (phone.length < 7 || phone.length > 15) {
        return 'Phone number length is invalid';
      }
    }

    // Check if original input has at least some digits
    if (!RegExp(r'\d').hasMatch(value)) {
      return 'Phone number must contain digits';
    }

    return null;
  }

  /// Validate address
  static String? validateAddress(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Address is required';
    }

    final address = value.trim();

    // Length checks
    if (address.length < 10) {
      return 'Please provide a more complete address';
    }

    if (address.length > 500) {
      return 'Address is too long';
    }

    // Check for basic address elements (at least one number and one letter)
    if (!RegExp(r'\d').hasMatch(address)) {
      return 'Address should include a house/building number';
    }

    if (!RegExp(r'[a-zA-Z]').hasMatch(address)) {
      return 'Address should include street/place names';
    }

    return null;
  }

  /// Validate tracking ID format
  static String? validateTrackingId(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Tracking ID is required';
    }

    final trackingId = value.trim();

    // Length checks
    if (trackingId.length < 6) {
      return 'Tracking ID must be at least 6 characters long';
    }

    if (trackingId.length > 50) {
      return 'Tracking ID is too long';
    }

    // Check for valid characters (alphanumeric, hyphens, underscores)
    final trackingRegex = RegExp(r'^[a-zA-Z0-9\-_]+$');
    if (!trackingRegex.hasMatch(trackingId)) {
      return 'Tracking ID can only contain letters, numbers, hyphens, and underscores';
    }

    return null;
  }

  /// Validate shop/platform name
  static String? validateShopName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Shop/Platform name is required';
    }

    final shopName = value.trim();

    // Length checks
    if (shopName.length < 2) {
      return 'Shop name must be at least 2 characters long';
    }

    if (shopName.length > 100) {
      return 'Shop name is too long';
    }

    // Check for valid characters
    final shopRegex = RegExp(r"^[a-zA-Z0-9\s\-&.,']+$");
    if (!shopRegex.hasMatch(shopName)) {
      return 'Shop name contains invalid characters';
    }

    return null;
  }

  /// Validate password
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    if (value.length < 6) {
      return 'Password must be at least 6 characters long';
    }

    if (value.length > 128) {
      return 'Password is too long';
    }

    return null;
  }

  /// Validate required field
  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  /// Sanitize input by trimming and removing extra whitespace
  static String sanitizeInput(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Check if input contains potentially harmful characters
  static String? validateSafeInput(String? value,
      {bool allowSpecialChars = false}) {
    if (value == null) return null;

    final input = value.trim();

    if (allowSpecialChars) {
      // Allow common special characters but prevent script injection
      if (RegExp(r'[<>]').hasMatch(input)) {
        return 'Input contains invalid characters';
      }
    } else {
      // Strict validation
      if (!RegExp(r'^[a-zA-Z0-9\s\-_.]+$').hasMatch(input)) {
        return 'Input contains invalid characters';
      }
    }

    return null;
  }
}
