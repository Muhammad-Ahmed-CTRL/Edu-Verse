// faculty_dashboard.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// ==================== CONTROLLER ====================
class FacultyDashboardController extends GetxController {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Observable state
  final RxBool isAvailable = false.obs;
  final RxString selectedTab = 'Requests'.obs; // Options: 'Requests', 'Schedule'
  final RxInt todayAppointments = 0.obs;
  final RxInt pendingRequests = 0.obs;
  final RxString facultyName = ''.obs;
  final RxString facultyRole = ''.obs;
  final RxString facultyImageUrl = ''.obs;
  final RxInt navIndex = 0.obs; // 0: Dashboard, 1: Schedule, 2: Messages, 3: Alerts
  
  @override
  void onInit() {
    super.onInit();
    loadFacultyProfile();
    fetchDashboardStats();
  }
  
  // Load faculty profile data
  Future<void> loadFacultyProfile() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        facultyName.value = data['name'] ?? 'Faculty Member';
        // Construct a role/title string
        String dept = data['departmentId'] ?? 'Department';
        String title = data['title'] ?? 'Professor';
        facultyRole.value = '$dept • $title';
        
        isAvailable.value = data['isAvailable'] ?? false;
        facultyImageUrl.value = data['imageUrl'] ?? '';
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to load profile: $e',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }
  
  // Fetch dashboard statistics via real-time streams
  void fetchDashboardStats() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    
    // 1. Listen to Today's Confirmed Appointments
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
    
    _firestore
        .collection('appointments')
        .where('profId', isEqualTo: uid) // Ensure your Appointment model uses 'profId'
        .where('scheduledTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('scheduledTime', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .where('status', isEqualTo: 'confirmed')
        .snapshots()
        .listen((snapshot) {
      todayAppointments.value = snapshot.docs.length;
    });
    
    // 2. Listen to Pending Requests (All time)
    _firestore
        .collection('appointments')
        .where('profId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      pendingRequests.value = snapshot.docs.length;
    });
  }
  
  // Toggle availability in Firestore
  Future<void> toggleAvailability(bool value) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      
      await _firestore.collection('users').doc(uid).update({
        'isAvailable': value,
      });
      
      isAvailable.value = value;
      Get.snackbar(
        'Status Updated',
        value ? 'You are now visible as Online' : 'You are now Offline',
        backgroundColor: value ? Colors.green : Colors.grey,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(10),
      );
    } catch (e) {
      Get.snackbar('Error', 'Failed to update availability: $e',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }
  
  // Approve appointment
  Future<void> approveAppointment(String appointmentId) async {
    try {
      final docRef = _firestore.collection('appointments').doc(appointmentId);
      final doc = await docRef.get();
      final data = doc.data();

      // Ensure scheduledTime exists. If missing, try to derive from requestDate + requestTime
      Timestamp? scheduled = data?['scheduledTime'];
      if (scheduled == null) {
        try {
          final Timestamp? reqTs = data?['requestDate'];
          final String? reqTime = data?['requestTime'];
          if (reqTs != null && reqTime != null && reqTime.isNotEmpty) {
            final dt = reqTs.toDate();
            final parts = reqTime.split(':');
            int hour = int.parse(parts[0]);
            int minute = parts.length > 1 ? int.parse(parts[1]) : 0;
            final scheduledDt = DateTime(dt.year, dt.month, dt.day, hour, minute);
            scheduled = Timestamp.fromDate(scheduledDt);
          }
        } catch (_) {
          scheduled = null;
        }
      }

      final updateData = {
        'status': 'confirmed',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (scheduled != null) updateData['scheduledTime'] = scheduled;

      await docRef.update(updateData);
      
      Get.snackbar('Success', 'Student appointment confirmed',
          backgroundColor: Colors.green, colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Error', 'Failed to approve: $e',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }
  
  // Decline appointment
  Future<void> declineAppointment(String appointmentId) async {
    try {
      await _firestore.collection('appointments').doc(appointmentId).update({
        'status': 'declined',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      Get.snackbar('Declined', 'Appointment request declined',
          backgroundColor: Colors.orange, colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Error', 'Failed to decline: $e',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }
  
  // Logout
  Future<void> logout() async {
    try {
      await _auth.signOut();
      Get.offAllNamed('/login');
    } catch (e) {
      Get.snackbar('Error', 'Logout failed: $e',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }
}

// ==================== VIEW ====================
class FacultyDashboardScreen extends GetView<FacultyDashboardController> {
  const FacultyDashboardScreen({Key? key}) : super(key: key);
  
  // Matching the dark theme requested
  static const Color primaryBg = Color(0xFF1A1F38); 
  static const Color cardColor = Colors.white;
  static const Color accentColor = Color(0xFF5E5CE6); // Blurple
  
  @override
  Widget build(BuildContext context) {
    // Inject controller
    Get.put(FacultyDashboardController());
    return Obx(() {
      Widget bodyContent;
      switch (controller.navIndex.value) {
        case 1:
          bodyContent = SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildScheduleList(),
          );
          break;
        case 2:
          bodyContent = SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildMessagesPage(),
          );
          break;
        case 3:
          bodyContent = SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildAlertsPage(),
          );
          break;
        case 0:
        default:
          bodyContent = SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildProfileCard(),
                const SizedBox(height: 20),
                _buildStatsCards(),
                const SizedBox(height: 24),
                _buildTabControl(),
                const SizedBox(height: 20),
                // Dynamic Body Content within Dashboard tab
                Obx(() {
                  if (controller.selectedTab.value == 'Requests') {
                    return _buildRequestsList();
                  } else {
                    return _buildScheduleList();
                  }
                }),
              ],
            ),
          );
      }

      return Scaffold(
        backgroundColor: primaryBg,
        appBar: AppBar(
          backgroundColor: primaryBg,
          elevation: 0,
          title: const Text(
            'Faculty Portal',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white70),
              onPressed: controller.logout,
              tooltip: 'Logout',
            ),
          ],
        ),
        body: bodyContent,
        bottomNavigationBar: _buildBottomNav(),
      );
    });
  }
  
  // 1. Profile & Status Card
  Widget _buildProfileCard() {
    return Obx(() => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 35,
            backgroundColor: accentColor.withOpacity(0.1),
            backgroundImage: controller.facultyImageUrl.value.isNotEmpty
                ? NetworkImage(controller.facultyImageUrl.value)
                : null,
            child: controller.facultyImageUrl.value.isEmpty
                ? const Icon(Icons.person, size: 35, color: accentColor)
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.facultyName.value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  controller.facultyRole.value,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text(
                controller.isAvailable.value ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: controller.isAvailable.value ? Colors.green : Colors.grey,
                ),
              ),
              Switch(
                value: controller.isAvailable.value,
                onChanged: controller.toggleAvailability,
                activeColor: Colors.green,
                inactiveTrackColor: Colors.grey[200],
              ),
            ],
          ),
        ],
      ),
    ));
  }
  
  // 2. Statistics Row
  Widget _buildStatsCards() {
    return Obx(() => Row(
      children: [
        Expanded(
          child: _buildStatCard(
            icon: Icons.calendar_today,
            label: "Today's Appts",
            count: controller.todayAppointments.value.toString(),
            color: accentColor,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            icon: Icons.pending_actions,
            label: 'Pending Requests',
            count: controller.pendingRequests.value.toString(),
            color: Colors.orange,
          ),
        ),
      ],
    ));
  }
  
  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Text(
                count,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  // 3. Tab Control (Segmented)
  Widget _buildTabControl() {
    return Obx(() => Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cardColor.withOpacity(0.1), // Semi-transparent on dark bg
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          _buildTabButton('Requests'),
          _buildTabButton('Schedule'),
        ],
      ),
    ));
  }
  
  Widget _buildTabButton(String text) {
    bool isSelected = controller.selectedTab.value == text;
    return Expanded(
      child: GestureDetector(
        onTap: () => controller.selectedTab.value = text,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? accentColor : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontWeight: FontWeight.w600,
              fontSize: 15
            ),
          ),
        ),
      ),
    );
  }
  
  // 4. Requests List (Real-time)
  Widget _buildRequestsList() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('Login Required'));
    
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('profId', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .orderBy('scheduledTime', descending: false) // Show upcoming first
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }
        
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.inbox, size: 40, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'No pending requests',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }
        
        return Column(
          children: snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return _buildRequestCard(doc.id, data);
          }).toList(),
        );
      },
    );
  }
  
  Widget _buildRequestCard(String id, Map<String, dynamic> data) {
    final Timestamp? ts = data['scheduledTime'];
    final date = ts?.toDate() ?? DateTime.now();
    final dateStr = DateFormat('MMM d, yyyy').format(date);
    final timeStr = DateFormat('h:mm a').format(date);
    final reason = data['reason'] ?? 'Consultation';
    final studentName = data['studentName'] ?? 'Student'; // Ensure your booking logic saves this name
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Appointment Request',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)
                ),
                child: const Text('Pending', style: TextStyle(color: Colors.orange, fontSize: 12)),
              )
            ],
          ),
          const SizedBox(height: 12),
          Text(
            studentName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 4),
          Text('Reason: $reason', style: TextStyle(color: Colors.grey[700])),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Text('$timeStr on $dateStr', style: TextStyle(color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => controller.declineAppointment(id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => controller.approveAppointment(id),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Approve', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildSchedulePlaceholder() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.event_note, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Schedule View',
            style: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Weekly calendar view coming in next update.',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleList() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('Login Required'));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('profId', isEqualTo: uid)
          .where('status', isEqualTo: 'confirmed')
          .orderBy('scheduledTime', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            height: 200,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.event_note, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'No scheduled appointments',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return Column(
          children: snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final Timestamp? ts = data['scheduledTime'];
            final date = ts?.toDate() ?? DateTime.now();
            final dateStr = DateFormat('MMM d, yyyy').format(date);
            final timeStr = DateFormat('h:mm a').format(date);
            final studentName = data['studentName'] ?? 'Student';
            final reason = data['reason'] ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(studentName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text('$timeStr • $dateStr', style: TextStyle(color: Colors.grey[700])),
                        if (reason.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('Reason: $reason', style: TextStyle(color: Colors.grey[700])),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildMessagesPage() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('Login Required'));

    // Simple messages placeholder: reads from `messages` collection where `to`==uid
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('messages')
          .where('to', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.white));
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [Icon(Icons.chat_bubble_outline, size: 40, color: Colors.grey[300]), const SizedBox(height: 16), Text('No messages', style: TextStyle(color: Colors.grey[600]))]),
          );
        }

        return Column(
          children: snap.data!.docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            final from = data['fromName'] ?? data['from'] ?? 'User';
            final text = data['text'] ?? '';
            final created = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
            return ListTile(
              title: Text(from),
              subtitle: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Text(DateFormat('h:mm a').format(created), style: TextStyle(color: Colors.grey[600])),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildAlertsPage() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('Login Required'));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('alerts')
          .where('to', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.white));
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [Icon(Icons.notifications_none, size: 40, color: Colors.grey[300]), const SizedBox(height: 16), Text('No alerts', style: TextStyle(color: Colors.grey[600]))]),
          );
        }

        return Column(
          children: snap.data!.docs.map((d) {
            final data = d.data() as Map<String, dynamic>;
            final title = data['title'] ?? 'Alert';
            final body = data['body'] ?? '';
            final created = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
            return ListTile(
              title: Text(title),
              subtitle: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Text(DateFormat('MMM d').format(created), style: TextStyle(color: Colors.grey[600])),
            );
          }).toList(),
        );
      },
    );
  }
  
  // 5. Bottom Navigation
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: primaryBg, // Match background for seamless look
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -5)
          ),
        ],
      ),
      child: Obx(() => BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: primaryBg,
        selectedItemColor: accentColor,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        currentIndex: controller.navIndex.value,
        onTap: (i) => controller.navIndex.value = i,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Schedule'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'Messages'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_none), label: 'Alerts'),
        ],
      )),
    );
  }
}