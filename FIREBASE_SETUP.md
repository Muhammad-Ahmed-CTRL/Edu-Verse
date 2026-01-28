# Firebase Setup Guide for Reclaimify

## Step 1: Create a Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **"Add project"**
3. Enter project name: `reclaimify` (or your preferred name)
4. Accept the terms and click **"Create project"**
5. Wait for the project to be created

## Step 2: Get Firebase Configuration

### For Android:
1. In Firebase Console, click **"Add app"** → **Android**
2. Enter package name: `com.example.reclaimify` (or your package name)
3. Download `google-services.json`
4. Place it in: `android/app/google-services.json`
5. Add plugin to `android/build.gradle.kts`:
   ```kotlin
   plugins {
       ...
       id("com.google.gms.google-services") version "4.3.15"
   }
   ```
6. Add plugin to `android/app/build.gradle.kts`:
   ```kotlin
   plugins {
       ...
       id("com.google.gms.google-services")
   }
   ```

### For Web:
1. In Firebase Console, click **"Add app"** → **Web**
2. You'll see a config object with these keys:
   - apiKey
   - appId
   - messagingSenderId
   - projectId
   - storageBucket

### For iOS (if needed):
1. In Firebase Console, click **"Add app"** → **iOS**
2. Enter bundle ID: `com.example.reclaimify`
3. Download `GoogleService-Info.plist`
4. Add to Xcode project

## Step 3: Update main.dart with Firebase Config

Replace the placeholder keys in `lib/main.dart` with your actual Firebase config:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "YOUR_ACTUAL_API_KEY_HERE",
      appId: "YOUR_ACTUAL_APP_ID_HERE",
      messagingSenderId: "YOUR_ACTUAL_SENDER_ID_HERE",
      projectId: "YOUR_ACTUAL_PROJECT_ID_HERE",
      storageBucket: "YOUR_ACTUAL_STORAGE_BUCKET_HERE",
    ),
  );
  runApp(const UniversityApp());
}
```

## Step 4: Setup Firestore Database

1. In Firebase Console, go to **Firestore Database**
2. Click **"Create database"**
3. Choose **"Start in test mode"** (for development)
4. Select your preferred location
5. Click **"Enable"**

## Step 5: Setup Authentication

1. Go to **Authentication** → **Sign-in method**
2. Enable:
   - **Email/Password**
   - **Google** (if using Google Sign-In)
   - **Phone** (if needed)

## Step 6: Setup Storage (for image uploads)

1. Go to **Storage**
2. Click **"Get started"**
3. Choose test mode rules
4. Click **"Done"**

## Step 7: Update Security Rules

### Firestore Rules (Development):
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
    match /users/{uid} {
      allow read, write: if request.auth.uid == uid;
    }
  }
}
```

### Storage Rules (Development):
```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

## Step 8: Test Connection

Run your app and check if Firebase initializes without errors:

```bash
flutter run -d chrome      # For web
flutter run -d android     # For Android
flutter run -d ios         # For iOS
```

## Database Structure Example

Your Firestore should have this structure:

```
users/
  {email}/
    - name: string
    - email: string
    - createdAt: timestamp
    - photoURL: string

posts/
  {postId}/
    - title: string
    - description: string
    - category: string (lost/found)
    - location: string
    - userId: string
    - images: array
    - createdAt: timestamp
    - status: string (active/resolved)

phoneNumbers/
  {uid}/
    - uid: string
    - phoneNumber: string
```

## Common Issues & Solutions

### Error: "apiKey not found"
- Make sure you replaced the placeholder keys with actual Firebase config
- Check Firebase Console for correct project

### Error: "Firestore not initialized"
- Ensure Firestore Database is created in Firebase Console
- Check internet connection

### Error: "Authentication failed"
- Check if Email/Password auth is enabled in Firebase Console
- Verify user exists in Authentication tab

## Next Steps

1. Copy your Firebase config keys from Firebase Console
2. Update `lib/main.dart` with your credentials
3. Run `flutter pub get`
4. Test the app with `flutter run`
