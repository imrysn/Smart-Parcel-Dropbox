import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parcel_dropbox/services/input_validator.dart';

void main() {
  group('InputValidator.validateEmail', () {
    test('should accept valid emails', () {
      expect(InputValidator.validateEmail('test@example.com'), null);
      expect(InputValidator.validateEmail('user.name@example.co.uk'), null);
      expect(InputValidator.validateEmail('user+tag@example.com'), null);
      expect(InputValidator.validateEmail('test123@gmail.com'), null);
      expect(InputValidator.validateEmail('a@b.co'), null);
    });
    
    test('should reject invalid emails', () {
      expect(InputValidator.validateEmail('notanemail'), isNotNull);
      expect(InputValidator.validateEmail('test@'), isNotNull);
      expect(InputValidator.validateEmail('@example.com'), isNotNull);
      expect(InputValidator.validateEmail('test@domain'), isNotNull);
      expect(InputValidator.validateEmail(''), isNotNull);
      expect(InputValidator.validateEmail(null), isNotNull);
    });
    
    test('should reject emails with spaces', () {
      expect(InputValidator.validateEmail('test @example.com'), isNotNull);
      expect(InputValidator.validateEmail('test@ example.com'), isNotNull);
      expect(InputValidator.validateEmail(' test@example.com'), isNotNull);
    });
    
    test('should reject emails with multiple @ symbols', () {
      expect(InputValidator.validateEmail('test@@example.com'), isNotNull);
      expect(InputValidator.validateEmail('test@test@example.com'), isNotNull);
    });
    
    test('should reject emails that are too long', () {
      final longEmail = 'a' * 300 + '@example.com';
      expect(InputValidator.validateEmail(longEmail), isNotNull);
    });
  });
  
  group('InputValidator.validatePhone', () {
    test('should accept valid Philippine mobile numbers', () {
      expect(InputValidator.validatePhone('09123456789'), null);
      expect(InputValidator.validatePhone('+639123456789'), null);
      expect(InputValidator.validatePhone('639123456789'), null);
    });
    
    test('should accept formatted phone numbers', () {
      expect(InputValidator.validatePhone('0912-345-6789'), null);
      expect(InputValidator.validatePhone('(0912) 345-6789'), null);
      expect(InputValidator.validatePhone('+63 912 345 6789'), null);
    });
    
    test('should reject invalid phone numbers', () {
      expect(InputValidator.validatePhone('123'), isNotNull);
      expect(InputValidator.validatePhone(''), isNotNull);
      expect(InputValidator.validatePhone(null), isNotNull);
      expect(InputValidator.validatePhone('abcdefghijk'), isNotNull);
    });
    
    test('should reject too short numbers', () {
      expect(InputValidator.validatePhone('091234'), isNotNull);
    });
  });
  
  group('InputValidator.validateFullName', () {
    test('should accept valid names', () {
      expect(InputValidator.validateFullName('John Doe'), null);
      expect(InputValidator.validateFullName('Maria Santos'), null);
      expect(InputValidator.validateFullName("O'Brien"), null);
      expect(InputValidator.validateFullName('Jean-Pierre'), null);
      expect(InputValidator.validateFullName('Juan dela Cruz'), null);
    });
    
    test('should reject invalid names', () {
      expect(InputValidator.validateFullName('A'), isNotNull);
      expect(InputValidator.validateFullName(''), isNotNull);
      expect(InputValidator.validateFullName(null), isNotNull);
      expect(InputValidator.validateFullName('123'), isNotNull);
      expect(InputValidator.validateFullName('John@Doe'), isNotNull);
    });
    
    test('should reject names that are too long', () {
      final longName = 'A' * 101;
      expect(InputValidator.validateFullName(longName), isNotNull);
    });
  });
  
  group('InputValidator.validateAddress', () {
    test('should accept valid addresses', () {
      expect(InputValidator.validateAddress('123 Main St, City'), null);
      expect(InputValidator.validateAddress('Unit 4B, Building A, Street 123'), null);
      expect(InputValidator.validateAddress('P.O. Box 1234'), null);
    });
    
    test('should reject invalid addresses', () {
      expect(InputValidator.validateAddress('123'), isNotNull); // Too short
      expect(InputValidator.validateAddress(''), isNotNull);
      expect(InputValidator.validateAddress(null), isNotNull);
      expect(InputValidator.validateAddress('NoNumber'), isNotNull); // No number
    });
    
    test('should reject addresses that are too long', () {
      final longAddress = 'A' * 501;
      expect(InputValidator.validateAddress(longAddress), isNotNull);
    });
  });
  
  group('InputValidator.validateTrackingId', () {
    test('should accept valid tracking IDs', () {
      expect(InputValidator.validateTrackingId('TRACK123'), null);
      expect(InputValidator.validateTrackingId('TEST-456'), null);
      expect(InputValidator.validateTrackingId('ABC_XYZ_123'), null);
      expect(InputValidator.validateTrackingId('SHOPEE123456'), null);
    });
    
    test('should reject invalid tracking IDs', () {
      expect(InputValidator.validateTrackingId('12345'), isNotNull); // Too short
      expect(InputValidator.validateTrackingId(''), isNotNull);
      expect(InputValidator.validateTrackingId(null), isNotNull);
      expect(InputValidator.validateTrackingId('TEST@123'), isNotNull); // Invalid char
      expect(InputValidator.validateTrackingId('TEST 123'), isNotNull); // Space
    });
    
    test('should reject tracking IDs that are too long', () {
      final longId = 'A' * 51;
      expect(InputValidator.validateTrackingId(longId), isNotNull);
    });
  });
  
  group('InputValidator.validateShopName', () {
    test('should accept valid shop names', () {
      expect(InputValidator.validateShopName('Shopee'), null);
      expect(InputValidator.validateShopName('Lazada Philippines'), null);
      expect(InputValidator.validateShopName("McDonald's"), null);
      expect(InputValidator.validateShopName('7-Eleven'), null);
      expect(InputValidator.validateShopName('A&W'), null);
    });
    
    test('should reject invalid shop names', () {
      expect(InputValidator.validateShopName('A'), isNotNull); // Too short
      expect(InputValidator.validateShopName(''), isNotNull);
      expect(InputValidator.validateShopName(null), isNotNull);
    });
  });
  
  group('InputValidator.sanitizeInput', () {
    test('should trim whitespace', () {
      expect(InputValidator.sanitizeInput('  test  '), 'test');
      expect(InputValidator.sanitizeInput('test   test'), 'test test');
    });
    
    test('should normalize multiple spaces', () {
      expect(InputValidator.sanitizeInput('test    test'), 'test test');
    });
  });
}
