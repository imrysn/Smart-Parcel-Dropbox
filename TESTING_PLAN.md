# 🧪 Comprehensive Testing Plan - Smart Parcel Drop Box

## Testing Strategy Overview

This document provides a systematic approach to test all functionality after the recent bug fixes and optimizations.

---

## Test Environment Setup

### Prerequisites
```bash
# Clean build
flutter clean
flutter pub get

# Run on multiple devices
flutter devices

# Start app in debug mode
flutter run --debug

# For verbose logging
flutter run --verbose
```

### Test Devices
- [ ] Android Emulator (API 30+)
- [ ] Physical Android Device
- [ ] iOS Simulator (if available)
- [ ] Different screen sizes

---

## Phase 1: Critical Path Testing (Priority 1)

### 1.1 Authentication Flow ⭐⭐⭐

#### Test Case 1.1.1: Email Registration
**Objective:** Verify new users can register with email/password

**Steps:**
1. Open app → Should show splash screen
2. Wait for splash → Should navigate to Login screen
3. Tap "Register" button
4. Fill in registration form:
   - Full Name: "Test User"
   - Email: "test123@example.com"
   - Phone: "09123456789"
   - Address: "123 Test St, Bacoor, Cavite"
   - Password: "TestPass123!"
   - Confirm Password: "TestPass123!"
5. Tap "Register" button

**Expected Results:**
- ✅ Form validates all fields correctly
- ✅ Loading indicator shows during registration
- ✅ User document created in Firestore with ALL fields:
  - uid, email, fullName, phoneNumber, address, createdAt, role, trackingNumbers[]
- ✅ Navigates to Home Screen
- ✅ User is authenticated

**Pass Criteria:**
- [ ] Registration successful
- [ ] All fields saved in Firestore
- [ ] trackingNumbers field exists and is empty array
- [ ] No errors in console

**Verification:**
```bash
# Check Firestore Console
# Navigate to: users collection → [new user uid]
# Verify: trackingNumbers: [] exists
```

---

#### Test Case 1.1.2: Email Login
**Objective:** Verify existing users can login

**Steps:**
1. If logged in, logout first
2. On Login screen, enter credentials:
   - Email: "test123@example.com"
   - Password: "TestPass123!"
3. Tap "Login" button

**Expected Results:**
- ✅ Loading indicator shows
- ✅ Authentication succeeds
- ✅ Navigates to Home Screen
- ✅ User data loads correctly

**Pass Criteria:**
- [ ] Login successful
- [ ] Home screen displays
- [ ] Profile tab shows user info
- [ ] No errors in console

---

#### Test Case 1.1.3: Google Sign-In
**Objective:** Verify Google authentication works

**Steps:**
1. On Login screen, tap "Continue with Google"
2. Select Google account
3. Authorize app

**Expected Results:**
- ✅ Google sign-in dialog appears
- ✅ User can select account
- ✅ If new user, creates document with trackingNumbers[]
- ✅ Navigates to Home Screen
- ✅ No errors in console (should use debugPrint)

**Pass Criteria:**
- [ ] Google sign-in successful
- [ ] User document consistent with email registration
- [ ] No print() statements in logs (should be debugPrint)
- [ ] Profile displays Google info

---

#### Test Case 1.1.4: Email Validation
**Objective:** Verify improved email validation

**Test Invalid Emails:**
- "notanemail" → Should show error
- "test@" → Should show error
- "test@domain" → Should show error
- "@domain.com" → Should show error
- "test @domain.com" → Should show error

**Test Valid Emails:**
- "test@example.com" → Should accept
- "user.name@example.co.uk" → Should accept
- "user+tag@example.com" → Should accept

**Pass Criteria:**
- [ ] All invalid emails rejected
- [ ] All valid emails accepted
- [ ] Clear error messages shown
- [ ] Validation works in login AND register

---

#### Test Case 1.1.5: Forgot Password
**Objective:** Verify password reset works

**Steps:**
1. On Login screen, tap "Forgot Password?"
2. Enter email: "test123@example.com"
3. Tap "Send Reset Link"

**Expected Results:**
- ✅ Email validation works (using InputValidator)
- ✅ Success message shown
- ✅ Password reset email sent (check email)
- ✅ Dialog closes

**Pass Criteria:**
- [ ] Email validated properly
- [ ] Success snackbar shown
- [ ] Reset email received
- [ ] No errors

---

### 1.2 Auth State Reactivity ⭐⭐⭐

#### Test Case 1.2.1: Logout Updates UI
**Objective:** Verify UI updates immediately on logout

**Steps:**
1. Login to app
2. Navigate to Home → Orders tab
3. Tap logout button in app bar
4. Confirm logout

**Expected Results:**
- ✅ Confirmation dialog appears
- ✅ After confirming, navigates to Login screen
- ✅ If you try to go back, stays on Login screen

**Pass Criteria:**
- [ ] Smooth logout flow
- [ ] No crashes
- [ ] No cached user data shown

---

#### Test Case 1.2.2: Auth State Change in Home Screen
**Objective:** Verify Home Screen reacts to auth changes

**Setup:** Need two test accounts or ability to force logout

**Steps:**
1. Login to app
2. Navigate to Home → Orders tab (should show user's orders)
3. Navigate to Profile tab (should show user info)
4. Force logout from another device OR use Firebase Console
5. Interact with app (pull to refresh, switch tabs)

**Expected Results:**
- ✅ Orders tab updates to show "Not logged in"
- ✅ Profile tab updates to show "Not logged in"
- ✅ No crash or error
- ✅ UI is responsive

**Pass Criteria:**
- [ ] UI updates automatically
- [ ] No error messages
- [ ] Graceful handling

**Note:** This uses the new StreamBuilder<User?> with authStateChanges

---

### 1.3 Home Screen Functionality ⭐⭐⭐

#### Test Case 1.3.1: Active Orders Display
**Objective:** Verify orders load and display correctly

**Prerequisites:** Have at least one tracking ID registered

**Steps:**
1. Login to app
2. Observe Home → Orders tab

**Expected Results:**
- ✅ Loading indicator shows initially
- ✅ Orders load from Firestore
- ✅ Each order card shows:
  - Shop name
  - Tracking ID
  - Status badge (with correct color)
  - Expected delivery date (if set)
- ✅ Tap order → navigates to details

**Pass Criteria:**
- [ ] Orders load successfully
- [ ] Status colors correct (pending=orange, in_transit=blue, delivered=green)
- [ ] No duplicate loading
- [ ] Smooth scrolling

---

#### Test Case 1.3.2: Profile Tab Display
**Objective:** Verify profile information displays correctly

**Steps:**
1. Navigate to Home → Profile tab

**Expected Results:**
- ✅ Loading indicator shows initially
- ✅ Profile loads with:
  - User avatar/initial
  - Full name
  - Email
  - Phone number
  - Address
  - Account status
- ✅ Gradient header displays
- ✅ Information cards display nicely

**Pass Criteria:**
- [ ] All user info displays
- [ ] No "Not logged in" error
- [ ] Profile is reactive (updates if user changes)
- [ ] Beautiful UI rendering

---

#### Test Case 1.3.3: Navigation Between Tabs
**Objective:** Verify smooth navigation

**Steps:**
1. Navigate: Home → Logs → Profile → Home
2. Repeat 3-5 times
3. Monitor memory and performance

**Expected Results:**
- ✅ Smooth transitions
- ✅ Each tab loads correctly
- ✅ No memory leaks
- ✅ No rebuild storms

**Pass Criteria:**
- [ ] All tabs functional
- [ ] No performance degradation
- [ ] No errors in console

---

### 1.4 Notifications ⭐⭐

#### Test Case 1.4.1: Notification Badge
**Objective:** Verify unread count displays correctly

**Prerequisites:** Have unread notifications in Firestore

**Steps:**
1. Login to app
2. Observe notification bell icon in app bar

**Expected Results:**
- ✅ Red badge shows unread count
- ✅ Count updates in real-time
- ✅ Tap bell → navigates to Notifications screen

**Pass Criteria:**
- [ ] Badge displays correctly
- [ ] Count is accurate
- [ ] Navigation works

---

#### Test Case 1.4.2: Background Notifications
**Objective:** Verify background handler works (no duplicates)

**Steps:**
1. Send test notification from Firebase Console
2. Receive notification when app is:
   - Foreground
   - Background
   - Terminated

**Expected Results:**
- ✅ Notification received in all states
- ✅ Only ONE handler processes it (no duplicate logs)
- ✅ Uses debugPrint (not print)

**Pass Criteria:**
- [ ] Notifications work in all states
- [ ] No duplicate handlers
- [ ] Proper logging (debugPrint)

---

## Phase 2: Feature Testing (Priority 2)

### 2.1 Tracking ID Management ⭐⭐

#### Test Case 2.1.1: Add Tracking ID
**Steps:**
1. Tap FAB "Add Tracking ID"
2. Fill form:
   - Tracking ID: "TEST123456"
   - Shop Name: "Shopee"
   - Expected Delivery: Tomorrow's date
3. Submit

**Expected Results:**
- ✅ Validation works
- ✅ Tracking ID created in Firestore
- ✅ Success message shown
- ✅ Returns to Home
- ✅ New order appears in list

**Pass Criteria:**
- [ ] Registration successful
- [ ] Order appears immediately
- [ ] All fields saved correctly

---

#### Test Case 2.1.2: View Tracking Details
**Steps:**
1. Tap on a tracking order card
2. View tracking details screen

**Expected Results:**
- ✅ Navigates to details screen
- ✅ Shows all tracking information
- ✅ Status timeline displays
- ✅ Can go back

**Pass Criteria:**
- [ ] Details screen loads
- [ ] All info accurate
- [ ] Good UI/UX

---

### 2.2 Validation Testing ⭐⭐

#### Test Case 2.2.1: Form Validation
**Test Each Field in Registration:**

**Full Name:**
- Empty → Should reject
- "A" → Too short, reject
- "Test User" → Accept
- "123456" → Invalid chars, reject

**Phone:**
- Empty → Reject
- "12345" → Too short, reject
- "09123456789" → Accept (PH format)
- "abc123" → Invalid, reject

**Address:**
- Empty → Reject
- "123" → Too short, reject
- "123 Test St, Bacoor" → Accept

**Password (in register):**
- Empty → Reject
- "weak" → Too short, reject
- "password" → No uppercase, reject
- "PASSWORD" → No lowercase, reject
- "Password" → No number, reject
- "Password123" → Accept

**Pass Criteria:**
- [ ] All validations work
- [ ] Clear error messages
- [ ] Using InputValidator and ErrorHandler

---

## Phase 3: Edge Cases & Error Handling (Priority 3)

### 3.1 Network Issues ⭐

#### Test Case 3.1.1: Offline Behavior
**Steps:**
1. Enable airplane mode
2. Try to login
3. Try to load orders
4. Try to add tracking ID

**Expected Results:**
- ✅ Appropriate error messages
- ✅ No crashes
- ✅ Graceful degradation

**Pass Criteria:**
- [ ] App doesn't crash
- [ ] User-friendly error messages
- [ ] Can recover when online

---

### 3.2 Concurrent Auth Changes ⭐

#### Test Case 3.2.1: Rapid Auth State Changes
**Steps:**
1. Login
2. Immediately logout
3. Immediately login again
4. Switch tabs rapidly
5. Repeat 3-5 times

**Expected Results:**
- ✅ No crashes
- ✅ UI updates correctly
- ✅ No race conditions
- ✅ No memory leaks

**Pass Criteria:**
- [ ] Handles rapid changes
- [ ] No errors
- [ ] Stable performance

---

## Phase 4: Performance Testing (Priority 4)

### 4.1 App Performance ⭐

#### Test Case 4.1.1: Cold Start Time
**Steps:**
1. Force close app
2. Clear from recent apps
3. Launch app
4. Measure time to Home screen

**Expected Results:**
- ✅ Cold start < 3 seconds
- ✅ Splash shows for configured time (2.5s)
- ✅ Smooth transition to Login/Home

**Pass Criteria:**
- [ ] Acceptable startup time
- [ ] No janky animations
- [ ] Good user experience

---

#### Test Case 4.1.2: Memory Usage
**Steps:**
1. Open app
2. Navigate between all screens
3. Add/view multiple tracking IDs
4. Leave app running for 10 minutes
5. Check memory in Android Studio Profiler

**Expected Results:**
- ✅ Stable memory usage
- ✅ No memory leaks
- ✅ Garbage collection working

**Pass Criteria:**
- [ ] Memory < 150MB
- [ ] No leaks detected
- [ ] Stable over time

---

#### Test Case 4.1.3: UI Responsiveness
**Steps:**
1. Rapid scrolling of order list
2. Quick tab switching
3. Fast form input

**Expected Results:**
- ✅ Smooth 60fps animations
- ✅ No lag or jank
- ✅ Responsive interactions

**Pass Criteria:**
- [ ] No frame drops
- [ ] Smooth scrolling
- [ ] Instant feedback

---

## Phase 5: Regression Testing (Priority 3)

### 5.1 Existing Features ⭐

#### Test Case 5.1.1: All Previous Features Still Work
**Checklist:**
- [ ] Splash screen animation
- [ ] Login with email
- [ ] Register new user
- [ ] Google Sign-In
- [ ] Forgot password
- [ ] View orders list
- [ ] Add tracking ID
- [ ] View tracking details
- [ ] View notifications
- [ ] View scan logs
- [ ] View profile
- [ ] Logout

**Pass Criteria:**
- [ ] All features functional
- [ ] No regressions introduced

---

## Test Results Template

### Test Execution Log

```markdown
## Test Execution - [Date]

**Tester:** [Your Name]
**Device:** [Device Model]
**OS Version:** [Android/iOS Version]
**App Version:** 1.0.0-optimized

### Test Results Summary
| Phase | Test Cases | Passed | Failed | Blocked | Pass Rate |
|-------|-----------|--------|--------|---------|-----------|
| Phase 1 | 15 | 0 | 0 | 0 | 0% |
| Phase 2 | 5 | 0 | 0 | 0 | 0% |
| Phase 3 | 3 | 0 | 0 | 0 | 0% |
| Phase 4 | 3 | 0 | 0 | 0 | 0% |
| Phase 5 | 1 | 0 | 0 | 0 | 0% |
| **Total** | **27** | **0** | **0** | **0** | **0%** |

### Critical Issues Found
1. [Issue description]
   - Severity: High/Medium/Low
   - Steps to reproduce
   - Expected vs Actual
   - Screenshots/Logs

### Minor Issues Found
1. [Issue description]

### Performance Metrics
- Cold Start: [X]s
- Memory Usage: [X]MB
- Frame Rate: [X]fps

### Notes
- [Any observations]

### Sign-off
- [ ] All critical tests passed
- [ ] No blockers found
- [ ] Ready for next phase

**Tested by:** _______________
**Date:** _______________
```

---

## Automated Testing (Future)

### Unit Tests to Add
```dart
// test/services/input_validator_test.dart
void main() {
  group('InputValidator.validateEmail', () {
    test('accepts valid emails', () {
      expect(InputValidator.validateEmail('test@example.com'), null);
    });
    
    test('rejects invalid emails', () {
      expect(InputValidator.validateEmail('invalid'), isNotNull);
    });
  });
}
```

### Widget Tests to Add
```dart
// test/screens/login_screen_test.dart
testWidgets('shows error on invalid credentials', (tester) async {
  await tester.pumpWidget(MaterialApp(home: LoginScreen()));
  // ... test implementation
});
```

---

## Quick Test Commands

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/services/auth_service_test.dart

# Run with coverage
flutter test --coverage

# View coverage report (requires lcov)
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

---

## Test Coverage Goals

| Component | Target Coverage | Current |
|-----------|----------------|---------|
| Services | 80%+ | TBD |
| Models | 90%+ | TBD |
| Widgets | 70%+ | TBD |
| Utils | 90%+ | TBD |
| **Overall** | **75%+** | **TBD** |

---

## Bug Reporting Template

```markdown
## Bug Report

**Bug ID:** BUG-XXX
**Date Found:** [Date]
**Severity:** Critical / High / Medium / Low

### Description
[Clear description of the bug]

### Steps to Reproduce
1. Step 1
2. Step 2
3. Step 3

### Expected Behavior
[What should happen]

### Actual Behavior
[What actually happens]

### Environment
- Device: [Device model]
- OS: [Android X.X]
- App Version: [Version]

### Logs
```
[Relevant logs]
```

### Screenshots
[Attach screenshots]

### Workaround
[If any workaround exists]

### Priority
[Why this priority level]
```

---

## Testing Checklist

### Pre-Testing
- [ ] Latest code pulled from repository
- [ ] Flutter clean && flutter pub get
- [ ] No compilation errors
- [ ] Test environment ready
- [ ] Test data prepared

### During Testing
- [ ] Follow test cases systematically
- [ ] Document all findings
- [ ] Take screenshots of issues
- [ ] Save logs for failures
- [ ] Note performance metrics

### Post-Testing
- [ ] All test cases executed
- [ ] Results documented
- [ ] Bugs reported
- [ ] Test summary created
- [ ] Sign-off obtained

---

## Success Criteria

**Phase 1 (Critical) - Must Pass:**
- ✅ All authentication flows work
- ✅ Auth state reactivity confirmed
- ✅ Home screen displays correctly
- ✅ No crashes or errors

**Phase 2 (Features) - Should Pass:**
- ✅ All core features functional
- ✅ Validation works properly
- ✅ Good user experience

**Phase 3-5 (Additional) - Nice to Pass:**
- ✅ Edge cases handled
- ✅ Good performance metrics
- ✅ No regressions

**Overall Success:**
- Critical Pass Rate: 100%
- Feature Pass Rate: 95%+
- No high-severity bugs
- Performance acceptable

---

**Testing Status:** 📋 Ready to Execute  
**Priority:** ⭐⭐⭐ High  
**Estimated Time:** 3-4 hours for complete testing  
**Start Date:** [To be scheduled]

---

*Remember: Quality is not an act, it is a habit. - Aristotle*
