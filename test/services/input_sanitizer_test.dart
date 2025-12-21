import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parcel_dropbox/services/input_sanitizer.dart';

void main() {
  group('InputSanitizer.sanitizeText', () {
    test('should remove HTML tags', () {
      expect(
        InputSanitizer.sanitizeText('<script>alert("test")</script>'),
        'alerttest',
      );
      expect(
        InputSanitizer.sanitizeText('Hello <b>World</b>'),
        'Hello World',
      );
    });
    
    test('should trim whitespace', () {
      expect(InputSanitizer.sanitizeText('  test  '), 'test');
    });
    
    test('should normalize multiple spaces', () {
      expect(InputSanitizer.sanitizeText('test    test'), 'test test');
    });
    
    test('should remove special characters', () {
      expect(InputSanitizer.sanitizeText('test!@#\$%'), 'test');
      expect(InputSanitizer.sanitizeText('hello;world'), 'helloworld');
    });
  });
  
  group('InputSanitizer.sanitizeEmail', () {
    test('should convert to lowercase', () {
      expect(
        InputSanitizer.sanitizeEmail('TEST@EXAMPLE.COM'),
        'test@example.com',
      );
    });
    
    test('should remove spaces', () {
      expect(
        InputSanitizer.sanitizeEmail(' test@example.com '),
        'test@example.com',
      );
    });
  });
  
  group('InputSanitizer.sanitizeTrackingId', () {
    test('should convert to uppercase', () {
      expect(
        InputSanitizer.sanitizeTrackingId('track123'),
        'TRACK123',
      );
    });
    
    test('should remove invalid characters', () {
      expect(
        InputSanitizer.sanitizeTrackingId('track@123#'),
        'TRACK123',
      );
    });
    
    test('should keep hyphens and underscores', () {
      expect(
        InputSanitizer.sanitizeTrackingId('track-123_456'),
        'TRACK-123_456',
      );
    });
  });
  
  group('InputSanitizer.sanitizePhone', () {
    test('should keep only digits and plus', () {
      expect(
        InputSanitizer.sanitizePhone('(0912) 345-6789'),
        '09123456789',
      );
      expect(
        InputSanitizer.sanitizePhone('+63 912 345 6789'),
        '+639123456789',
      );
    });
  });
  
  group('InputSanitizer.containsSqlInjection', () {
    test('should detect SQL injection patterns', () {
      expect(
        InputSanitizer.containsSqlInjection("'; DROP TABLE users; --"),
        true,
      );
      expect(
        InputSanitizer.containsSqlInjection('SELECT * FROM users'),
        true,
      );
      expect(
        InputSanitizer.containsSqlInjection('1 UNION SELECT password'),
        true,
      );
    });
    
    test('should not flag normal text', () {
      expect(
        InputSanitizer.containsSqlInjection('Hello World'),
        false,
      );
      expect(
        InputSanitizer.containsSqlInjection('test@example.com'),
        false,
      );
    });
  });
  
  group('InputSanitizer.containsXss', () {
    test('should detect XSS patterns', () {
      expect(
        InputSanitizer.containsXss('<script>alert("xss")</script>'),
        true,
      );
      expect(
        InputSanitizer.containsXss('javascript:alert("xss")'),
        true,
      );
      expect(
        InputSanitizer.containsXss('<img src=x onerror=alert("xss")>'),
        true,
      );
      expect(
        InputSanitizer.containsXss('<iframe src="malicious.com">'),
        true,
      );
    });
    
    test('should not flag normal HTML-like text', () {
      expect(
        InputSanitizer.containsXss('My email is <user@example.com>'),
        false,
      );
      expect(
        InputSanitizer.containsXss('Price: \$10 < \$20'),
        false,
      );
    });
  });
  
  group('InputSanitizer.validateSafeInput', () {
    test('should pass safe input', () {
      expect(
        InputSanitizer.validateSafeInput('Hello World'),
        null,
      );
      expect(
        InputSanitizer.validateSafeInput('test@example.com'),
        null,
      );
    });
    
    test('should detect SQL injection', () {
      expect(
        InputSanitizer.validateSafeInput("'; DROP TABLE users; --"),
        isNotNull,
      );
      expect(
        InputSanitizer.validateSafeInput("'; DROP TABLE users; --"),
        contains('SQL'),
      );
    });
    
    test('should detect XSS', () {
      expect(
        InputSanitizer.validateSafeInput('<script>alert("xss")</script>'),
        isNotNull,
      );
      expect(
        InputSanitizer.validateSafeInput('<script>alert("xss")</script>'),
        contains('XSS'),
      );
    });
    
    test('should handle null/empty input', () {
      expect(InputSanitizer.validateSafeInput(null), null);
      expect(InputSanitizer.validateSafeInput(''), null);
      expect(InputSanitizer.validateSafeInput('   '), null);
    });
  });
  
  group('InputSanitizer.escapeHtml', () {
    test('should escape HTML entities', () {
      expect(InputSanitizer.escapeHtml('<script>'), '&lt;script&gt;');
      expect(InputSanitizer.escapeHtml('&'), '&amp;');
      expect(InputSanitizer.escapeHtml('"'), '&quot;');
      expect(InputSanitizer.escapeHtml("'"), '&#x27;');
    });
  });
  
  group('InputSanitizer.isValidLength', () {
    test('should validate length', () {
      expect(InputSanitizer.isValidLength('test', min: 2, max: 10), true);
      expect(InputSanitizer.isValidLength('a', min: 2, max: 10), false);
      expect(InputSanitizer.isValidLength('a' * 11, min: 2, max: 10), false);
    });
  });
  
  group('InputSanitizer.sanitizeMap', () {
    test('should sanitize all string values in map', () {
      final input = {
        'name': '  John  ',
        'email': '<b>test@example.com</b>',
        'age': 25,
      };
      
      final sanitized = InputSanitizer.sanitizeMap(input);
      
      expect(sanitized['name'], 'John');
      expect(sanitized['email'], 'testexample.com');
      expect(sanitized['age'], 25);
    });
  });
}
