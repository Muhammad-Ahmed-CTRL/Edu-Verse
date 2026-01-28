// ============================================================================
// COMPLETE EDUVERSE NOTIFICATION SYSTEM - FIXED VERSION
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import 'theme_colors.dart';

// ============================================================================
// 0. TOP-LEVEL BACKGROUND HANDLER
// ============================================================================
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Background message: ${message.messageId}");
  // Show local notification even in background
  if (message.notification != null) {
    await NotificationService().showLocalNotification(
      title: message.notification!.title ?? 'New Notification',
      body: message.notification!.body ?? '',
      payload: jsonEncode(message.data),
    );
  }
}

// ============================================================================
// 1. NOTIFICATION MODELS
// ============================================================================

enum NotificationType {
  announcement,
  timetable,
  lostAndFound,
  jobPosting,
  requestApproved,
  requestRejected,
  complaintInProgress,
  complaintResolved,
  marketplace,
  custom,
}

enum NotificationPriority { low, normal, high, urgent }

class AppNotification {
  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final NotificationPriority priority;
  final String universityId;
  final String? userId;
  final String? imageUrl;
  final String? imageBase64;
  final Map<String, dynamic>? data;
  final DateTime createdAt;
  final bool isRead;
  final bool isPushSent;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.priority = NotificationPriority.normal,
    required this.universityId,
    this.userId,
    this.imageUrl,
    this.imageBase64,
    this.data,
    required this.createdAt,
    this.isRead = false,
    this.isPushSent = false,
  });

  bool get isNew => DateTime.now().difference(createdAt).inHours <= 24;

  String get timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }

  IconData get icon {
    const icons = {
      NotificationType.announcement: Icons.campaign,
      NotificationType.timetable: Icons.calendar_today,
      NotificationType.lostAndFound: Icons.search,
      NotificationType.jobPosting: Icons.work,
      NotificationType.requestApproved: Icons.check_circle,
      NotificationType.requestRejected: Icons.cancel,
      NotificationType.complaintInProgress: Icons.pending,
      NotificationType.complaintResolved: Icons.done_all,
      NotificationType.marketplace: Icons.shopping_bag,
      NotificationType.custom: Icons.notifications,
    };
    return icons[type] ?? Icons.notifications;
  }

  Color get color {
    const colors = {
      NotificationType.announcement: Color(0xFF6C63FF),
      NotificationType.timetable: Color(0xFF4A90E2),
      NotificationType.lostAndFound: Color(0xFFFFA726),
      NotificationType.jobPosting: Color(0xFF66BB6A),
      NotificationType.requestApproved: Color(0xFF26A69A),
      NotificationType.requestRejected: Color(0xFFEF5350),
      NotificationType.complaintInProgress: Color(0xFFFF9800),
      NotificationType.complaintResolved: Color(0xFF4CAF50),
      NotificationType.marketplace: Color(0xFF9C27B0),
    };
    return colors[type] ?? kPrimaryColor;
  }

  AppNotification copyWith({bool? isRead, bool? isPushSent}) {
    return AppNotification(
      id: id,
      title: title,
      body: body,
      type: type,
      priority: priority,
      universityId: universityId,
      userId: userId,
      imageUrl: imageUrl,
      imageBase64: imageBase64,
      data: data,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      isPushSent: isPushSent ?? this.isPushSent,
    );
  }
}

// ============================================================================
// 2. NOTIFICATION SERVICE
// ============================================================================

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static const String _projectId = 'my-project-859f5';
  StreamSubscription? _userRealtimeSub;

  // --- INITIALIZATION ---
  Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('User granted permission: ${settings.authorizationStatus}');

    // Android notification channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.max,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('Local Notification Tapped: ${response.payload}');
      },
    );

    // Foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground message received: ${message.messageId}');
      if (message.notification != null) {
        showLocalNotification(
          title: message.notification!.title ?? 'New Notification',
          body: message.notification!.body ?? '',
          payload: jsonEncode(message.data),
        );
      }
    });

    // Message opened app handler
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Message clicked: ${message.messageId}');
    });
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'High Importance Notifications',
      channelDescription: 'This channel is used for important notifications.',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  Future<void> subscribeToUniversity(String universityId) async {
    await _fcm.subscribeToTopic('university_$universityId');
  }

  // --- REAL-TIME LISTENER FOR USER NOTIFICATIONS ---
  void registerUserListener(String userId) {
    _userRealtimeSub?.cancel();
    final col = _db.collection('users').doc(userId).collection('notifications');
    _userRealtimeSub = col.orderBy('createdAt', descending: true).snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>?;
          if (data != null && data['isRead'] == false) {
            // Show local notification for new unread notifications
            if (!kIsWeb) {
              showLocalNotification(
                title: data['title'] ?? 'New Notification',
                body: data['body'] ?? '',
                payload: jsonEncode(data['data'] ?? {}),
              );
            }
          }
        }
      }
    });
  }

  void unregisterUserListener() {
    _userRealtimeSub?.cancel();
    _userRealtimeSub = null;
  }

  // --- DB Operations (USER-SPECIFIC) ---

  Future<List<AppNotification>> fetchNotifications({
    required String userId,
    required String universityId,
    bool unreadOnly = false,
  }) async {
    CollectionReference userCol = _db.collection('users').doc(userId).collection('notifications');
    Query query = userCol.orderBy('createdAt', descending: true);
    if (unreadOnly) query = query.where('isRead', isEqualTo: false);
    final snapshot = await query.get();
    return snapshot.docs.map(_docToNotification).toList();
  }

  Future<void> markAsReadForUser(String userId, String notificationId) async {
    final docRef = _db.collection('users').doc(userId).collection('notifications').doc(notificationId);
    await docRef.update({'isRead': true});
  }

  Future<void> deleteNotificationForUser(String userId, String notificationId) async {
    final docRef = _db.collection('users').doc(userId).collection('notifications').doc(notificationId);
    await docRef.delete();
  }

  Future<void> markAllAsRead(String userId, String universityId) async {
    final col = _db.collection('users').doc(userId).collection('notifications');
    final snapshot = await col.where('isRead', isEqualTo: false).get();
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  Future<int> getUnreadCount(String userId, String universityId) async {
    final snapshot = await _db
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .get();
    return snapshot.docs.length;
  }

  Stream<List<AppNotification>> streamNotifications({
    required String userId,
    required String universityId,
    bool unreadOnly = false,
    int limit = 50,
  }) {
    final col = _db.collection('users').doc(userId).collection('notifications');
    Query query = col.orderBy('createdAt', descending: true).limit(limit);
    if (unreadOnly) query = query.where('isRead', isEqualTo: false);
    return query.snapshots().map((snapshot) => snapshot.docs.map(_docToNotification).toList());
  }

  // --- PERSIST TOKEN FOR TARGETED NOTIFICATIONS ---
  Future<void> registerFcmToken({required String userId, required String token}) async {
    if (userId.isEmpty || token.isEmpty) return;
    await _db.collection('users').doc(userId).collection('fcmTokens').doc(token).set({
      'createdAt': FieldValue.serverTimestamp(),
      'platform': Platform.operatingSystem,
    });
  }

  // ========== NOTIFICATION CREATION & V1 PUSH TRIGGER ==========

  Future<void> _createAndPushNotification({
    required String title,
    required String body,
    required NotificationType type,
    required String universityId,
    String? userId,
    String? imageUrl,
    String? imageBase64,
    NotificationPriority priority = NotificationPriority.normal,
    Map<String, dynamic>? data,
  }) async {
    try {
      if (userId != null) {
        // TARGETED: Single user
        final userNotifRef = _db.collection('users').doc(userId).collection('notifications').doc();
        await userNotifRef.set({
          'title': title,
          'body': body,
          'type': type.toString().split('.').last,
          'priority': priority.toString().split('.').last,
          'universityId': universityId,
          'userId': userId,
          'imageUrl': imageUrl,
          'imageBase64': imageBase64,
          'data': data ?? {},
          'isRead': false,
          'isPushSent': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Send push to user's devices
        final tokensSnapshot = await _db.collection('users').doc(userId).collection('fcmTokens').get();
        for (var doc in tokensSnapshot.docs) {
          await _sendV1Push(
            token: doc.id,
            title: title,
            body: body,
            data: data,
          );
        }

        await userNotifRef.update({'isPushSent': true});
      } else {
        // BROADCAST: All users in university
        final usersQuery = await _db.collection('users').where('uniId', isEqualTo: universityId).get();
        
        for (final udoc in usersQuery.docs) {
          final uref = udoc.reference.collection('notifications').doc();
          await uref.set({
            'title': title,
            'body': body,
            'type': type.toString().split('.').last,
            'priority': priority.toString().split('.').last,
            'universityId': universityId,
            'userId': udoc.id,
            'imageUrl': imageUrl,
            'imageBase64': imageBase64,
            'data': data ?? {},
            'isRead': false,
            'isPushSent': false,
            'createdAt': FieldValue.serverTimestamp(),
          });

          // Send push to each user's devices
          final tokensSnapshot = await udoc.reference.collection('fcmTokens').get();
          for (var tdoc in tokensSnapshot.docs) {
            _sendV1Push(token: tdoc.id, title: title, body: body, data: data);
          }
        }
      }
    } catch (e) {
      debugPrint('Error creating notification: $e');
    }
  }

  // --- V1 API PUSH SENDER ---
  Future<void> _sendV1Push({
    String? token,
    String? topic,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final String response = await rootBundle.loadString('assets/service_account.json');
      final Map<String, dynamic> saMap = jsonDecode(response) as Map<String, dynamic>;
      final serviceAccountCredentials = ServiceAccountCredentials.fromJson(saMap);

      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final client = await clientViaServiceAccount(serviceAccountCredentials, scopes);

      final Map<String, dynamic> messagePayload = {
        'message': {
          if (token != null) 'token': token,
          if (topic != null) 'topic': topic,
          'notification': {
            'title': title,
            'body': body,
          },
          'data': data?.map((key, value) => MapEntry(key, value.toString())) ?? {},
          'android': {
            'priority': 'high',
            'notification': {
              'channelId': 'high_importance_channel',
              'sound': 'default',
            },
          },
          'apns': {
            'payload': {
              'aps': {
                'sound': 'default',
                'badge': 1,
              },
            },
          },
        }
      };

      final url = Uri.parse('https://fcm.googleapis.com/v1/projects/$_projectId/messages:send');

      final httpResponse = await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(messagePayload),
      );

      if (httpResponse.statusCode == 200) {
        debugPrint('V1 Notification Sent Successfully!');
      } else {
        debugPrint('Failed to send V1 Notification: ${httpResponse.body}');
      }

      client.close();
    } catch (e) {
      debugPrint('Error sending V1 Push: $e');
    }
  }

  // -------------------- ALL MODULE CONVENIENCE WRAPPERS --------------------

  Future<void> notifyAnnouncement({
    required String universityId,
    required String title,
    required String body,
    String? imageUrl,
    String? imageBase64,
    String? announcementId,
  }) async {
    await _createAndPushNotification(
      title: title,
      body: body,
      type: NotificationType.announcement,
      universityId: universityId,
      imageUrl: imageUrl,
      imageBase64: imageBase64,
      data: {'announcement_id': announcementId},
      priority: NotificationPriority.high,
    );
  }

  Future<void> notifyTimetableUpdate({
    required String universityId,
    String? className,
    String? title,
    String? body,
    String? timetableId,
    String? userId,
  }) async {
    final tTitle = title ?? (className != null ? 'Timetable update: $className' : 'Timetable update');
    final tBody = body ?? (className != null ? '$className schedule changed' : 'A timetable entry was updated');
    await _createAndPushNotification(
      title: tTitle,
      body: tBody,
      type: NotificationType.timetable,
      universityId: universityId,
      userId: userId,
      data: {'timetable_id': timetableId},
    );
  }

  Future<void> notifyLostAndFound({
    required String universityId,
    required String itemName,
    required bool isLost,
    String? postId,
  }) async {
    await _createAndPushNotification(
      title: isLost ? 'Item Lost Posted' : 'Item Found Posted',
      body: 'Someone posted about: $itemName',
      type: NotificationType.lostAndFound,
      universityId: universityId,
      data: {'post_id': postId, 'is_lost': isLost},
    );
  }

  Future<void> notifyJobPosting({
    required String universityId,
    String? companyName,
    String? position,
    String? title,
    String? body,
    String? jobId,
  }) async {
    final tTitle = title ?? (position != null ? position : 'New Job Posting');
    final tBody = body ?? (companyName != null ? '$companyName posted ${position ?? 'a job'}' : 'A new job was posted');
    await _createAndPushNotification(
      title: tTitle,
      body: tBody,
      type: NotificationType.jobPosting,
      universityId: universityId,
      data: {'job_id': jobId},
    );
  }

  Future<void> notifyMarketplace({
    required String universityId,
    required String itemName,
    required String price,
    String? postId,
    String? imageUrl,
  }) async {
    await _createAndPushNotification(
      title: 'New Item Listed',
      body: '$itemName listed for $price',
      type: NotificationType.marketplace,
      universityId: universityId,
      imageUrl: imageUrl,
      data: {'post_id': postId},
    );
  }

  Future<void> notifyRequestApproved({
    required String userId,
    required String universityId,
    required String requestType,
    String? requestId,
  }) async {
    await _createAndPushNotification(
      title: 'Request Approved',
      body: 'Your $requestType request has been approved',
      type: NotificationType.requestApproved,
      universityId: universityId,
      userId: userId,
      priority: NotificationPriority.high,
      data: {'request_id': requestId},
    );
  }

  Future<void> notifyRequestRejected({
    required String userId,
    required String universityId,
    required String requestType,
    String? reason,
    String? requestId,
  }) async {
    await _createAndPushNotification(
      title: 'Request Declined',
      body: reason ?? 'Your $requestType request was declined',
      type: NotificationType.requestRejected,
      universityId: universityId,
      userId: userId,
      priority: NotificationPriority.high,
      data: {'request_id': requestId},
    );
  }

  Future<void> notifyComplaintStatus({
    required String userId,
    required String universityId,
    required bool isResolved,
    required String complaintTitle,
    String? complaintId,
  }) async {
    await _createAndPushNotification(
      title: isResolved ? 'Complaint Resolved' : 'Complaint In Progress',
      body: isResolved
          ? 'Your complaint "$complaintTitle" has been resolved'
          : 'Your complaint "$complaintTitle" is being processed',
      type: isResolved ? NotificationType.complaintResolved : NotificationType.complaintInProgress,
      universityId: universityId,
      userId: userId,
      priority: isResolved ? NotificationPriority.high : NotificationPriority.normal,
      data: {'complaint_id': complaintId},
    );
  }

  Future<void> sendCustomNotification({
    required String title,
    required String body,
    required String universityId,
    String? userId,
    String? imageUrl,
    String? imageBase64,
    NotificationPriority priority = NotificationPriority.normal,
    Map<String, dynamic>? data,
  }) async {
    await _createAndPushNotification(
      title: title,
      body: body,
      type: NotificationType.custom,
      universityId: universityId,
      userId: userId,
      imageUrl: imageUrl,
      imageBase64: imageBase64,
      priority: priority,
      data: data,
    );
  }

  Future<Map<String, dynamic>> loadUserPreferences(String userId) async {
    try {
      final doc = await _db.collection('users').doc(userId).collection('settings').doc('notifications').get();
      if (!doc.exists) return {};
      return Map<String, dynamic>.from(doc.data() ?? {});
    } catch (e) {
      return {};
    }
  }

  Future<void> saveUserPreferences(String userId, Map<String, dynamic> prefs) async {
    try {
      await _db.collection('users').doc(userId).collection('settings').doc('notifications').set(prefs, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to save user notification prefs: $e');
    }
  }

  AppNotification _docToNotification(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    DateTime createdAt;
    final ts = data['createdAt'];
    if (ts is Timestamp) {
      createdAt = ts.toDate();
    } else {
      createdAt = DateTime.now();
    }

    NotificationType type = NotificationType.custom;
    try {
      final typeStr = (data['type'] as String?) ?? 'custom';
      type = NotificationType.values.firstWhere(
          (t) => t.toString().split('.').last == typeStr,
          orElse: () => NotificationType.custom);
    } catch (_) {}

    NotificationPriority priority = NotificationPriority.normal;
    try {
      final p = (data['priority'] as String?) ?? 'normal';
      priority = NotificationPriority.values.firstWhere(
          (t) => t.toString().split('.').last == p,
          orElse: () => NotificationPriority.normal);
    } catch (_) {}

    return AppNotification(
      id: doc.id,
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      type: type,
      priority: priority,
      universityId: data['universityId'] ?? '',
      userId: data['userId'] as String?,
      imageUrl: data['imageUrl'] as String?,
      imageBase64: data['imageBase64'] as String?,
      data: Map<String, dynamic>.from(data['data'] ?? {}),
      createdAt: createdAt,
      isRead: data['isRead'] as bool? ?? false,
      isPushSent: data['isPushSent'] as bool? ?? false,
    );
  }
}

// ============================================================================
// 3. NOTIFICATION PAGE UI (SAME AS BEFORE - NO CHANGES NEEDED)
// ============================================================================

class NotificationPage extends StatefulWidget {
  final String userId;
  final String universityId;

  const NotificationPage({
    super.key,
    required this.userId,
    required this.universityId,
  });

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage>
    with SingleTickerProviderStateMixin {
  final NotificationService _service = NotificationService();
  late Stream<List<AppNotification>> _notificationsStream;
  bool _showUnreadOnly = false;
  late TabController _tabController;
  int _unreadCount = 0;
  int _totalCount = 0;
  StreamSubscription<List<AppNotification>>? _subs;
  String _resolvedUniversityId = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    String uni = widget.universityId;
    try {
      if (uni.isEmpty && widget.userId.isNotEmpty) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
        if (userDoc.exists) {
          final data = userDoc.data();
          uni = (data != null && (data['uniId'] != null || data['universityId'] != null))
              ? (data['uniId'] ?? data['universityId']).toString()
              : '';
        }
      }

    } catch (e) {
      debugPrint('Failed to resolve universityId for notifications: $e');
    }

    _resolvedUniversityId = uni;

    _notificationsStream = _service.streamNotifications(
      userId: widget.userId,
      universityId: _resolvedUniversityId,
      unreadOnly: _showUnreadOnly,
    );

    _service.registerUserListener(widget.userId);

    _subs = _notificationsStream.listen((list) {
      if (!mounted) return;
      setState(() {
        _totalCount = list.length;
        _unreadCount = list.where((n) => !n.isRead).length;
      });
    });
  }

  @override
  void dispose() {
    _subs?.cancel();
    _service.unregisterUserListener();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _markAllAsRead() async {
    await _service.markAllAsRead(widget.userId, _resolvedUniversityId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All notifications marked as read'),
          backgroundColor: kPrimaryColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final appBarColor = Theme.of(context).appBarTheme.backgroundColor;
    final fgColor = Theme.of(context).appBarTheme.foregroundColor;
    final unselectedLabelColor = isDark ? Colors.white70 : kDarkTextColor.withOpacity(0.5);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: appBarColor,
        title: Text(
          'Notifications',
          style: TextStyle(
            color: fgColor,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(color: fgColor),
        actions: [
          if (_unreadCount > 0)
            IconButton(
              icon: const Icon(Icons.done_all, color: kPrimaryColor),
              onPressed: _markAllAsRead,
              tooltip: 'Mark all as read',
            ),
          IconButton(
            icon: const Icon(Icons.settings, color: kPrimaryColor),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NotificationSettingsPage(
                    userId: widget.userId,
                  ),
                ),
              );
            },
            tooltip: 'Settings',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: kPrimaryColor,
          unselectedLabelColor: unselectedLabelColor,
          indicatorColor: kPrimaryColor,
          onTap: (index) {
            setState(() {
              _showUnreadOnly = index == 1;
              _notificationsStream = _service.streamNotifications(
                userId: widget.userId,
                universityId: _resolvedUniversityId,
                unreadOnly: _showUnreadOnly,
              );
            });
          },
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('All'),
                  if (_totalCount > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_totalCount',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Unread'),
                  if (_unreadCount > 0)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_unreadCount',
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: _notificationsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: kPrimaryColor));
          }
          if (snapshot.hasError) {
            debugPrint('Notifications stream error: ${snapshot.error}');
            return Center(child: Text('Error loading notifications: ${snapshot.error}'));
          }
          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) return _buildEmptyState();

          return RefreshIndicator(
            onRefresh: () async {
              await _service.fetchNotifications(
                  userId: widget.userId, universityId: _resolvedUniversityId, unreadOnly: _showUnreadOnly);
            },
            color: kPrimaryColor,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final n = notifications[index];
                return _NotificationCard(
                  notification: n,
                  onTap: () => _handleNotificationTap(n),
                  onDismiss: () => _deleteNotification(n),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white70 : kDarkTextColor.withOpacity(0.6);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _showUnreadOnly ? Icons.notifications_none : Icons.notifications_off,
            size: 80,
            color: kPrimaryColor.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            _showUnreadOnly ? 'No unread notifications' : 'No notifications yet',
            style: TextStyle(
              fontSize: 18,
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _showUnreadOnly
                ? 'You\'re all caught up!'
                : 'We\'ll notify you when something happens',
            style: TextStyle(
              fontSize: 14,
              color: textColor.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNotificationTap(AppNotification notification) async {
    if (!notification.isRead) {
      await _service.markAsReadForUser(widget.userId, notification.id);
    }
    _showNotificationDetail(notification);
  }

  void _showNotificationDetail(AppNotification notification) {
    showDialog(
      context: context,
      builder: (context) => _NotificationDetailDialog(notification: notification),
    );
  }

  Future<void> _deleteNotification(AppNotification notification) async {
    await _service.deleteNotificationForUser(widget.userId, notification.id);
  }
}

// Notification Card
class _NotificationCard extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : kDarkTextColor;
    final cardColor = isDark ? const Color(0xFF2D2557).withOpacity(0.5) : kWhiteColor;

    return Dismissible(
      key: Key(notification.id),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: notification.isRead ? cardColor : kPrimaryColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: notification.isRead ? null : Border.all(color: kPrimaryColor.withOpacity(0.2), width: 1),
            boxShadow: [
              BoxShadow(
                color: textColor.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: notification.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(notification.icon, color: notification.color, size: 24),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: notification.isRead ? FontWeight.w600 : FontWeight.bold,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (notification.isNew && !notification.isRead)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: TextStyle(
                        fontSize: 14,
                        color: textColor.withOpacity(0.7),
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      notification.timeAgo,
                      style: const TextStyle(
                        fontSize: 12,
                        color: kSecondaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (!notification.isRead)
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: kPrimaryColor,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Notification Detail Dialog
class _NotificationDetailDialog extends StatelessWidget {
  final AppNotification notification;

  const _NotificationDetailDialog({required this.notification});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Theme.of(context).cardColor : kWhiteColor;
    final textColor = isDark ? Colors.white : kDarkTextColor;

    Uint8List? imageBytes;
    if (notification.imageBase64 != null) {
      try {
        imageBytes = base64Decode(notification.imageBase64!);
      } catch (e) {
        print('Error decoding base64 image: $e');
      }
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: notification.color,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Icon(notification.icon, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      notification.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (notification.imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          notification.imageUrl!,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                        ),
                      )
                    else if (imageBytes != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          imageBytes,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                        ),
                      ),
                    if (notification.imageUrl != null || imageBytes != null) const SizedBox(height: 16),
                    Text(
                      notification.body,
                      style: TextStyle(
                        fontSize: 16,
                        color: textColor,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 16, color: kSecondaryColor),
                        const SizedBox(width: 8),
                        Text(
                          notification.timeAgo,
                          style: const TextStyle(
                            fontSize: 14,
                            color: kSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 4. NOTIFICATION SETTINGS PAGE
// ============================================================================

class NotificationSettingsPage extends StatefulWidget {
  final String userId;

  const NotificationSettingsPage({super.key, required this.userId});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool announcements = true;
  bool timetable = true;
  bool lostAndFound = true;
  bool jobPostings = true;
  bool requests = true;
  bool complaints = true;
  bool marketplace = true;
  bool pushEnabled = true;
  bool soundEnabled = true;
  bool vibrationEnabled = true;
  final NotificationService _service = NotificationService();

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await _service.loadUserPreferences(widget.userId);
    setState(() {
      announcements = prefs['announcements'] ?? announcements;
      timetable = prefs['timetable'] ?? timetable;
      lostAndFound = prefs['lostAndFound'] ?? lostAndFound;
      jobPostings = prefs['jobPostings'] ?? jobPostings;
      requests = prefs['requests'] ?? requests;
      complaints = prefs['complaints'] ?? complaints;
      marketplace = prefs['marketplace'] ?? marketplace;
      pushEnabled = prefs['pushEnabled'] ?? pushEnabled;
      soundEnabled = prefs['soundEnabled'] ?? soundEnabled;
      vibrationEnabled = prefs['vibrationEnabled'] ?? vibrationEnabled;
    });
  }

  Future<void> _save() async {
    await _service.saveUserPreferences(widget.userId, {
      'announcements': announcements,
      'timetable': timetable,
      'lostAndFound': lostAndFound,
      'jobPostings': jobPostings,
      'requests': requests,
      'complaints': complaints,
      'marketplace': marketplace,
      'pushEnabled': pushEnabled,
      'soundEnabled': soundEnabled,
      'vibrationEnabled': vibrationEnabled,
    });
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final appBarColor = Theme.of(context).appBarTheme.backgroundColor;
    final fgColor = Theme.of(context).appBarTheme.foregroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: appBarColor,
        title: Text(
          'Notification Settings',
          style: TextStyle(
            color: fgColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(color: fgColor),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            'Notification Types',
            [
              _buildSwitch('Announcements', announcements, (v) async {
                setState(() => announcements = v);
                await _save();
              }),
              _buildSwitch('Timetable Updates', timetable, (v) async {
                setState(() => timetable = v);
                await _save();
              }),
              _buildSwitch('Lost & Found', lostAndFound, (v) async {
                setState(() => lostAndFound = v);
                await _save();
              }),
              _buildSwitch('Job Postings', jobPostings, (v) async {
                setState(() => jobPostings = v);
                await _save();
              }),
              _buildSwitch('Request Status', requests, (v) async {
                setState(() => requests = v);
                await _save();
              }),
              _buildSwitch('Complaint Updates', complaints, (v) async {
                setState(() => complaints = v);
                await _save();
              }),
              _buildSwitch('Marketplace', marketplace, (v) async {
                setState(() => marketplace = v);
                await _save();
              }),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            'Push Notifications',
            [
              _buildSwitch('Enable Push Notifications', pushEnabled, (v) async {
                setState(() => pushEnabled = v);
                await _save();
              }),
              _buildSwitch('Sound', soundEnabled, (v) async {
                setState(() => soundEnabled = v);
                await _save();
              }),
              _buildSwitch('Vibration', vibrationEnabled, (v) async {
                setState(() => vibrationEnabled = v);
                await _save();
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sectionColor = isDark ? Theme.of(context).cardColor : kWhiteColor;
    final titleColor = isDark ? Colors.white : kDarkTextColor;

    return Container(
      decoration: BoxDecoration(
        color: sectionColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: kDarkTextColor.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: titleColor,
              ),
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitch(String title, bool value, Function(bool) onChanged) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white70 : kDarkTextColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              color: textColor,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: kPrimaryColor,
          ),
        ],
      ),
    );
  }
}

// AdminNotificationSender (same as before, no changes needed)
class AdminNotificationSender extends StatefulWidget {
  final String adminId;
  final String universityId;

  const AdminNotificationSender({
    super.key,
    required this.adminId,
    required this.universityId,
  });

  @override
  State<AdminNotificationSender> createState() => _AdminNotificationSenderState();
}

class _AdminNotificationSenderState extends State<AdminNotificationSender> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _imageUrlController = TextEditingController();
  String? _imageBase64;
  NotificationPriority _priority = NotificationPriority.normal;
  bool _isBroadcast = true;
  String _targetUserId = '';
  bool _isSubmitting = false;
  final NotificationService _service = NotificationService();

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    // In real app, use image_picker package
    setState(() {
      _imageBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image selected (demo mode)'),
          backgroundColor: kPrimaryColor,
        ),
      );
    }
  }

  Future<void> _sendNotification() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isBroadcast && _targetUserId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a target user ID'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _service.sendCustomNotification(
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        universityId: widget.universityId,
        userId: _isBroadcast ? null : _targetUserId.trim(),
        imageUrl: _imageUrlController.text.trim().isEmpty ? null : _imageUrlController.text.trim(),
        imageBase64: _imageBase64,
        priority: _priority,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isBroadcast
                  ? 'Notification sent to all students'
                  : 'Notification sent to user successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final cardColor = isDark ? Theme.of(context).cardColor : kWhiteColor;
    final textColor = isDark ? Colors.white : kDarkTextColor;
    final hintColor = isDark ? Colors.white54 : kSecondaryColor;

    InputDecoration getInputDecoration(String label, {IconData? icon, String? hint}) {
      return InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: hintColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kPrimaryColor, width: 2),
        ),
        filled: true,
        fillColor: cardColor,
        prefixIcon: icon != null ? Icon(icon, color: hintColor) : null,
        hintText: hint,
        hintStyle: TextStyle(color: hintColor.withOpacity(0.5)),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: cardColor,
        title: Text(
          'Send Custom Notification',
          style: TextStyle(
            color: textColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(color: textColor),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: kPrimaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kPrimaryColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: kPrimaryColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Custom notifications will be sent as push notifications and appear in the notification feed',
                        style: TextStyle(
                          fontSize: 14,
                          color: textColor.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Title Field
              TextFormField(
                controller: _titleController,
                style: TextStyle(color: textColor),
                decoration: getInputDecoration('Title *', icon: Icons.title),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Please enter a title' : null,
              ),

              const SizedBox(height: 16),

              // Body Field
              TextFormField(
                controller: _bodyController,
                style: TextStyle(color: textColor),
                decoration: getInputDecoration('Message *', icon: Icons.message),
                maxLines: 4,
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Please enter a message' : null,
              ),

              const SizedBox(height: 16),

              // Priority Selector
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Priority',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: NotificationPriority.values.map((priority) {
                        final isSelected = _priority == priority;
                        return ChoiceChip(
                          label: Text(priority.toString().split('.').last.toUpperCase()),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() => _priority = priority);
                          },
                          selectedColor: kPrimaryColor,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : textColor,
                            fontWeight: FontWeight.bold,
                          ),
                          backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Target Selection
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Broadcast to All Students',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isBroadcast
                                  ? 'Will send to all students in your university'
                                  : 'Will send to a specific user',
                              style: TextStyle(
                                fontSize: 12,
                                color: textColor.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: _isBroadcast,
                          onChanged: (value) {
                            setState(() => _isBroadcast = value);
                          },
                          activeColor: kPrimaryColor,
                        ),
                      ],
                    ),
                    if (!_isBroadcast) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        style: TextStyle(color: textColor),
                        decoration: getInputDecoration(
                          'Target User ID *',
                          icon: Icons.person,
                          hint: 'Enter user ID',
                        ),
                        onChanged: (value) {
                          setState(() => _targetUserId = value);
                        },
                        validator: (value) => !_isBroadcast && (value == null || value.trim().isEmpty)
                            ? 'Please enter a user ID'
                            : null,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Image Options
              Text(
                'Add Image (Optional)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),

              const SizedBox(height: 12),

              // Image URL Field
              TextFormField(
                controller: _imageUrlController,
                style: TextStyle(color: textColor),
                decoration: getInputDecoration(
                  'Image URL',
                  icon: Icons.link,
                  hint: 'https://example.com/image.jpg',
                ),
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                      child: Container(
                          height: 1, color: isDark ? Colors.white12 : Colors.grey.shade300)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        color: textColor.withOpacity(0.5),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                      child: Container(
                          height: 1, color: isDark ? Colors.white12 : Colors.grey.shade300)),
                ],
              ),

              const SizedBox(height: 12),

              // Upload Image Button
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.upload_file, color: kPrimaryColor),
                label: Text(
                  _imageBase64 != null ? 'Image Selected ✓' : 'Upload Image (Base64)',
                  style: const TextStyle(color: kPrimaryColor),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: kPrimaryColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              if (_imageBase64 != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.image, size: 50, color: kPrimaryColor),
                          const SizedBox(height: 8),
                          Text(
                            'Image Preview',
                            style: TextStyle(
                              color: textColor.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // Send Button
              ElevatedButton(
                onPressed: _isSubmitting ? null : _sendNotification,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.send, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _isBroadcast ? 'Send to All Students' : 'Send to User',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 16),

              // Preview Card
              if (_titleController.text.isNotEmpty || _bodyController.text.isNotEmpty) ...[
                const Divider(height: 32),
                Text(
                  'Preview',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kPrimaryColor.withOpacity(0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: textColor.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.notifications, color: kPrimaryColor, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _titleController.text.isEmpty
                                  ? 'Notification Title'
                                  : _titleController.text,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _bodyController.text.isEmpty
                                  ? 'Notification message will appear here'
                                  : _bodyController.text,
                              style: TextStyle(
                                fontSize: 14,
                                color: textColor.withOpacity(0.7),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getPriorityColor().withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _priority.toString().split('.').last.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: _getPriorityColor(),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  _isBroadcast ? Icons.people : Icons.person,
                                  size: 14,
                                  color: kSecondaryColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isBroadcast ? 'All Students' : 'Single User',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: kSecondaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getPriorityColor() {
    switch (_priority) {
      case NotificationPriority.low:
        return Colors.grey;
      case NotificationPriority.normal:
        return Colors.blue;
      case NotificationPriority.high:
        return Colors.orange;
      case NotificationPriority.urgent:
        return Colors.red;
    }
  }
}

// ============================================================================
// USAGE EXAMPLES FOR ALL MODULES
// ============================================================================

/*
// HOW TO USE IN YOUR APP:

// 1. INITIALIZE IN main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Initialize notification service
  await NotificationService().init();
  
  runApp(MyApp());
}

// 2. REGISTER USER TOKEN (After login)
Future<void> setupNotifications(String userId, String universityId) async {
  final token = await FirebaseMessaging.instance.getToken();
  if (token != null) {
    await NotificationService().registerFcmToken(userId: userId, token: token);
  }
  await NotificationService().subscribeToUniversity(universityId);
}

// 3. SEND NOTIFICATIONS FROM DIFFERENT MODULES:

// --- ANNOUNCEMENTS MODULE ---
await NotificationService().notifyAnnouncement(
  universityId: 'uni_123',
  title: 'Important Announcement',
  body: 'Classes are suspended tomorrow due to heavy rain',
  imageUrl: 'https://example.com/announcement.jpg',
  announcementId: 'ann_456',
);

// --- TIMETABLE MODULE ---
await NotificationService().notifyTimetableUpdate(
  universityId: 'uni_123',
  className: 'Computer Science 101',
  title: 'Schedule Change',
  body: 'CS101 lecture moved to Room 305',
  timetableId: 'tt_789',
  userId: 'user_123', // Optional: for specific user
);

// --- LOST & FOUND MODULE ---
await NotificationService().notifyLostAndFound(
  universityId: 'uni_123',
  itemName: 'Blue Backpack',
  isLost: true,
  postId: 'lf_101',
);

// --- JOB POSTINGS MODULE ---
await NotificationService().notifyJobPosting(
  universityId: 'uni_123',
  companyName: 'Tech Corp',
  position: 'Software Engineer Intern',
  jobId: 'job_202',
);

// --- MARKETPLACE MODULE ---
await NotificationService().notifyMarketplace(
  universityId: 'uni_123',
  itemName: 'Calculus Textbook',
  price: '\$50',
  postId: 'mp_303',
  imageUrl: 'https://example.com/book.jpg',
);

// --- REQUEST APPROVAL MODULE ---
await NotificationService().notifyRequestApproved(
  userId: 'user_123',
  universityId: 'uni_123',
  requestType: 'Leave Application',
  requestId: 'req_404',
);

// --- REQUEST REJECTION MODULE ---
await NotificationService().notifyRequestRejected(
  userId: 'user_123',
  universityId: 'uni_123',
  requestType: 'Document Request',
  reason: 'Incomplete information provided',
  requestId: 'req_505',
);

// --- COMPLAINT STATUS MODULE ---
await NotificationService().notifyComplaintStatus(
  userId: 'user_123',
  universityId: 'uni_123',
  isResolved: true,
  complaintTitle: 'Wi-Fi not working in library',
  complaintId: 'cmp_606',
);

// --- CUSTOM NOTIFICATION (Admin) ---
await NotificationService().sendCustomNotification(
  title: 'Emergency Alert',
  body: 'Campus will close at 3 PM today',
  universityId: 'uni_123',
  userId: null, // null = broadcast to all
  priority: NotificationPriority.urgent,
  data: {'type': 'emergency', 'action': 'evacuate'},
);

// 4. NAVIGATION TO NOTIFICATION PAGE
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => NotificationPage(
      userId: currentUser.id,
      universityId: currentUser.universityId,
    ),
  ),
);

// 5. ADMIN PANEL - SEND CUSTOM NOTIFICATION
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => AdminNotificationSender(
      adminId: currentAdmin.id,
      universityId: currentAdmin.universityId,
    ),
  ),
);

// 6. GET UNREAD COUNT (For Badge)
final unreadCount = await NotificationService().getUnreadCount(
  userId: 'user_123',
  universityId: 'uni_123',
);

// 7. STREAM NOTIFICATIONS (Real-time updates)
StreamBuilder<List<AppNotification>>(
  stream: NotificationService().streamNotifications(
    userId: 'user_123',
    universityId: 'uni_123',
    unreadOnly: false,
  ),
  builder: (context, snapshot) {
    final notifications = snapshot.data ?? [];
    return ListView.builder(
      itemCount: notifications.length,
      itemBuilder: (context, index) {
        return ListTile(
          title: Text(notifications[index].title),
          subtitle: Text(notifications[index].body),
        );
      },
    );
  },
);

*/