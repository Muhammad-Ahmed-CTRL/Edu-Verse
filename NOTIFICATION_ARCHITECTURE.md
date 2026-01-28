# EduVerse Notification System - Architecture Diagrams

## 🏗️ System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     EduVerse App (Flutter)                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │         NotificationService Singleton                   │   │
│  ├──────────────────────────────────────────────────────────┤   │
│  │ ✅ init()          - Initialize FCM + Local Notif       │   │
│  │ ✅ registerUserListener()  - Real-time Firestore listen │   │
│  │ ✅ _createAndPushNotification() - Core create + fan-out │   │
│  │ ✅ _sendV1Push() - FCM V1 HTTP API                      │   │
│  │ ✅ notify*() - Convenience wrappers (Announcement, etc) │   │
│  └──────────────────────────────────────────────────────────┘   │
│           ↓           ↓           ↓           ↓                  │
│    ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐          │
│    │ FCM Init │ │Local Notif│ │ Listeners│ │ V1 Push  │          │
│    │  Setup   │ │  Config   │ │  Setup   │ │  Setup   │          │
│    └──────────┘ └──────────┘ └──────────┘ └──────────┘          │
│           ↓           ↓           ↓           ↓                  │
└─────────────────────────────────────────────────────────────────┘
         ↓                          ↓                      ↓
    ┌─────────┐            ┌──────────────┐        ┌──────────┐
    │ Android │            │   Firestore  │        │ Google   │
    │   iOS   │            │   Realtime   │        │ FCM V1   │
    │ WebPush │            │   Database   │        │   API    │
    └─────────┘            └──────────────┘        └──────────┘
```

---

## 📊 Notification Flow Diagram

### Broadcast Notification (e.g., Announcement)
```
Admin Posts Announcement
         ↓
┌─────────────────────────────────────┐
│ notifyAnnouncement(                 │
│   universityId: 'uni_123',          │
│   title: 'New Announcement',        │
│   body: '...'                       │
│ )                                   │
└─────────────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│ _createAndPushNotification()         │
│                                     │
│ for each user in university:        │
│   ├─ Write to users/{uid}/notif/   │ ← KEY: Per-user storage
│   └─ Fetch users/{uid}/fcmTokens   │
└─────────────────────────────────────┘
    ↙            ↙           ↙            ↙
User A       User B       User C       User D
Write to:    Write to:    Write to:    Write to:
users/A/...  users/B/...  users/C/...  users/D/...
    ↓            ↓           ↓            ↓
Real-time  Real-time  Real-time  Real-time
Listener   Listener   Listener   Listener
Fires      Fires      Fires      Fires
    ↓            ↓           ↓            ↓
Show Local Show Local Show Local Show Local
Notif      Notif      Notif      Notif
(Android)  (Android)  (Android)  (Android)
    ↓            ↓           ↓            ↓
System Notif ┐ System Notif ┐ System Notif ┐ System Notif ┐
Appears      Appears         Appears         Appears
```

### Targeted Notification (e.g., Approval)
```
Admin Approves Job Request
         ↓
┌──────────────────────────────────┐
│ notifyRequestApproved(           │
│   userId: 'recruiter_uid',  ← KEY│
│   universityId: 'uni_123'        │
│ )                                │
└──────────────────────────────────┘
         ↓
┌──────────────────────────────────┐
│ _createAndPushNotification()      │
│                                  │
│ Write ONLY to:                   │
│ users/{recruiter_uid}/notif/  ← ISOLATED
│                                  │
│ Send push ONLY to recruiter's    │
│ tokens in users/{recruiter}/...  │
└──────────────────────────────────┘
         ↓
Real-time Listener for Recruiter
         ↓
Show Local Notification (Mobile)
OR
Show in NotificationPage (Web)
```

---

## 🗄️ Database Structure Diagram

```
Firestore
│
├── announcements/                    ← Global announcements
│   └── {docId}
│       ├── title: "..."
│       ├── content: "..."
│       └── uniId: "uni_123"
│
├── users/
│   ├── {userId_A}/
│   │   ├── notifications/          ← ✅ ISOLATED per user
│   │   │   ├── {docId_1}
│   │   │   │   ├── title: "Announcement"
│   │   │   │   ├── type: "announcement"
│   │   │   │   ├── isRead: false
│   │   │   │   └── createdAt: 2025-12-29
│   │   │   └── {docId_2}
│   │   │       ├── title: "Job Posted"
│   │   │       ├── type: "jobPosting"
│   │   │       ├── isRead: false
│   │   │       └── createdAt: 2025-12-29
│   │   │
│   │   ├── fcmTokens/              ← Device tokens
│   │   │   ├── {token_1} {createdAt}
│   │   │   └── {token_2} {createdAt}
│   │   │
│   │   └── settings/
│   │       └── notifications {preferences}
│   │
│   ├── {userId_B}/
│   │   ├── notifications/          ← SEPARATE for User B
│   │   │   ├── {docId_1}
│   │   │   │   ├── title: "Announcement"  ← SAME title
│   │   │   │   ├── type: "announcement"   ← SAME type
│   │   │   │   └── isRead: false
│   │   │   └── {docId_3}
│   │   │       ├── title: "Lost Item"
│   │   │       └── type: "lostAndFound"
│   │   │
│   │   ├── fcmTokens/
│   │   └── settings/
│   │
│   └── {userId_C}/
│       ├── notifications/          ← SEPARATE for User C
│       │   ├── {docId_1}
│       │   │   ├── title: "Announcement"  ← SAME again (fan-out)
│       │   │   └── type: "announcement"   ← When deleted here,
│       │   └── {docId_4}               ← doesn't affect A or B
│       ├── fcmTokens/
│       └── settings/
│
├── jobs/                            ← Job postings
│   └── {jobId}
│
├── complaints/                      ← Student complaints
│   └── {complaintId}
│
└── universities/                    ← University data
    └── {uniId}/
        ├── marketplace_items/
        └── ...
```

### Key Design Feature
```
When Admin Posts Announcement:

❌ OLD DESIGN (WRONG):
notifications/
└── {docId}
    └── sharedByAll: true  ← All users see same doc
                           ← One delete = all lose it

✅ NEW DESIGN (CORRECT):
users/userA/notifications/{docId}  ← User A's copy
users/userB/notifications/{docId}  ← User B's copy (different)
users/userC/notifications/{docId}  ← User C's copy (different)

Delete in A → only A's copy deleted ✅
Delete in B → B's copy gone, A & C unaffected ✅
```

---

## 🔄 Real-Time Notification Flow

```
┌─────────────────────────────────────────────────────────────┐
│                   NotificationPage Opens                    │
├─────────────────────────────────────────────────────────────┤
│ initState() called                                          │
│   ↓                                                          │
│ _service.registerUserListener(userId)  ← ACTIVATE LISTENER │
│   ↓                                                          │
│ Listen to: users/{userId}/notifications (Firestore)        │
│   ↓                                                          │
│ StreamBuilder instantiated                                  │
│   ↓                                                          │
│ "All Notifications" StreamBuilder.listen()                 │
└─────────────────────────────────────────────────────────────┘
                    ↓
        ┌───────────────────────┐
        │ WAITING FOR CHANGES   │
        └───────────────────────┘
                    ↓
        Admin posts Announcement
                    ↓
        Document added to users/{userId}/notifications/
                    ↓
        Real-time listener fires
                    ↓
        ┌─────────────────────────────────────┐
        │ NEW DOCUMENT DETECTED               │
        │                                     │
        │ if (change.type == added) {        │
        │   showLocalNotification()           │
        │ }                                   │
        └─────────────────────────────────────┘
                    ↓
        Mobile: System notification appears
        (Alert, sound, vibration)
                    ↓
        StreamBuilder refreshes UI
        (New notification appears in list)
                    ↓
        Badge count updates
        (If unread)
```

---

## 📱 Mobile Notification Lifecycle

```
App State: RUNNING (Open)
         ↓
Notification Document added to Firestore
         ↓
Real-time Listener fires
(registerUserListener callback)
         ↓
showLocalNotification() called
         ↓
Android: AndroidFlutterLocalNotificationsPlugin.show()
iOS: DarwinFlutterLocalNotificationsPlugin.show()
         ↓
System Notification Display
─────────────────────────────
Android: Notification bar
iOS: Alert / Banner
─────────────────────────────
         ↓
User taps notification
         ↓
onDidReceiveNotificationResponse
(Payload passed)
         ↓
Navigate to NotificationPage
(If not already visible)


App State: BACKGROUND
         ↓
Notification Document added
         ↓
Real-time Listener fires
         ↓
showLocalNotification() called
         ↓
System Notification Display
         ↓
User taps notification
         ↓
FirebaseMessaging.onMessageOpenedApp
(Background handler)
         ↓
App brought to foreground
         ↓
NotificationPage opens


App State: TERMINATED
         ↓
User gets FCM V1 push
         ↓
_firebaseMessagingBackgroundHandler
(top-level handler with @pragma)
         ↓
showLocalNotification() called
         ↓
System Notification Display
         ↓
User taps notification
         ↓
App launches
         ↓
NotificationPage opens
```

---

## 🔐 Isolation & Security Model

```
User Authentication
         ↓
User ID obtained: 'user_abc'
         ↓
Query/Write to Firestore
         ↓
┌────────────────────────────────────────┐
│ FIRESTORE SECURITY RULES               │
├────────────────────────────────────────┤
│ match /users/{userId}/notifications   │
│ {                                      │
│   allow read: if                       │
│     request.auth.uid == userId         │
│     ← ONLY user can read own notifs    │
│                                        │
│   allow write: if                      │
│     request.auth.uid == userId OR      │
│     request.auth.token.admin == true   │
│     ← Only user or admin can write     │
│                                        │
│   allow delete: if                     │
│     request.auth.uid == userId         │
│     ← Only user can delete own         │
│ }                                      │
└────────────────────────────────────────┘
         ↓
Operation Allowed/Denied
         ↓
Result returned to app

SECURITY GUARANTEE:
User A cannot:
  ✅ Read User B's notifications
  ✅ Write to User B's notifications
  ✅ Delete User B's notifications
  ✅ Modify User B's read status
```

---

## 🔄 Admin Approval Workflow

```
Recruiter
   ↓
Submits Job Request
   ↓
┌─────────────────────────────────┐
│ job_requests/                   │
│ └── {docId}                     │
│     ├── status: "pending"       │
│     ├── job: {...}              │
│     └── recruiterId: "rec_123"  │
└─────────────────────────────────┘
         ↓
Admin Dashboard
   ↓
Opens "Recruiter Requests" tab
   ↓
┌─────────────────────────────────┐
│ Review Job Details              │
│ ┌─────────┬─────────┐           │
│ │ Approve │ Reject  │           │
│ └─────────┴─────────┘           │
└─────────────────────────────────┘
         ↓ (Approve clicked)
┌──────────────────────────────────────┐
│ APPROVAL FLOW                        │
├──────────────────────────────────────┤
│ 1. Create job in jobs/ collection   │
│ 2. Call notifyJobPosting()          │
│    ├─ Broadcast to all students     │
│    └─ Each user gets doc in own     │
│        users/{uid}/notifications/   │
│ 3. Call notifyRequestApproved()     │
│    ├─ Targeted to recruiter_uid     │
│    └─ Doc in users/{recruiter}/     │
│        notifications/ ONLY          │
│ 4. Update request: status="approved"│
└──────────────────────────────────────┘
         ↓
Students see: "New Job Posted"
(Notification in their list)
         ↓
Recruiter sees: "Request Approved"
(Notification in their list)
         ↓
Admin sees: "Approved - Status Updated"
(Dashboard updates)
```

---

## 📊 Notification Type Classification

```
BROADCAST (No userId)
├─ Announcement
│   Recipients: All users in university
│   Delivery: Fan-out to users/{uid}/notifications
│
├─ Marketplace
│   Recipients: All users in university
│   Delivery: Fan-out
│
├─ Lost & Found
│   Recipients: All users in university
│   Delivery: Fan-out
│
├─ Timetable Update
│   Recipients: All students with that class
│   Delivery: Fan-out
│
└─ Job Posting
    Recipients: All students in university
    Delivery: Fan-out


TARGETED (With userId)
├─ Request Approved
│   Recipients: Specific recruiter only
│   Delivery: users/{recruiter_id}/notifications
│
├─ Request Rejected
│   Recipients: Specific recruiter only
│   Delivery: users/{recruiter_id}/notifications
│
├─ Complaint Status
│   Recipients: Specific student (complaint filer)
│   Delivery: users/{student_id}/notifications
│
└─ Custom
    Recipients: Specific user OR all
    Delivery: Depends on userId parameter
```

---

## 🎯 Summary

```
KEY PRINCIPLES
═══════════════════════════════════════════════════

✅ Per-User Subcollections
   users/{userId}/notifications/{id}
   → No cross-user interference
   → Natural isolation
   → Easy to implement rules

✅ Real-Time Listeners
   Firestore StreamBuilder
   → Instant UI updates
   → Auto-sync across devices
   → Mobile notifications trigger

✅ Fan-Out Pattern
   For each user → write one document
   → Simple and scalable (<10k users)
   → No transaction complexity

✅ FCM V1 Push API
   HTTP API with service account auth
   → Official Google standard
   → Token-specific delivery
   → Rich notification support

✅ Admin Dashboard
   Central control point
   → Post announcements
   → Approve/reject requests
   → View all pending items
   → Manage complaints

═══════════════════════════════════════════════════
Result: Secure, fast, scalable notification system
```

---

**Last Updated**: December 29, 2025
