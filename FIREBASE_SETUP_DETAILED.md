# 🔥 Firebase Console Setup - Step by Step Guide

## Current Status
You're viewing: **Project Overview** page
You need to navigate to different sections to enable features.

## Step-by-Step Instructions

### 📍 Step 1: Enable Authentication

1. **In the left sidebar, look for "Build" section** (you can see it in your screenshot)
2. **Click the arrow next to "Build"** to expand it
3. You'll see these options:
   - Authentication ← **Click this**
   - Firestore Database
   - Realtime Database
   - Storage
   - Hosting
   - Functions
   - Machine Learning
   - Remote Config

4. **Click "Authentication"**
5. Click **"Get started"** button
6. You'll see "Sign-in methods" tab
7. Click on **"Email/Password"**
8. Toggle **"Enable"** to ON
9. Click **"Save"**

✅ **Authentication is now enabled!**

---

### 📍 Step 2: Create Firestore Database

1. **In the left sidebar, under "Build" section**
2. **Click "Firestore Database"**
3. Click **"Create database"** button
4. You'll see two options:
   - **Choose "Start in test mode"** ← Select this for development
   - Start in production mode
5. Click **"Next"**
6. **Select region**: Choose **"asia-southeast1 (Singapore)"** 
   - This is closest to Philippines for best performance
7. Click **"Enable"**

✅ **Firestore Database is now created!**

The database will show these collections when you use the app:
- `users` (created on first registration)
- `tracking_ids` (created when adding tracking)
- `delivery_logs` (created on delivery events)

---

### 📍 Step 3: (Optional) Set Up Cloud Messaging

1. **In the left sidebar, under "Build" section**
2. Scroll down and look for **"Cloud Messaging"**
3. This is already configured from your `google-services.json`
4. No additional setup needed for basic functionality

---

## 🎯 Quick Visual Guide

```
Firebase Console Left Sidebar:
┌─────────────────────────┐
│ 🏠 Project Overview     │ ← You are here
├─────────────────────────┤
│ 🔧 Build               │ ← Click the arrow to expand
│   ├─ Authentication     │ ← Go here first (Step 1)
│   ├─ Firestore Database│ ← Go here second (Step 2)
│   ├─ Storage           │
│   └─ ...               │
├─────────────────────────┤
│ 🎯 Run                 │
│   ├─ Analytics         │
│   └─ ...               │
├─────────────────────────┤
│ 🤖 AI                  │
└─────────────────────────┘
```

---

## ⚠️ Important Notes

### Security Rules (After Testing)

Once you've tested the app and confirmed it works, update your Firestore Security Rules:

1. Go to **Firestore Database**
2. Click **"Rules"** tab (at the top)
3. Replace with:

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

4. Click **"Publish"**

---

## ✅ Verification Checklist

After completing the steps, verify:

- [ ] Authentication shows "Email/Password" as **Enabled**
- [ ] Firestore Database shows "Cloud Firestore" tab with empty collections
- [ ] Region is set to **asia-southeast1**
- [ ] Test mode is active (you'll see rules allowing read/write for testing)

---

## 🆘 Can't Find These Options?

If you don't see "Build" or these options:

1. **Refresh the Firebase Console page**
2. **Make sure you're on the correct project**: "Smart Parcel Drop Box"
3. **Check the left sidebar** - you might need to scroll down
4. **Try clicking on "Build" text itself** to expand the menu

---

## 📱 After Firebase Setup

Once Firebase is configured, return to your terminal and run:

```bash
flutter run
```

Then test:
1. Register a new account
2. Add a tracking ID
3. View it on the dashboard

The data will now be stored in your Firestore Database!

---

## 🎓 For Your Thesis

These Firebase services demonstrate:
- **Authentication**: Secure user management
- **Firestore**: Real-time cloud database
- **Cloud Messaging**: Push notification infrastructure
- **Analytics**: User behavior tracking (optional)

All align with your thesis objectives for cloud-based, secure parcel management!
