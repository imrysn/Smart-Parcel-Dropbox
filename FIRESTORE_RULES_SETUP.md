# Firestore Security Rules Setup

## Issue
If you're getting a `permission-denied` error when accessing the logs page, you need to update your Firestore security rules in the Firebase Console.

## Quick Fix

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Navigate to **Firestore Database** → **Rules** tab
4. Replace the existing rules with the rules below
5. Click **Publish**

## Recommended Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper function to check if user is authenticated
    function isAuthenticated() {
      return request.auth != null;
    }
    
    // Helper function to check if user owns the resource
    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }
    
    // Users collection - users can read/write their own data
    match /users/{userId} {
      allow read, write: if isOwner(userId);
    }
    
    // Tracking IDs collection
    match /tracking_ids/{trackingId} {
      // Users can read their own tracking IDs
      allow read: if isAuthenticated() && resource.data.userId == request.auth.uid;
      // Users can create tracking IDs for themselves
      allow create: if isAuthenticated() && request.resource.data.userId == request.auth.uid;
      // Users can update their own tracking IDs
      allow update: if isAuthenticated() && resource.data.userId == request.auth.uid;
      // System/IoT can update any tracking ID (for delivery status)
      allow update: if isAuthenticated();
    }
    
    // Delivery logs collection
    match /delivery_logs/{logId} {
      // Users can read logs for their tracking IDs
      allow read: if isAuthenticated() && resource.data.userId == request.auth.uid;
      // System/IoT can create delivery logs
      allow create: if isAuthenticated();
    }
    
    // Scan logs collection
    match /scan_logs/{logId} {
      // Users can read their own scan logs
      allow read: if isAuthenticated() && (
        resource.data.userId == request.auth.uid || 
        resource.data.userId == null
      );
      // System/IoT can create scan logs
      allow create: if isAuthenticated();
    }
  }
}
```

## What Changed in the Code

The logs screen now only fetches logs for the current user (`getUserScanLogs(user.uid)`) instead of all logs. This is:
- More secure (users only see their own logs)
- Fixes the permission issue
- Better for privacy

## Testing

After updating the rules:
1. Wait a few seconds for the rules to propagate
2. Restart your app
3. Navigate to the Logs page
4. The permission error should be resolved

## Note

The app has been updated to only show the current user's scan logs. If you need to see all logs (for admin purposes), you would need to:
1. Add an admin role to your user model
2. Update the security rules to allow admins to read all logs
3. Update the logs screen to check for admin role



