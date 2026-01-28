// pubspec.yaml dependencies needed:
// get: ^4.6.6
// intl: ^0.18.1
// cloud_firestore: ^4.13.6
// firebase_auth: ^4.15.3
// firebase_core: ^2.24.2

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// --- IMPORT GLOBAL THEME ---
// (Adjust path if needed, e.g., 'package:your_app_name/theme_colors.dart')
import '../../theme_colors.dart';

void main() {
  runApp(const EduverseStudentApp());
}

// ============================================================================
// APP ROOT
// ============================================================================
class EduverseStudentApp extends StatelessWidget {
  const EduverseStudentApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Eduverse - Student Portal',
      debugShowCheckedModeBanner: false,
      // Use the global theme definitions if available via Get/Global context, 
      // otherwise define local defaults matching theme_colors.dart
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: kPrimaryColor,
        scaffoldBackgroundColor: kBackgroundColor,
        cardColor: kWhiteColor,
        fontFamily: 'Poppins',
        appBarTheme: const AppBarTheme(
          backgroundColor: kWhiteColor,
          foregroundColor: kDarkTextColor,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: kPrimaryColor,
        scaffoldBackgroundColor: kDarkBackgroundColor,
        cardColor: const Color(0xFF1E1E2C), // Slightly lighter than bg
        fontFamily: 'Poppins',
        appBarTheme: const AppBarTheme(
          backgroundColor: kDarkBackgroundColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const MainNavigationScreen(),
    );
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================
class FacultyUser {
  final String id;
  final String name;
  final String department;
  final String photoUrl;
  final bool isAvailable;
  final String officeHours;
  final String title;
  final String email;

  FacultyUser({
    required this.id,
    required this.name,
    required this.department,
    required this.photoUrl,
    required this.isAvailable,
    required this.officeHours,
    this.title = '',
    this.email = '',
  });

  factory FacultyUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FacultyUser(
      id: doc.id,
      name: data['name'] ?? 'Unknown',
      department: data['dept'] ?? 'N/A',
      photoUrl: data['imageUrl'] ?? '',
      isAvailable: data['isAvailable'] ?? false,
      officeHours: data['officeHours'] ?? 'Not specified',
      title: data['title'] ?? '',
      email: data['email'] ?? '',
    );
  }
}

class AppointmentModel {
  final String id;
  final String studentId;
  final String facultyId;
  final String facultyName;
  final String facultyDept;
  final String facultyPhoto;
  final DateTime requestDate;
  final String requestTime;
  final String reason;
  final String status; // pending, confirmed, cancelled
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;

  AppointmentModel({
    required this.id,
    required this.studentId,
    required this.facultyId,
    required this.facultyName,
    required this.facultyDept,
    required this.facultyPhoto,
    required this.requestDate,
    required this.requestTime,
    required this.reason,
    required this.status,
    this.confirmedAt,
    this.cancelledAt,
  });

  factory AppointmentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppointmentModel(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      facultyId: data['facultyId'] ?? '',
      facultyName: data['facultyName'] ?? 'Unknown',
      facultyDept: data['facultyDept'] ?? 'N/A',
      facultyPhoto: data['facultyPhoto'] ?? '',
      requestDate: (data['requestDate'] as Timestamp).toDate(),
      requestTime: data['requestTime'] ?? '',
      reason: data['reason'] ?? '',
      status: data['status'] ?? 'pending',
      confirmedAt: data['confirmedAt'] != null 
          ? (data['confirmedAt'] as Timestamp).toDate() 
          : null,
      cancelledAt: data['cancelledAt'] != null 
          ? (data['cancelledAt'] as Timestamp).toDate() 
          : null,
    );
  }
}

// ============================================================================
// CONTROLLERS
// ============================================================================
class FacultyController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final RxList<FacultyUser> allFaculty = <FacultyUser>[].obs;
  final RxList<FacultyUser> filteredFaculty = <FacultyUser>[].obs;
  final RxString searchQuery = ''.obs;
  final RxBool isLoading = true.obs;
  final RxString selectedDepartment = 'All'.obs;

  @override
  void onInit() {
    super.onInit();
    loadFacultyFromFirestore();
    ever(searchQuery, (_) => filterFaculty());
    ever(selectedDepartment, (_) => filterFaculty());
  }

  // Load faculty from Firestore
  void loadFacultyFromFirestore() {
    isLoading.value = true;

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      isLoading.value = false;
      Get.snackbar('Error', 'Not signed in', backgroundColor: Colors.red);
      return;
    }

    // Read student's uniId first, then listen to faculty for that uni only
    _firestore.collection('users').doc(uid).get().then((userDoc) {
      final myUniId = userDoc.data()?['uniId'] as String?;
      if (myUniId == null) {
        isLoading.value = false;
        Get.snackbar('Error', 'Your account has no university assigned', backgroundColor: Colors.orange);
        return;
      }

      _firestore
          .collection('users')
          .where('role', isEqualTo: 'faculty')
          .where('uniId', isEqualTo: myUniId)
          .snapshots()
          .listen((snapshot) {
        allFaculty.value = snapshot.docs
            .map((doc) => FacultyUser.fromFirestore(doc))
            .toList();
        filterFaculty();
        isLoading.value = false;
        debugPrint('Loaded ${allFaculty.length} faculty for uni=$myUniId');
      }, onError: (error) {
        isLoading.value = false;
        Get.snackbar(
          'Error',
          'Failed to load faculty: $error',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      });
    }).catchError((e) {
      isLoading.value = false;
      Get.snackbar('Error', 'Failed to determine your university: $e', backgroundColor: Colors.red);
    });
  }

  void filterFaculty() {
    List<FacultyUser> result = allFaculty;

    // Filter by department
    if (selectedDepartment.value != 'All') {
      result = result
          .where((f) => f.department == selectedDepartment.value)
          .toList();
    }

    // Filter by search query
    if (searchQuery.value.isNotEmpty) {
      final query = searchQuery.value.toLowerCase();
      result = result.where((faculty) {
        return faculty.name.toLowerCase().contains(query) ||
            faculty.department.toLowerCase().contains(query) ||
            faculty.title.toLowerCase().contains(query);
      }).toList();
    }

    filteredFaculty.value = result;
  }

  List<String> getDepartments() {
    final depts = allFaculty.map((f) => f.department).toSet().toList();
    depts.sort();
    return ['All', ...depts];
  }
}

class BookingController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final Rx<FacultyUser?> selectedFaculty = Rx<FacultyUser?>(null);
  final RxString selectedTimeSlot = ''.obs;
  final RxString selectedDate = ''.obs;
  final TextEditingController reasonController = TextEditingController();
  final RxBool isBooking = false.obs;

  // Generate available time slots
  List<String> generateTimeSlots() {
    final slots = <String>[];
    for (int hour = 9; hour <= 17; hour++) {
      slots.add('${hour.toString().padLeft(2, '0')}:00');
      if (hour < 17) {
        slots.add('${hour.toString().padLeft(2, '0')}:30');
      }
    }
    return slots;
  }

  // Generate available dates (next 7 days)
  List<String> generateDates() {
    final dates = <String>[];
    final now = DateTime.now();
    for (int i = 1; i <= 7; i++) {
      final date = now.add(Duration(days: i));
      dates.add(DateFormat('yyyy-MM-dd').format(date));
    }
    return dates;
  }

  Future<void> bookAppointment() async {
    if (selectedFaculty.value == null) {
      Get.snackbar('Error', 'Please select a faculty member');
      return;
    }

    if (selectedTimeSlot.value.isEmpty) {
      Get.snackbar('Error', 'Please select a time slot');
      return;
    }

    if (selectedDate.value.isEmpty) {
      Get.snackbar('Error', 'Please select a date');
      return;
    }

    if (reasonController.text.trim().isEmpty) {
      Get.snackbar('Error', 'Please provide a reason for visit');
      return;
    }

    isBooking.value = true;

    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) {
        throw Exception('User not authenticated');
      }

      // Get student info
      final studentDoc = await _firestore.collection('users').doc(uid).get();
      final studentData = studentDoc.data();

      // Parse date
      final requestDateTime = DateTime.parse(selectedDate.value);
      // Parse time slot into hours/minutes
      int hour = 0;
      int minute = 0;
      try {
        final parts = selectedTimeSlot.value.split(':');
        hour = int.parse(parts[0]);
        minute = int.parse(parts[1]);
      } catch (_) {}

      final scheduledDateTime = DateTime(
        requestDateTime.year,
        requestDateTime.month,
        requestDateTime.day,
        hour,
        minute,
      );

      // Create appointment
      await _firestore.collection('appointments').add({
        'studentId': uid,
        'studentName': studentData?['name'] ?? 'Student',
        'studentEmail': studentData?['email'] ?? '',
        'facultyId': selectedFaculty.value!.id,
        // also include profId for faculty dashboard compatibility
        'profId': selectedFaculty.value!.id,
        'facultyName': selectedFaculty.value!.name,
        'facultyDept': selectedFaculty.value!.department,
        'facultyPhoto': selectedFaculty.value!.photoUrl,
        'requestDate': Timestamp.fromDate(requestDateTime),
        'requestTime': selectedTimeSlot.value,
        // helpful for faculty-side queries & calendar display
        'scheduledTime': Timestamp.fromDate(scheduledDateTime),
        'reason': reasonController.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Show success dialog
      Get.dialog(
        SuccessDialog(
          facultyName: selectedFaculty.value!.name,
          date: DateFormat('MMM dd, yyyy').format(requestDateTime),
          time: selectedTimeSlot.value,
        ),
        barrierDismissible: false,
      );

      // Reset form
      selectedTimeSlot.value = '';
      selectedDate.value = '';
      reasonController.clear();
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to book appointment: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      isBooking.value = false;
    }
  }

  @override
  void onClose() {
    reasonController.dispose();
    super.onClose();
  }
}

class AppointmentController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final RxList<AppointmentModel> upcomingAppointments = <AppointmentModel>[].obs;
  final RxList<AppointmentModel> historyAppointments = <AppointmentModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxString selectedTab = 'Upcoming'.obs;

  @override
  void onInit() {
    super.onInit();
    loadAppointments();
  }

  void loadAppointments() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    isLoading.value = true;

    _firestore
        .collection('appointments')
        .where('studentId', isEqualTo: uid)
        .orderBy('requestDate', descending: true)
        .snapshots()
        .listen((snapshot) {
      final now = DateTime.now();
      final allAppointments = snapshot.docs
          .map((doc) => AppointmentModel.fromFirestore(doc))
          .toList();

      // Separate upcoming and history
      upcomingAppointments.value = allAppointments
          .where((apt) =>
              apt.requestDate.isAfter(now) || apt.status == 'pending')
          .toList();

      historyAppointments.value = allAppointments
          .where((apt) =>
              apt.requestDate.isBefore(now) && apt.status != 'pending')
          .toList();

      isLoading.value = false;
    }, onError: (error) {
      isLoading.value = false;
      Get.snackbar(
        'Error',
        'Failed to load appointments: $error',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    });
  }

  Future<void> cancelAppointment(String appointmentId) async {
    try {
      final confirmed = await Get.dialog<bool>(
        AlertDialog(
          title: const Text('Cancel Appointment'),
          content: const Text('Are you sure you want to cancel this appointment?'),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Get.back(result: true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Yes, Cancel'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await _firestore.collection('appointments').doc(appointmentId).update({
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
        });

        Get.snackbar(
          'Success',
          'Appointment cancelled successfully',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to cancel appointment: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Future<void> rescheduleAppointment(String appointmentId) async {
    Get.snackbar(
      'Info',
      'Reschedule feature coming soon',
      backgroundColor: kPrimaryColor,
      colorText: Colors.white,
    );
  }
}

// ============================================================================
// MAIN NAVIGATION SCREEN
// ============================================================================
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({Key? key}) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const FacultyDirectoryScreen(),
    const AppointmentsScreen(),
    const PlaceholderScreen(title: 'Chat'),
    const PlaceholderScreen(title: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    // Dynamic Theme
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBarColor = isDark ? Theme.of(context).cardColor : Colors.white;
    final unselectedColor = isDark ? Colors.white54 : Colors.grey;

    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navBarColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
            ),
          ],
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: navBarColor,
          selectedItemColor: kPrimaryColor,
          unselectedItemColor: unselectedColor,
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today),
              label: 'Appointments',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              label: 'Chat',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// FACULTY DIRECTORY SCREEN
// ============================================================================
class FacultyDirectoryScreen extends StatelessWidget {
  const FacultyDirectoryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final FacultyController controller = Get.put(FacultyController());
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, controller),
            _buildSearchBar(context, controller),
            _buildDepartmentFilter(context, controller),
            Expanded(child: _buildFacultyList(context, controller)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, FacultyController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : kDarkTextColor;
    final subTextColor = isDark ? Colors.white70 : Colors.grey[700];

    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<DocumentSnapshot?>(
                future: () async {
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) return null;
                  return FirebaseFirestore.instance.collection('users').doc(uid).get();
                }(),
                builder: (context, snap) {
                  String name = 'Student';
                  if (snap.connectionState == ConnectionState.done && snap.hasData && snap.data?.data() != null) {
                    final data = snap.data!.data() as Map<String, dynamic>;
                    name = data['name'] ?? FirebaseAuth.instance.currentUser?.displayName ?? 'Student';
                  } else if (FirebaseAuth.instance.currentUser?.displayName != null) {
                    name = FirebaseAuth.instance.currentUser!.displayName!;
                  }
                  return Text(
                    'Hi, $name!',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Find a Mentor',
                style: TextStyle(
                  color: subTextColor,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const Spacer(),
          CircleAvatar(
            radius: 24,
            backgroundColor: kPrimaryColor.withOpacity(0.2),
            backgroundImage: FirebaseAuth.instance.currentUser?.photoURL != null
                ? NetworkImage(FirebaseAuth.instance.currentUser!.photoURL!)
                : null,
            child: FirebaseAuth.instance.currentUser?.photoURL == null
                ? const Icon(Icons.person, color: kPrimaryColor)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, FacultyController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Theme.of(context).cardColor : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white54 : Colors.grey[400];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: TextField(
          style: TextStyle(color: textColor),
          onChanged: (value) => controller.searchQuery.value = value,
          decoration: InputDecoration(
            hintText: 'Search Professor, Dept, or Skill...',
            hintStyle: TextStyle(color: hintColor),
            prefixIcon: Icon(Icons.search, color: isDark ? Colors.white54 : Colors.grey),
            suffixIcon: IconButton(
              icon: const Icon(Icons.tune, color: kPrimaryColor),
              onPressed: () {
                // Additional filters
              },
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 15,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDepartmentFilter(BuildContext context, FacultyController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedBg = isDark ? Theme.of(context).cardColor : Colors.white;
    final unselectedText = isDark ? Colors.white70 : Colors.black87;

    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Obx(() {
        final departments = controller.getDepartments();
        return ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: departments.length,
          itemBuilder: (context, index) {
            final dept = departments[index];
            final isSelected = controller.selectedDepartment.value == dept;
            return GestureDetector(
              onTap: () => controller.selectedDepartment.value = dept,
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? kPrimaryColor : unselectedBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(
                    dept,
                    style: TextStyle(
                      color: isSelected ? Colors.white : unselectedText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }

  Widget _buildFacultyList(BuildContext context, FacultyController controller) {
    return Obx(() {
      if (controller.isLoading.value) {
        return const Center(
          child: CircularProgressIndicator(color: kPrimaryColor),
        );
      }

      if (controller.filteredFaculty.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 80,
                color: Colors.grey.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'No faculty found',
                style: TextStyle(
                  color: Colors.grey.withOpacity(0.7),
                  fontSize: 18,
                ),
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: controller.filteredFaculty.length,
        itemBuilder: (context, index) {
          final faculty = controller.filteredFaculty[index];
          return _buildFacultyCard(context, faculty);
        },
      );
    });
  }

  Widget _buildFacultyCard(BuildContext context, FacultyUser faculty) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Theme.of(context).cardColor : Colors.white;
    final textColor = isDark ? Colors.white : kDarkTextColor;
    final subTextColor = isDark ? Colors.white70 : Colors.grey[600];

    return GestureDetector(
      onTap: () => _showBookingBottomSheet(context, faculty),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: faculty.photoUrl.isNotEmpty
                      ? NetworkImage(faculty.photoUrl)
                      : null,
                  child: faculty.photoUrl.isEmpty
                      ? const Icon(Icons.person, size: 30)
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: faculty.isAvailable
                          ? const Color(0xFF00C853)
                          : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: cardColor, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    faculty.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    faculty.department,
                    style: TextStyle(
                      fontSize: 13,
                      color: subTextColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        faculty.isAvailable
                            ? Icons.circle
                            : Icons.circle_outlined,
                        size: 12,
                        color: faculty.isAvailable
                            ? const Color(0xFF00C853)
                            : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        faculty.isAvailable ? 'Online Now' : 'Offline',
                        style: TextStyle(
                          fontSize: 12,
                          color: faculty.isAvailable
                              ? const Color(0xFF00C853)
                              : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                ElevatedButton(
                  onPressed: () => _showBookingBottomSheet(context, faculty),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  child: const Text(
                    'Book Now',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => _showProfileDialog(context, faculty),
                  child: const Text(
                    'View Profile',
                    style: TextStyle(
                      fontSize: 11,
                      color: kPrimaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showProfileDialog(BuildContext context, FacultyUser faculty) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? Theme.of(context).cardColor : Colors.white;
    final textColor = isDark ? Colors.white : kDarkTextColor;
    final containerBg = isDark ? Colors.white10 : Colors.grey[100];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 50,
                backgroundImage: faculty.photoUrl.isNotEmpty
                    ? NetworkImage(faculty.photoUrl)
                    : null,
                child: faculty.photoUrl.isEmpty
                    ? const Icon(Icons.person, size: 50)
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                faculty.name,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                faculty.title,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                faculty.department,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: containerBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Office Hours',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      faculty.officeHours,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey[700]
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showBookingBottomSheet(context, faculty);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Book Appointment',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBookingBottomSheet(BuildContext context, FacultyUser faculty) {
    final BookingController bookingController = Get.put(BookingController());
    bookingController.selectedFaculty.value = faculty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BookingBottomSheet(faculty: faculty),
    );
  }
}

// ============================================================================
// BOOKING BOTTOM SHEET
// ============================================================================
class BookingBottomSheet extends StatelessWidget {
  final FacultyUser faculty;

  const BookingBottomSheet({Key? key, required this.faculty}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final BookingController controller = Get.find<BookingController>();
    
    // Dynamic Theme
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? Theme.of(context).cardColor : Colors.white;
    
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 24),
                    _buildOfficeHours(context),
                    const SizedBox(height: 20),
                    _buildDateSelector(context, controller),
                    const SizedBox(height: 20),
                    _buildTimeSlotSelector(context, controller),
                    const SizedBox(height: 20),
                    _buildReasonInput(context, controller),
                    const SizedBox(height: 24),
                    _buildBookButton(context, controller),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : kDarkTextColor;

    return Row(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundImage: faculty.photoUrl.isNotEmpty
              ? NetworkImage(faculty.photoUrl)
              : null,
          child: faculty.photoUrl.isEmpty
              ? const Icon(Icons.person, size: 30)
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Book with',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white60 : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.share, size: 18, color: isDark ? Colors.white70 : Colors.grey),
                    onPressed: () {},
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              Text(
                faculty.name,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOfficeHours(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final containerBg = isDark ? Colors.white10 : Colors.grey[100];
    final textColor = isDark ? Colors.white : kDarkTextColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Office Hours',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            faculty.officeHours,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector(BuildContext context, BookingController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : kDarkTextColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Date',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(height: 12),
        Obx(() {
          final currentSelected = controller.selectedDate.value;
          DateTime initialDate;
          try {
            initialDate = currentSelected.isNotEmpty
                ? DateTime.parse(currentSelected)
                : DateTime.now().add(const Duration(days: 1));
          } catch (_) {
            initialDate = DateTime.now().add(const Duration(days: 1));
          }

          return SizedBox(
            height: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: ColorScheme.light(
                        primary: kPrimaryColor,
                        onPrimary: Colors.white,
                        surface: isDark ? Colors.grey[800]! : Colors.white,
                        onSurface: isDark ? Colors.white : Colors.black,
                      ),
                      primaryColor: kPrimaryColor,
                    ),
                    child: CalendarDatePicker(
                      initialDate: initialDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      onDateChanged: (selected) {
                        controller.selectedDate.value = DateFormat('yyyy-MM-dd').format(selected);
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    currentSelected.isNotEmpty
                        ? DateFormat('EEE, MMM d, yyyy').format(DateTime.parse(currentSelected))
                        : 'No date selected',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.grey[700]),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTimeSlotSelector(BuildContext context, BookingController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : kDarkTextColor;
    final availableSlotBg = isDark ? Colors.white10 : Colors.white;
    final unavailableSlotBg = isDark ? Colors.white.withOpacity(0.05) : Colors.grey[200];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select a Slot',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(height: 12),
        Obx(() {
          final slots = controller.generateTimeSlots();
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: slots.map((slot) {
              final isSelected = controller.selectedTimeSlot.value == slot;
              final hour = int.parse(slot.split(':')[0]);
              final isAvailable = hour >= 10 && hour <= 16;

              return GestureDetector(
                onTap: isAvailable
                    ? () => controller.selectedTimeSlot.value = slot
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: !isAvailable
                        ? unavailableSlotBg
                        : isSelected
                            ? kPrimaryColor
                            : availableSlotBg,
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: !isAvailable
                          ? (isDark ? Colors.white12 : Colors.grey[300]!)
                          : isSelected
                              ? kPrimaryColor
                              : (isDark ? Colors.white24 : Colors.grey[300]!),
                      width: 2,
                    ),
                  ),
                  child: Text(
                    slot,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: !isAvailable
                          ? (isDark ? Colors.white30 : Colors.grey[400])
                          : isSelected
                              ? Colors.white
                              : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  Widget _buildReasonInput(BuildContext context, BookingController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : kDarkTextColor;
    final hintColor = isDark ? Colors.white38 : Colors.grey[400];
    final borderColor = isDark ? Colors.white24 : Colors.grey[300]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reason for Visit',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller.reasonController,
          maxLines: 3,
          maxLength: 200,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            hintText: 'e.g., Thesis topic discussion',
            hintStyle: TextStyle(color: hintColor),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kPrimaryColor, width: 2),
            ),
            counterText: '',
          ),
        ),
        Text(
          '0/200',
          style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey[500]),
        ),
      ],
    );
  }

  Widget _buildBookButton(BuildContext context, BookingController controller) {
    return Obx(() => SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: controller.isBooking.value
                ? null
                : () => controller.bookAppointment(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C853),
              disabledBackgroundColor: Colors.grey[300],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: controller.isBooking.value
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Request Appointment',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ));
  }
}

// ============================================================================
// SUCCESS DIALOG
// ============================================================================
class SuccessDialog extends StatelessWidget {
  final String facultyName;
  final String date;
  final String time;

  const SuccessDialog({
    Key? key,
    required this.facultyName,
    required this.date,
    required this.time,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? Theme.of(context).cardColor : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final containerBg = isDark ? Colors.white10 : Colors.grey[100];

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                color: Color(0xFF00C853),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check,
                size: 50,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Booking Confirmed!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Your request for 10:15 AM has been sent.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white70 : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: containerBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'Dr. $facultyName',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$date at $time',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Get.back();
                  Get.back();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C853),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
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
// APPOINTMENTS SCREEN
// ============================================================================
class AppointmentsScreen extends StatelessWidget {
  const AppointmentsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final AppointmentController controller = Get.put(AppointmentController());
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final appBarBg = Theme.of(context).appBarTheme.backgroundColor;
    final appBarFg = Theme.of(context).appBarTheme.foregroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarBg,
        elevation: 0,
        title: Text(
          'My Appointments',
          style: TextStyle(
            color: appBarFg,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildSegmentedControl(context, controller),
          Expanded(child: _buildAppointmentsList(context, controller)),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl(BuildContext context, AppointmentController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final containerBg = isDark ? Theme.of(context).cardColor : Colors.white;
    final unselectedText = isDark ? Colors.white60 : Colors.black54;

    return Obx(() => Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          height: 50,
          decoration: BoxDecoration(
            color: containerBg,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => controller.selectedTab.value = 'Upcoming',
                  child: Container(
                    decoration: BoxDecoration(
                      color: controller.selectedTab.value == 'Upcoming'
                          ? kPrimaryColor
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Upcoming',
                      style: TextStyle(
                        color: controller.selectedTab.value == 'Upcoming'
                            ? Colors.white
                            : unselectedText,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => controller.selectedTab.value = 'History',
                  child: Container(
                    decoration: BoxDecoration(
                      color: controller.selectedTab.value == 'History'
                          ? kPrimaryColor
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'History',
                      style: TextStyle(
                        color: controller.selectedTab.value == 'History'
                            ? Colors.white
                            : unselectedText,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ));
  }

  Widget _buildAppointmentsList(BuildContext context, AppointmentController controller) {
    return Obx(() {
      if (controller.isLoading.value) {
        return const Center(
          child: CircularProgressIndicator(color: kPrimaryColor),
        );
      }

      final appointments = controller.selectedTab.value == 'Upcoming'
          ? controller.upcomingAppointments
          : controller.historyAppointments;

      if (appointments.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 80,
                color: Colors.grey.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'No more upcoming appointments.',
                style: TextStyle(
                  color: Colors.grey.withOpacity(0.7),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              const Icon(
                Icons.thumb_up_outlined,
                size: 40,
                color: Colors.grey,
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: appointments.length,
        itemBuilder: (context, index) {
          final appointment = appointments[index];
          return _buildAppointmentCard(context, controller, appointment);
        },
      );
    });
  }

  Widget _buildAppointmentCard(
    BuildContext context,
    AppointmentController controller,
    AppointmentModel appointment,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Theme.of(context).cardColor : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.grey[600];

    Color statusColor;
    String statusText;

    switch (appointment.status) {
      case 'confirmed':
        statusColor = const Color(0xFF00C853);
        statusText = 'Confirmed';
        break;
      case 'pending':
        statusColor = Colors.amber;
        statusText = 'Pending';
        break;
      case 'cancelled':
        statusColor = const Color(0xFFFF3D00);
        statusText = 'Declined';
        break;
      default:
        statusColor = Colors.grey;
        statusText = 'Unknown';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage: appointment.facultyPhoto.isNotEmpty
                    ? NetworkImage(appointment.facultyPhoto)
                    : null,
                child: appointment.facultyPhoto.isEmpty
                    ? const Icon(Icons.person, size: 24)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.facultyName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Text(
                      appointment.facultyDept,
                      style: TextStyle(
                        fontSize: 13,
                        color: subTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: subTextColor),
              const SizedBox(width: 8),
              Text(
                DateFormat('MMM dd, yyyy').format(appointment.requestDate),
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.access_time, size: 16, color: subTextColor),
              const SizedBox(width: 8),
              Text(
                appointment.requestTime,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
            ],
          ),
          if (appointment.reason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Reason: ${appointment.reason}',
              style: TextStyle(
                fontSize: 13,
                color: subTextColor,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (appointment.status == 'pending' ||
              appointment.status == 'confirmed') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        controller.rescheduleAppointment(appointment.id),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: kPrimaryColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Reschedule',
                      style: TextStyle(
                        color: kPrimaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        controller.cancelAppointment(appointment.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3D00),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// PLACEHOLDER SCREEN
// ============================================================================
class PlaceholderScreen extends StatelessWidget {
  final String title;

  const PlaceholderScreen({Key? key, required this.title}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Dynamic Theme
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final appBarBg = Theme.of(context).appBarTheme.backgroundColor;
    final appBarFg = Theme.of(context).appBarTheme.foregroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white70 : Colors.grey;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarBg,
        elevation: 0,
        title: Text(
          title,
          style: TextStyle(
            color: appBarFg,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction,
              size: 80,
              color: textColor.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              '$title coming soon',
              style: TextStyle(
                color: textColor,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}