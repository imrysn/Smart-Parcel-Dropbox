# 📱 App Flow Diagram

## User Journey Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         APP START                               │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
            ┌──────────────────┐
            │  Splash Screen   │
            │  (2 seconds)     │
            └────────┬─────────┘
                     │
                     ▼
         ┌───────────────────────┐
         │  Check Auth Status    │
         └─────┬───────────┬─────┘
               │           │
        Logged In    Not Logged In
               │           │
               ▼           ▼
      ┌─────────────┐  ┌─────────────┐
      │ Home Screen │  │Login Screen │
      └──────┬──────┘  └──────┬──────┘
             │                 │
             │                 ├──Register──┐
             │                 │            │
             │                 ▼            ▼
             │         ┌──────────────────────┐
             │         │  Register Screen     │
             │         └──────────┬───────────┘
             │                    │
             │                    └─────┐
             │                          │
             ▼                          ▼
    ┌──────────────────────────────────────┐
    │          HOME SCREEN                 │
    │  ┌────────────────────────────────┐  │
    │  │  Navigation: Home | Profile    │  │
    │  └────────────────────────────────┘  │
    │                                      │
    │  HOME TAB:                           │
    │  ┌────────────────────────────────┐  │
    │  │  Active Orders List            │  │
    │  │  ┌────────────────────┐        │  │
    │  │  │ Order Card 1       │        │  │
    │  │  │ Status: Delivered  │        │  │
    │  │  └────────────────────┘        │  │
    │  │  ┌────────────────────┐        │  │
    │  │  │ Order Card 2       │        │  │
    │  │  │ Status: In Transit │        │  │
    │  │  └────────────────────┘        │  │
    │  └────────────────────────────────┘  │
    │                                      │
    │  [+ Add Tracking ID] (FAB)           │
    │                                      │
    │  PROFILE TAB:                        │
    │  ┌────────────────────────────────┐  │
    │  │  User Avatar                   │  │
    │  │  Full Name                     │  │
    │  │  Email                         │  │
    │  │  Phone Number                  │  │
    │  │  Address                       │  │
    │  └────────────────────────────────┘  │
    └───────────┬─────────────┬────────────┘
                │             │
        Click FAB       Click Order
                │             │
                ▼             ▼
    ┌──────────────────┐  ┌──────────────────┐
    │ Add Tracking     │  │ Tracking Details │
    │ Screen           │  │ Screen           │
    │                  │  │                  │
    │ [Tracking ID]    │  │ Status Info      │
    │ [Shop Name]      │  │ Parcel Info      │
    │ [Expected Date]  │  │ Delivery Logs    │
    │                  │  │                  │
    │ [Add Button]     │  │ Timeline View    │
    └──────────────────┘  └──────────────────┘
```

## Screen-by-Screen Breakdown

### 1. Splash Screen
```
┌────────────────────┐
│                    │
│    📦 App Icon     │
│                    │
│  Smart Parcel      │
│  Drop Box          │
│                    │
│  Secure Contactless│
│  Deliveries        │
│                    │
│      ⏳ Loading    │
│                    │
└────────────────────┘
```

### 2. Login Screen
```
┌────────────────────┐
│  📦 Logo           │
│                    │
│  Smart Parcel      │
│  Drop Box          │
│  Sign in to        │
│  continue          │
│                    │
│  📧 Email          │
│  [____________]    │
│                    │
│  🔒 Password       │
│  [____________]    │
│                    │
│  [   Login   ]     │
│                    │
│  Don't have an     │
│  account? Register │
└────────────────────┘
```

### 3. Register Screen
```
┌────────────────────┐
│  ← Register        │
│                    │
│  👤 Full Name      │
│  [____________]    │
│                    │
│  📧 Email          │
│  [____________]    │
│                    │
│  📱 Phone          │
│  [____________]    │
│                    │
│  🏠 Address        │
│  [____________]    │
│  [____________]    │
│                    │
│  🔒 Password       │
│  [____________]    │
│                    │
│  🔒 Confirm        │
│  [____________]    │
│                    │
│  [  Register  ]    │
└────────────────────┘
```

### 4. Home Screen - Home Tab
```
┌────────────────────┐
│ Smart Parcel  🚪   │
│ Drop Box           │
├────────────────────┤
│                    │
│ ┌────────────────┐ │
│ │ Shopee        ⬤│ │
│ │ Delivered      │ │
│ │ ID: ABC123     │ │
│ │ Expected: Today│ │
│ └────────────────┘ │
│                    │
│ ┌────────────────┐ │
│ │ Lazada        ⬤│ │
│ │ In Transit     │ │
│ │ ID: XYZ789     │ │
│ └────────────────┘ │
│                    │
│                    │
│              [+]   │ ← FAB
├────────────────────┤
│  🏠 Home | 👤 Me  │
└────────────────────┘
```

### 5. Home Screen - Profile Tab
```
┌────────────────────┐
│ Smart Parcel  🚪   │
│ Drop Box           │
├────────────────────┤
│                    │
│ ┌────────────────┐ │
│ │      👤        │ │
│ │   Juan Dela    │ │
│ │   Cruz         │ │
│ │ juan@email.com │ │
│ └────────────────┘ │
│                    │
│ ┌────────────────┐ │
│ │ 📱 Phone       │ │
│ │ 09123456789    │ │
│ ├────────────────┤ │
│ │ 🏠 Address     │ │
│ │ Bacoor, Cavite │ │
│ └────────────────┘ │
│                    │
├────────────────────┤
│  🏠 Home | 👤 Me  │
└────────────────────┘
```

### 6. Add Tracking Screen
```
┌────────────────────┐
│ ← Add Tracking ID  │
├────────────────────┤
│                    │
│ ┌────────────────┐ │
│ │ ℹ️ Register your│ │
│ │ tracking ID to  │ │
│ │ receive updates │ │
│ └────────────────┘ │
│                    │
│  📊 Tracking ID    │
│  [____________]    │
│                    │
│  🏪 Shop Name      │
│  [____________]    │
│                    │
│  📅 Expected Date  │
│  [____________]    │
│                    │
│                    │
│  [Add Tracking ID] │
│                    │
└────────────────────┘
```

### 7. Tracking Details Screen
```
┌────────────────────┐
│ ← Tracking Details │
├────────────────────┤
│ ┌────────────────┐ │
│ │      📦        │ │
│ │   Delivered    │ │
│ │ Your parcel has│ │
│ │ been delivered │ │
│ └────────────────┘ │
│                    │
│ Parcel Information │
│ ┌────────────────┐ │
│ │ 🏪 Shop        │ │
│ │    Shopee      │ │
│ ├────────────────┤ │
│ │ 📊 Tracking ID │ │
│ │    ABC123456   │ │
│ ├────────────────┤ │
│ │ 📅 Expected    │ │
│ │    2025-11-08  │ │
│ ├────────────────┤ │
│ │ ✅ Delivered   │ │
│ │    2025-11-08  │ │
│ │    10:30 AM    │ │
│ └────────────────┘ │
│                    │
│ Delivery Logs      │
│ ┌────────────────┐ │
│ │ 📷 Scanned     │ │
│ │ 10:28 AM       │ │
│ ├────────────────┤ │
│ │ 🔓 Door Opened │ │
│ │ 10:29 AM       │ │
│ ├────────────────┤ │
│ │ 📥 Inserted    │ │
│ │ 10:30 AM       │ │
│ ├────────────────┤ │
│ │ 🔒 Door Closed │ │
│ │ 10:30 AM       │ │
│ └────────────────┘ │
└────────────────────┘
```

## Data Flow

```
┌──────────────────┐
│  Mobile App      │
│  (Flutter)       │
└────────┬─────────┘
         │
         │ Firebase SDK
         │
         ▼
┌──────────────────┐
│  Firebase        │
│  Services        │
│                  │
│  ┌────────────┐  │
│  │ Auth       │  │ ← User Login/Register
│  └────────────┘  │
│                  │
│  ┌────────────┐  │
│  │ Firestore  │  │ ← Data Storage
│  │ Database   │  │   - users
│  └────────────┘  │   - tracking_ids
│                  │   - delivery_logs
│  ┌────────────┐  │
│  │ Cloud      │  │ ← Push Notifications
│  │ Messaging  │  │
│  └────────────┘  │
└────────┬─────────┘
         │
         │ IoT Communication
         │ (Future Integration)
         │
         ▼
┌──────────────────┐
│  Smart Parcel    │
│  Drop Box        │
│  Hardware        │
│  (ESP32)         │
└──────────────────┘
```

## Firebase Collections Structure

```
Firestore Database
│
├── users/
│   └── {userId}/
│       ├── uid: string
│       ├── email: string
│       ├── fullName: string
│       ├── phoneNumber: string
│       ├── address: string
│       ├── role: string
│       └── createdAt: timestamp
│
├── tracking_ids/
│   └── {trackingId}/
│       ├── trackingId: string
│       ├── userId: string
│       ├── shopName: string
│       ├── status: string
│       ├── registeredAt: timestamp
│       ├── expectedDeliveryDate: string
│       ├── deliveredAt: timestamp
│       └── retrievedAt: timestamp
│
└── delivery_logs/
    └── {logId}/
        ├── trackingId: string
        ├── userId: string
        ├── eventType: string
        ├── details: string
        └── timestamp: timestamp
```

## Authentication Flow

```
Registration Flow:
1. User enters details
2. App validates input
3. Firebase creates account
4. App creates user document in Firestore
5. User automatically logged in
6. Navigate to Home Screen

Login Flow:
1. User enters email/password
2. App validates input
3. Firebase authenticates
4. On success, save auth state
5. Navigate to Home Screen

Auto-Login:
1. App starts
2. Check Firebase auth state
3. If logged in → Home Screen
4. If not → Login Screen
```

## Status Flow

```
Parcel Status Lifecycle:

pending → in_transit → delivered → retrieved
   ↓          ↓           ↓           ↓
 🟠 Orange  🔵 Blue    🟢 Green   ⚪ Grey

pending:     Registered, waiting for pickup
in_transit:  Out for delivery
delivered:   In drop box, ready for pickup
retrieved:   User collected the parcel
```

This diagram should help you understand how everything connects together!
