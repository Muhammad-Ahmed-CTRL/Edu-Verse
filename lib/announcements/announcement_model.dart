import 'package:cloud_firestore/cloud_firestore.dart';

class Announcement {
  final String id;
  final String title;
  final String content;
  final String? imageBase64;
  final String universityId;
  final String authorId;
  final DateTime createdAt;

  Announcement({
    required this.id,
    required this.title,
    required this.content,
    this.imageBase64,
    required this.universityId,
    required this.authorId,
    required this.createdAt,
  });

  // Helper to check if the announcement is "New" (less than 48 hours old)
  bool get isNew {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    return difference.inHours <= 48;
  }

  // Convert from Firestore Document
  factory Announcement.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    DateTime created;
    try {
      final ts = data['timestamp'];
      if (ts is Timestamp) {
        created = ts.toDate();
      } else if (ts is Map && ts['_seconds'] != null) {
        created = DateTime.fromMillisecondsSinceEpoch((ts['_seconds'] as int) * 1000);
      } else {
        created = DateTime.now();
      }
    } catch (_) {
      created = DateTime.now();
    }

    return Announcement(
      id: doc.id,
      title: data['title'] ?? '',
      content: data['content'] ?? '',
      imageBase64: data['imageBase64'],
      universityId: data['uniId'] ?? '',
      authorId: data['postedBy'] ?? '',
      createdAt: created,
    );
  }

  // Convert to Map for saving to Firestore
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'content': content,
      'imageBase64': imageBase64,
      'uniId': universityId,
      'postedBy': authorId,
      'timestamp': Timestamp.fromDate(createdAt),
    };
  }
}