import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
// import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';

// --- 1. IMPORT YOUR THEME FILE ---
import 'theme_colors.dart'; 

// --- 2. MODULE IMPORTS WITH 'HIDE' TO PREVENT CONFLICTS ---
// We tell Dart: "Import these files, but IGNORE their color definitions"
// so they don't clash with theme_colors.dart

import 'student_marketplace.dart' hide kPrimaryColor, kSecondaryColor, kBackgroundColor, kDarkBackgroundColor, kWhiteColor, kDarkTextColor;
import 'homepage/profile_screen.dart' hide kPrimaryColor, kSecondaryColor, kBackgroundColor, kDarkBackgroundColor, kWhiteColor, kDarkTextColor;
import 'announcements/student_announcement_view.dart' hide kPrimaryColor, kSecondaryColor, kBackgroundColor, kDarkBackgroundColor, kWhiteColor, kDarkTextColor;
import 'notifications.dart'; // You already fixed this file, so no hide needed usually, but safe to add if needed.
import 'complaints/views/student_complaint_view.dart';
import 'complaints/views/create_complaint_screen.dart';
import 'complaints/views/admin_complaint_list.dart';
import 'shared.dart'; 
import 'auth.dart'; 
import 'lost_and_found.dart'; 
import 'timetable/index.dart'; 
import 'homepage/index.dart'; 
import 'homepage/admin_dashboard.dart';
import 'ai_study_planner/ai_study_planner.dart' hide kPrimaryColor, kSecondaryColor, kBackgroundColor, kDarkBackgroundColor, kWhiteColor, kDarkTextColor;
import 'timetable/placements/student_placement_screen.dart';
import 'timetable/placements/recruiter_admin_panel.dart';
import 'timetable/FACULTY/faculty_dashboard.dart'; 
import 'timetable/FACULTY/student_connect.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with error handling
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e, s) {
    final msg = e.toString();
    if (msg.contains('already exists') || msg.contains('firebase app') && msg.contains('already')) {
      // swallow duplicate initialization error
    } else {
      runApp(ErrorReportApp(exception: e, stack: s));
      return;
    }
  }
  
  // Disable persistence for web compatibility
  try {
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
  } catch (e) {}

  // Initialize Notifications
  try {
    if (!kIsWeb) {
      await NotificationService().init();
      
      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await NotificationService().registerFcmToken(userId: user.uid, token: token);
        }
      });
      
      final token = await FirebaseMessaging.instance.getToken();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && token != null) {
        await NotificationService().registerFcmToken(userId: user.uid, token: token);
      }
    }
  } catch (e) {
    debugPrint('Notification Service Init Error: $e');
  }

  // Log recruiter creds if available (Debug only)
  try {
    final recruiterEmail = Platform.environment['RECRUITER_ADMIN_EMAIL'] ?? 'recruiter@admin.test';
    final recruiterPassword = Platform.environment['RECRUITER_ADMIN_PASSWORD'] ?? 'Recruiter123!';
    debugPrint('RECRUITER_ADMIN_CREDENTIALS:');
    debugPrint('  email: $recruiterEmail');
    debugPrint('  password: $recruiterPassword');
  } catch (_) {}
  
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Scaffold(
      appBar: AppBar(title: const Text('Error')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('An error occurred',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(details.exceptionAsString()),
              const SizedBox(height: 12),
              Text(details.stack.toString()),
            ],
          ),
        ),
      ),
    );
  };

  runApp(const UniversityApp());
}

// Background handler
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
  debugPrint('FCM background message received: ${message.messageId}');
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> _initLocalNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings();
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      final payload = response.payload;
      try {
        final ctx = Get.context;
        if (ctx != null && payload != null && payload.isNotEmpty) {
          Get.toNamed('/notifications');
        }
      } catch (_) {}
    },
  );

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'eduverse_high',
    'Eduverse High Priority',
    importance: Importance.high,
    description: 'High priority notifications for Eduverse',
  );
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

class ErrorReportApp extends StatelessWidget {
  final Object exception;
  final StackTrace stack;
  const ErrorReportApp({super.key, required this.exception, required this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: true,
      home: Scaffold(
        appBar: AppBar(title: const Text('Init Error')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Firebase initialization failed',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(exception.toString()),
                const SizedBox(height: 12),
                Text(stack.toString()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UniversityApp extends StatelessWidget {
  const UniversityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(392, 803),
      builder: (context, child) {
        return GetMaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Eduverse',
          
          // ==================================================================
          // 3. LIGHT THEME CONFIGURATION
          // ==================================================================
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            primaryColor: kPrimaryColor, // Uses theme_colors.dart
            scaffoldBackgroundColor: kBackgroundColor,
            fontFamily: 'Inter',

            colorScheme: ColorScheme.fromSeed(
              seedColor: kPrimaryColor,
              primary: kPrimaryColor,
              secondary: kSecondaryColor,
              surface: kWhiteColor,
              background: kBackgroundColor,
              onBackground: kDarkTextColor,
            ),

            appBarTheme: const AppBarTheme(
              backgroundColor: kWhiteColor,
              foregroundColor: kDarkTextColor,
              elevation: 0,
              centerTitle: true,
            ),
            
            cardTheme: CardThemeData(
              color: kWhiteColor,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),

          // ==================================================================
          // 4. DARK THEME CONFIGURATION
          // ==================================================================
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            primaryColor: kPrimaryColor,
            scaffoldBackgroundColor: kDarkBackgroundColor, // Uses theme_colors.dart
            fontFamily: 'Inter',

            colorScheme: ColorScheme.dark(
              primary: kPrimaryColor,
              secondary: kSecondaryColor,
              surface: kDarkBackgroundColor.withOpacity(0.8),
              background: kDarkBackgroundColor,
              onBackground: kWhiteColor,
            ),

            appBarTheme: const AppBarTheme(
              backgroundColor: kDarkBackgroundColor,
              foregroundColor: kWhiteColor,
              elevation: 0,
              centerTitle: true,
            ),
          ),

          themeMode: ThemeMode.system, 

          home: const AuthGate(),

          getPages: [
            GetPage(name: '/login', page: () => const LoginView()),
            GetPage(name: '/dashboard', page: () => const HomeDashboard()), 
            GetPage(name: '/admin', page: () => const AdminDashboard()),
            GetPage(name: '/lost-and-found', page: () => const LostAndFoundLandingPage()), 
            GetPage(name: '/timetable', page: () => const TimetableScreen()), 
            GetPage(name: '/marketplace', page: () => const StudentMarketplace()),
            GetPage(name: '/complaints', page: () => StudentComplaintView()),
            GetPage(name: '/complaints/create', page: () => const CreateComplaintScreen()),
            GetPage(name: '/complaints/admin', page: () => AdminComplaintList()),
            GetPage(name: '/ai-study-planner', page: () => const StudyPlannerModule()),
            
            // Placement module
            GetPage(name: '/student-placement', page: () => const StudentPlacementScreen()),
            GetPage(name: '/recruiter-dashboard', page: () => const RecruiterAdminPanel()),

            // Faculty Module
            GetPage(name: '/faculty-dashboard', page: () => const FacultyDashboardScreen()),
            GetPage(name: '/faculty-connect', page: () => const MainNavigationScreen()),

            GetPage(name: '/profile', page: () => const ProfileScreen()),

            // Announcements Routes
            GetPage(name: '/announcements', page: () => const StudentAnnouncementFeed()),
            GetPage(name: '/student_announcements_view', page: () => const StudentAnnouncementFeed()),
            
            // Notifications Routes
            GetPage(
              name: '/notifications',
              page: () {
                final args = Get.arguments as Map<String, dynamic>?;
                return NotificationPage(
                  userId: args?['userId'] ?? FirebaseAuth.instance.currentUser?.uid ?? '',
                  universityId: args?['universityId'] ?? '',
                );
              },
            ),
            GetPage(
              name: '/notification_settings',
              page: () {
                final args = Get.arguments as Map<String, dynamic>?;
                return NotificationSettingsPage(userId: args?['userId'] ?? FirebaseAuth.instance.currentUser?.uid ?? '');
              },
            ),
          ],
        );
      },
    );
  }
}

// AuthGate (Preserved)
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    if (user != null) {
      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if(!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          
          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final role = userData?['role'] ?? 'student';

            if (role == 'faculty') return const FacultyDashboardScreen();
            if (role == 'recruiter') return const RecruiterAdminPanel();
            if (role == 'super_admin') return const AdminDashboard();
            if (role == 'admin') return user.emailVerified ? const HomeDashboard() : const VerifyEmailView();

            return user.emailVerified ? const HomeDashboard() : const VerifyEmailView();
        }
      );
    }
    
    return const LoginView();
  }
}