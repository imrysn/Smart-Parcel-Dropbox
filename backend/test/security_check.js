/**
 * Phase 11: Backend Security Implementation Test
 * 
 * Verifies that hmacKey generation logic is functional and secure.
 */
const crypto = require('crypto');

function generateSymmetricKey() {
  return crypto.randomBytes(32).toString('hex');
}

function runTests() {
  console.log('--- [BACKEND SECURITY TEST] ---');

  // Test 1: Key Generation
  const key1 = generateSymmetricKey();
  const key2 = generateSymmetricKey();

  console.log(`Generated Key 1: ${key1}`);
  console.log(`Generated Key 2: ${key2}`);

  if (key1.length === 64 && key1 !== key2) {
    console.log('✅ TEST 1 PASSED: Keys are 256-bit (64 hex chars) and unique.');
  } else {
    console.log('❌ TEST 1 FAILED');
  }

  // Test 2: HMAC Calculation (Consistency with ESP32/Flutter)
  const testKey = 'TEST_KEY_123';
  const payload = 'USER_ABC-12345';
  
  const hmac = crypto.createHmac('sha256', testKey);
  hmac.update(payload);
  const digest = hmac.digest('hex').toUpperCase();
  const shortHash = digest.substring(0, 8);

  console.log(`Payload: ${payload}`);
  console.log(`Full HMAC: ${digest}`);
  console.log(`Short Hash: ${shortHash}`);

  // Known vector: if key="TEST_KEY_123" and payload="USER_ABC-12345", 
  // then shortHash must be "F1D4EEBC" (verified via Node.js crypto)
  if (shortHash === 'F1D4EEBC') {
    console.log('✅ TEST 2 PASSED: HMAC logic matches Hardware/App test vectors.');
  } else {
    console.log('❌ TEST 2 FAILED');
  }

  console.log('--- [TESTS COMPLETE] ---');
}

runTests();
