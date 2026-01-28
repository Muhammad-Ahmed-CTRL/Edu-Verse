# Firestore Database Examples & Query Patterns

## Collections Structure

```
Firestore Database (Cloud Firestore)
├── users/
│   └── {email} (document)
│       ├── name: string
│       ├── email: string
│       ├── createdAt: timestamp
│       └── photoURL: string (optional)
│
├── posts/
│   └── {postId} (document)
│       ├── title: string
│       ├── description: string
│       ├── category: string ("lost" or "found")
│       ├── location: string
│       ├── userId: string (user email)
│       ├── images: array<string> (image URLs from storage)
│       ├── createdAt: timestamp
│       ├── status: string ("active", "resolved", "claimed")
│       └── comments: map<comment> (nested)
│
└── phoneNumbers/
    └── {uid} (document)
        ├── uid: string
        └── phoneNumber: string
```

## Common Firestore Queries

### 1. Get All Posts
```dart
Future<List<Map<String, dynamic>>> getAllPosts() async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .get();
    
    return snapshot.docs.map((doc) => doc.data()).toList();
  } catch (e) {
    print('Error fetching posts: $e');
    return [];
  }
}
```

### 2. Get Posts by Category (Lost/Found)
```dart
Future<List<Map<String, dynamic>>> getPostsByCategory(String category) async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('posts')
        .where('category', isEqualTo: category)
        .orderBy('createdAt', descending: true)
        .get();
    
    return snapshot.docs.map((doc) => doc.data()).toList();
  } catch (e) {
    print('Error: $e');
    return [];
  }
}
```

### 3. Create a New Post
```dart
Future<bool> createPost({
  required String title,
  required String description,
  required String category, // "lost" or "found"
  required String location,
  required List<String> imageUrls,
}) async {
  try {
    final userId = FirebaseAuth.instance.currentUser?.email ?? "";
    final postId = FirebaseFirestore.instance.collection('posts').doc().id;
    
    await FirebaseFirestore.instance.collection('posts').doc(postId).set({
      'postId': postId,
      'title': title,
      'description': description,
      'category': category,
      'location': location,
      'userId': userId,
      'images': imageUrls,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'active',
      'comments': {},
    });
    
    return true;
  } catch (e) {
    print('Error creating post: $e');
    return false;
  }
}
```

### 4. Search Posts by Title or Description
```dart
Future<List<Map<String, dynamic>>> searchPosts(String query) async {
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('posts')
        .where('status', isEqualTo: 'active')
        .get();
    
    // Client-side filtering for text search
    return snapshot.docs
        .map((doc) => doc.data())
        .where((post) => 
            post['title'].toString().toLowerCase().contains(query.toLowerCase()) ||
            post['description'].toString().toLowerCase().contains(query.toLowerCase())
        )
        .toList();
  } catch (e) {
    print('Error: $e');
    return [];
  }
}
```

### 5. Get User's Own Posts
```dart
Future<List<Map<String, dynamic>>> getUserPosts() async {
  try {
    final userId = FirebaseAuth.instance.currentUser?.email ?? "";
    
    final snapshot = await FirebaseFirestore.instance
        .collection('posts')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .get();
    
    return snapshot.docs.map((doc) => doc.data()).toList();
  } catch (e) {
    print('Error: $e');
    return [];
  }
}
```

### 6. Update a Post
```dart
Future<bool> updatePost(String postId, Map<String, dynamic> updates) async {
  try {
    await FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .update(updates);
    return true;
  } catch (e) {
    print('Error updating post: $e');
    return false;
  }
}
```

### 7. Delete a Post
```dart
Future<bool> deletePost(String postId) async {
  try {
    await FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .delete();
    return true;
  } catch (e) {
    print('Error deleting post: $e');
    return false;
  }
}
```

### 8. Add Comment to Post
```dart
Future<bool> addComment(String postId, String comment) async {
  try {
    final userId = FirebaseAuth.instance.currentUser?.email ?? "Anonymous";
    final commentId = FirebaseFirestore.instance.collection('posts').doc().id;
    
    await FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .update({
          'comments.${commentId}': {
            'userId': userId,
            'text': comment,
            'createdAt': FieldValue.serverTimestamp(),
          }
        });
    
    return true;
  } catch (e) {
    print('Error adding comment: $e');
    return false;
  }
}
```

### 9. Real-time Listener (Get posts and listen for changes)
```dart
StreamSubscription<QuerySnapshot>? listenToPosts() {
  return FirebaseFirestore.instance
      .collection('posts')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .listen((snapshot) {
        for (var doc in snapshot.docs) {
          print('Post: ${doc.data()}');
        }
      });
}
```

### 10. Get Single Post by ID
```dart
Future<Map<String, dynamic>?> getPost(String postId) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .get();
    
    return doc.data();
  } catch (e) {
    print('Error: $e');
    return null;
  }
}
```

## Firebase Storage (Image Upload) Examples

### Upload Image
```dart
Future<String?> uploadImage(File imageFile, String imageName) async {
  try {
    final ref = FirebaseStorage.instance.ref('posts/$imageName');
    await ref.putFile(imageFile);
    final url = await ref.getDownloadURL();
    return url;
  } catch (e) {
    print('Error uploading image: $e');
    return null;
  }
}
```

### Upload Multiple Images
```dart
Future<List<String>> uploadImages(List<File> imageFiles) async {
  List<String> urls = [];
  try {
    for (int i = 0; i < imageFiles.length; i++) {
      final imageName = '${DateTime.now().millisecondsSinceEpoch}_$i';
      final url = await uploadImage(imageFiles[i], imageName);
      if (url != null) {
        urls.add(url);
      }
    }
    return urls;
  } catch (e) {
    print('Error: $e');
    return urls;
  }
}
```

### Delete Image from Storage
```dart
Future<bool> deleteImage(String imageUrl) async {
  try {
    final ref = FirebaseStorage.instance.refFromURL(imageUrl);
    await ref.delete();
    return true;
  } catch (e) {
    print('Error deleting image: $e');
    return false;
  }
}
```

## Important Notes

1. **Always use try-catch** when accessing Firestore
2. **Use FieldValue.serverTimestamp()** for timestamps (server-side)
3. **Add proper error handling** in your UI (show snackbars/dialogs)
4. **Test Firestore rules** before going to production
5. **Use indexes** for complex queries (Firestore will prompt you)
6. **Optimize queries** - fetch only what you need

## Firestore Best Practices

- Keep documents small (< 1MB)
- Avoid deeply nested data
- Use subcollections for large arrays
- Index your queries
- Use batch writes for multiple updates
- Limit real-time listeners (they cost money)
