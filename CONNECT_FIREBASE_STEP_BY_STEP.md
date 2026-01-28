# Step-by-Step Firebase Connection for Reclaimify

## Prerequisites
- Firebase project created at https://console.firebase.google.com/
- Firebase credentials obtained from project settings

## Step 1: Get Your Firebase Credentials

### For Web/Android:
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Click **⚙️ Project Settings** (top left, next to project name)
4. Go to **"Service Accounts"** tab
5. Click **"Generate New Private Key"** (creates JSON file)
6. Copy the following values:
   - `apiKey` → from Web API Key (in Settings → General)
   - `appId` → from firebaseAppId
   - `messagingSenderId` → from messagingSenderId
   - `projectId` → your project ID
   - `storageBucket` → projectId.appspot.com (format)

### Easier Way - Get Web Config:
1. In Firebase Console, click **⚙️ Project Settings**
2. Click **"Add app"** → **Web**
3. Copy the config object shown:
```javascript
const firebaseConfig = {
  apiKey: "xxx",
  authDomain: "xxx",
  projectId: "xxx",
  storageBucket: "xxx",
  messagingSenderId: "xxx",
  appId: "xxx"
};
```

## Step 2: Update main.dart with Your Credentials

Open `lib/main.dart` and replace the placeholder values:

```dart
await Firebase.initializeApp(
  options: const FirebaseOptions(
    apiKey: "YOUR_API_KEY",           // Copy from Firebase
    appId: "YOUR_APP_ID",             // Copy from Firebase
    messagingSenderId: "YOUR_SENDER_ID", // Copy from Firebase
    projectId: "YOUR_PROJECT_ID",     // Copy from Firebase
    storageBucket: "YOUR_STORAGE_BUCKET", // Format: projectId.appspot.com
  ),
);
```

**Example (with real values):**
```dart
await Firebase.initializeApp(
  options: const FirebaseOptions(
    apiKey: "AIzaSyDxxx123xyz...",
    appId: "1:234567890123:web:abcdef1234567890",
    messagingSenderId: "234567890123",
    projectId: "my-reclaimify-app",
    storageBucket: "my-reclaimify-app.appspot.com",
  ),
);
```

## Step 3: Enable Firebase Services in Console

### Authentication
1. Go to **Authentication** → **Sign-in method**
2. Enable **Email/Password**
3. Enable **Google** (for Google Sign-In)

### Firestore Database
1. Go to **Firestore Database**
2. Click **"Create database"**
3. Start in **test mode** (for development)
4. Select **Start collection** location (e.g., United States)

### Cloud Storage
1. Go to **Storage**
2. Click **"Get started"**
3. Start in **test mode**

## Step 4: Add Your First User

### Via Firebase Console:
1. Go to **Authentication** → **Users**
2. Click **"Add user"**
3. Enter test email and password
4. Click **"Add user"**

### Via Your App:
1. Run the app
2. Click "Sign Up"
3. Enter email, password, name
4. Verify email (click link)
5. Now you're authenticated!

## Step 5: Test the Database Connection

### Create a Firestore Collection Manually:
1. Go to **Firestore Database**
2. Click **"+ Start collection"**
3. Collection name: `users`
4. Add document:
   - Document ID: (auto) or use email
   - Fields:
     - `name`: "Test User" (string)
     - `email`: "test@example.com" (string)
     - `createdAt`: (timestamp - server)

5. Click **"Save"**

### Or Create via Your App:
In `auth.dart`, the `createUser()` function already does this:
```dart
Future<User?> createUser({
  required String email,
  required String password,
  required String username
}) async {
  try {
    await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password
    );
    
    // This creates the user document in Firestore
    await FirebaseFirestore.instance
        .collection("users")
        .doc(email)
        .set({
          'email': email,
          'name': username
        });
    
    return _auth.currentUser;
  } catch (e) {
    // Handle error
    rethrow;
  }
}
```

## Step 6: Update Firestore Rules for Development

1. Go to **Firestore Database** → **Rules**
2. Replace the rules with:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow authenticated users to read and write their own user data
    match /users/{uid} {
      allow read, write: if request.auth.uid == uid;
    }
    
    // Allow authenticated users to read all posts
    match /posts/{postId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth.uid == resource.data.userId;
    }
    
    // Allow phone number access
    match /phoneNumbers/{uid} {
      allow read, write: if request.auth.uid == uid;
    }
  }
}
```

3. Click **"Publish"**

## Step 7: Update Storage Rules for Development

1. Go to **Storage** → **Rules**
2. Replace with:

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Allow authenticated users to read/write their own files
    match /posts/{allPaths=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

3. Click **"Publish"**

## Step 8: Create Posts Collection

Your app already has code to create posts. Here's the structure:

**Collection:** `posts`

**Example Document:**
```
documentId: auto-generated
├── title: "Lost iPhone 14" (string)
├── description: "Black iPhone 14 lost near campus" (string)
├── category: "lost" (string)
├── location: "University Campus" (string)
├── userId: "test@example.com" (string)
├── images: [
│   "https://storage.googleapis.com/.../image1.jpg",
│   "https://storage.googleapis.com/.../image2.jpg"
│ ] (array)
├── createdAt: 2024-12-07T10:30:00Z (timestamp)
├── status: "active" (string)
└── comments: {} (map)
```

## Step 9: Run the App

```bash
cd c:\Users\DELL\OneDrive\Desktop\mad_project

# Clear previous builds
flutter clean

# Get dependencies
flutter pub get

# Run on web
flutter run -d chrome

# OR run on Android
flutter run -d android

# OR run on iOS
flutter run -d ios
```

## Step 10: Test the Complete Flow

1. **Sign Up**: Create an account
   - Check if user document appears in Firestore `users` collection
   
2. **Create Post**: Create a lost/found post
   - Check if post appears in Firestore `posts` collection
   - Check if images appear in Cloud Storage `posts/` folder
   
3. **View Posts**: See all posts
   - Posts should load from Firestore

4. **Search Posts**: Search by title
   - Results should filter correctly

5. **Edit/Delete Posts**: Modify your own posts
   - Changes should appear in Firestore immediately

## Common Troubleshooting

### App Won't Start
- Check if Firebase credentials are correct in `main.dart`
- Verify Firebase project is created
- Check console for error messages: `flutter run -d chrome 2>&1`

### Can't Login
- Verify user exists in Firebase Authentication
- Check Firestore rules allow authentication
- Ensure email is verified (if required)

### Can't See Posts
- Check if posts collection exists in Firestore
- Verify Firestore rules allow read access
- Check browser console for errors (F12 → Console)

### Images Not Uploading
- Check Cloud Storage bucket exists
- Verify Storage rules allow authenticated write
- Ensure image picker is working (select file)
- Check browser developer tools for network errors

### Firestore Rules Error
- Go to Firebase Console → Firestore → Rules
- Check for syntax errors (red underline)
- Try the "Rules Playground" to test rules
- Remember to **Publish** after changes

## Security Checklist (Before Production)

- [ ] Update Firestore rules to restrict unauthorized access
- [ ] Update Storage rules to prevent abuse
- [ ] Enable reCAPTCHA on authentication
- [ ] Set up email verification
- [ ] Configure CORS for storage if needed
- [ ] Add rate limiting rules
- [ ] Test all user permissions
- [ ] Enable billing (required for production)
- [ ] Set up monitoring and logging
- [ ] Backup Firestore data

## Next Steps

1. Get your Firebase credentials
2. Update `lib/main.dart` with real values
3. Run: `flutter pub get`
4. Run: `flutter run -d chrome`
5. Sign up and test the app
6. Check Firestore Console to see data
7. Celebrate! 🎉





