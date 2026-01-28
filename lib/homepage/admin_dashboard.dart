import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart'; // Added for Clipboard
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart'; // Added for opening Email App
import '../shared.dart';
import 'package:reclaimify/theme_colors.dart';
import '../timetable/timetable_service.dart';
import '../marketplace_admin_list.dart';
import '../student_marketplace.dart';
import 'recruiter_requests_admin.dart';
import 'admin_notifications.dart';
import '../lost_and_found_admin.dart';
import '../complaints/views/admin_complaint_list.dart';
import '../auth.dart'; // IMPORTED AUTH SERVICE

// --- IMPORT THE NEW ANNOUNCEMENTS MODULE ---
import '../announcements/admin_announcement_view.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _service = TimetableService();
  late TabController _tabController;

  // Admin Capabilities
  bool isSuperAdmin = false;
  bool isUniversityAdmin = false;
  bool isDepartmentAdmin = false;
  Map<String, dynamic>? adminScope;

  // GLOBAL SELECTION STATE
  String? selectedUni;
  String? selectedUniName;
  String? selectedDept;
  String? selectedDeptName;
  String? selectedSection;
  String? selectedSectionName;
  String selectedShift = 'morning';
  String? selectedSemester;
  final List<String> semesters = ['1', '2', '3', '4', '5', '6', '7', '8'];

  // Data Cache
  List<Map<String, dynamic>> universities = [];
  List<Map<String, dynamic>> departments = [];
  List<Map<String, dynamic>> sections = [];
  bool isLoadingProfile = true;
  String userName = '';

  final List<String> days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    // Saturday removed (off)
  ];

  @override
  void initState() {
    super.initState();
    _loadAdminProfile();
  }

  // Wrap Firestore snapshots with error handling to avoid web SDK assertion
  // bubbling up and crashing the app. Errors are logged and swallowed so UI
  // can display a friendly message instead of causing unhandled exceptions.
  Stream<QuerySnapshot> _safeCollectionStream(CollectionReference col) {
    try {
      return col.snapshots().handleError((e, st) {
        // Log for diagnostics; do not rethrow to avoid breaking StreamBuilder
        debugPrint('Firestore stream error: $e');
      }, test: (_) => true);
    } catch (e) {
      debugPrint('Failed to obtain snapshots stream: $e');
      return const Stream.empty();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _db.collection('users').doc(user.uid).get();
    if (!doc.exists) return;

    final data = doc.data() as Map<String, dynamic>;
    setState(() {
      userName = data['name'] ?? 'Admin';
      String role = data['role'] ?? 'student';
      isSuperAdmin = (role == 'super_admin');
      adminScope = data['adminScope'] as Map<String, dynamic>?;

      if (role == 'admin' && adminScope != null) {
        if (adminScope!['deptId'] != null) {
          isDepartmentAdmin = true;
          isUniversityAdmin = false;
        } else {
          isUniversityAdmin = true;
          isDepartmentAdmin = false;
        }
      }

      if (isSuperAdmin) {
        selectedUni = null;
      } else if (adminScope != null) {
        selectedUni = adminScope!['uniId'];
        if (adminScope!['deptId'] != null) {
          selectedDept = adminScope!['deptId'];
        }
      } else {
        selectedUni = data['uniId'];
      }

      isLoadingProfile = false;
    });

    final tabLength = 2 +
        ((isSuperAdmin || isUniversityAdmin || isDepartmentAdmin) ? 1 : 0) +
        ((isSuperAdmin || isUniversityAdmin) ? 2 : 0);
    _tabController = TabController(length: tabLength, vsync: this);
    // Ensure UI updates (FAB visibility) when the selected tab changes
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    if (isSuperAdmin) {
      await _fetchAllUniversities();
    } else if (selectedUni != null) {
      await _fetchDepartments(selectedUni!);
      if (selectedDept != null) {
        await _fetchSections(selectedUni!, selectedDept!);
      }
    }
  }

  Future<void> _fetchAllUniversities() async {
    final list = await _service.getAllUniversities();
    setState(() => universities = list);
  }

  Future<void> _fetchDepartments(String uniId) async {
    final list = await _service.getDepartments(uniId);
    setState(() => departments = list);
  }

  Future<void> _fetchSections(String uniId, String deptId) async {
    final list = await _service.getSections(uniId, deptId);
    setState(() => sections = list);
  }

  String _getContextTitle() {
    List<String> parts = [];
    if (selectedUniName != null) parts.add(selectedUniName!);
    if (selectedDeptName != null) parts.add(selectedDeptName!);
    if (selectedSectionName != null) parts.add(selectedSectionName!);
    if (parts.isEmpty) return "Admin Dashboard";
    return parts.join(" > ");
  }

  // ==========================================
  // FACULTY CONNECT / INVITE DIALOG
  // ==========================================
  void _showGenerateInviteDialog() {
    // 1. Validation: Ensure we know which university this admin belongs to
    if (selectedUni == null) {
      Get.snackbar("Error",
          "University ID not found. Please select a university context.",
          backgroundColor: Colors.red.shade100);
      return;
    }

    final emailCtrl = TextEditingController();

    Get.defaultDialog(
      title: "Generate Faculty Invite",
      content: Column(
        children: [
          const Text("Enter the professor's email to lock this code."),
          const SizedBox(height: 10),
          TextField(
            controller: emailCtrl,
            decoration: const InputDecoration(
              labelText: "Professor Email",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Linking to Uni ID: $selectedUni",
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      textConfirm: "Generate & Email",
      textCancel: "Cancel",
      confirmTextColor: Colors.white,
      onConfirm: () async {
        final email = emailCtrl.text.trim();
        if (email.isEmpty || !email.contains('@')) {
          Get.snackbar("Error", "Invalid Email",
              backgroundColor: Colors.orange.shade100);
          return;
        }

        try {
          // 2. CALL AUTH SERVICE DIRECTLY
          final String code = await AuthService().generateFacultyInvite(
            facultyEmail: email,
            uniId: selectedUni!,
            deptId: selectedDept, // Optional: link to department if known
          );

          Get.back(); // Close input dialog

          // --- 3. IMPLICITLY OPEN EMAIL APP ---
          // Creates a mailto link with subject and body pre-filled
          final String subject = Uri.encodeComponent("Faculty Invitation Code");
          final String body = Uri.encodeComponent(
              "Hello,\n\nYou have been invited to join the faculty.\n\nYour invitation code is:\n$code\n\nPlease use this code to register.\n\nRegards,\nAdmin");

          final Uri mailUri =
              Uri.parse("mailto:$email?subject=$subject&body=$body");

          try {
            await launchUrl(mailUri);
          } catch (e) {
            debugPrint("Could not launch email app: $e");
            Get.snackbar("Info",
                "Could not open email app automatically. Please copy the code.",
                backgroundColor: Colors.orange.shade100);
          }
          // ------------------------------------

          // 4. Show Success Dialog with Copy option
          Get.defaultDialog(
            title: "Invite Created",
            content: Column(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 50),
                const SizedBox(height: 10),
                const Text(
                  "Code generated & Email opened!",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  code,
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                      letterSpacing: 2),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    Get.back();
                    Get.snackbar("Copied", "Code copied to clipboard",
                        backgroundColor: Colors.green.shade100);
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text("Copy Code"),
                )
              ],
            ),
            textCancel: null, // removing default cancel button
          );
        } catch (e) {
          Get.back();
          Get.snackbar('Error', 'Failed to generate invite: $e',
              backgroundColor: Colors.red.shade100,
              duration: const Duration(seconds: 5));
        }
      },
    );
  }

  // ==========================================
  // MAIN BUILD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    if (isLoadingProfile) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        // Theme-aware AppBar: white in light mode, dark background in dark mode
        backgroundColor: isDark ? kDarkBackgroundColor : Colors.white,
        iconTheme: IconThemeData(color: isDark ? kLightTextColor : kPrimaryColor),
        elevation: 1,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  Navigator.pop(context);
                },
              )
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getContextTitle(),
              style: TextStyle(
                fontSize: 16,
                color: isDark ? kLightTextColor : kPrimaryColor,
              ),
            ),
            Text(
              selectedShift == 'morning' ? 'Morning Shift' : 'Evening Shift',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w300,
                  color: isDark ? Colors.white70 : Colors.grey),
            ),
          ],
        ),
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Open Drawer',
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          if (isSuperAdmin)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showWizardMenu,
            ),
          // Invite Button (Preserved from your file)
          if (isSuperAdmin || isUniversityAdmin || isDepartmentAdmin)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1),
              tooltip: 'Generate Faculty Invite',
              onPressed: _showGenerateInviteDialog,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: kPrimaryColor,
          unselectedLabelColor: isDark ? Colors.white70 : Colors.grey,
          indicatorColor: kPrimaryColor,
          tabs: [
            const Tab(icon: Icon(Icons.calendar_month), text: "Timetable"),
            const Tab(icon: Icon(Icons.people), text: "Manage Users"),
            if (isSuperAdmin || isUniversityAdmin || isDepartmentAdmin)
              const Tab(icon: Icon(Icons.report_problem), text: 'Complaints'),
            if (isSuperAdmin || isUniversityAdmin)
              const Tab(
                icon: Icon(Icons.store_mall_directory),
                text: 'Manage Marketplaces',
              ),
            if (isSuperAdmin || isUniversityAdmin)
              const Tab(
                icon: Icon(Icons.find_in_page),
                text: 'Lost & Found',
              ),
          ],
        ),
      ),
      drawer: _buildSidebarDrawer(),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGridTimetable(),
          _buildUserManager(),
          if (isSuperAdmin || isUniversityAdmin || isDepartmentAdmin)
            AdminComplaintList(adminViewUniId: selectedUni),
          if (isSuperAdmin)
            const MarketplaceAdminList()
          else if (isUniversityAdmin)
            // University admin sees only their university marketplace
            StudentMarketplace(adminViewUniId: selectedUni),
          if (isSuperAdmin || isUniversityAdmin)
            LostAndFoundAdminList(adminViewUniId: selectedUni),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _showAddClassDialog,
              label: const Text("Add Class"),
              icon: const Icon(Icons.add),
              backgroundColor: isSuperAdmin
                  ? Colors.purple
                  : (isUniversityAdmin ? Colors.indigo : Colors.teal),
            )
          : null,
    );
  }

  // ==========================================
  // SIDEBAR DRAWER
  // ==========================================
  Widget _buildSidebarDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            padding: EdgeInsets.zero,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isSuperAdmin
                    ? [Colors.purple, Colors.deepPurple]
                    : (isUniversityAdmin
                        ? [Colors.indigo, Colors.blue]
                        : [Colors.teal, Colors.cyan]),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white,
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : 'A',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    isSuperAdmin
                        ? 'Super Admin'
                        : (isUniversityAdmin
                            ? 'University Admin'
                            : 'Department Admin'),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Filter & Context',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
          ),
          // University Selector
          if (isSuperAdmin)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8,
              ),
              child: DropdownButtonFormField<String?>(
                value: selectedUni,
                decoration: const InputDecoration(
                  labelText: "University",
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text("Select University"),
                  ),
                  ...universities.map(
                    (u) => DropdownMenuItem<String?>(
                      value: u['id'] as String,
                      child: Text(u['name']),
                    ),
                  ),
                ],
                onChanged: (val) async {
                  setState(() {
                    selectedUni = val;
                    selectedUniName = val != null
                        ? universities.firstWhere((e) => e['id'] == val)['name']
                        : null;
                    selectedDept = null;
                    selectedDeptName = null;
                    selectedSection = null;
                    selectedSectionName = null;
                    departments = [];
                    sections = [];
                  });
                  if (val != null) await _fetchDepartments(val);
                },
              ),
            ),
          // Semester selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: DropdownButtonFormField<String?>(
              value: selectedSemester,
              decoration: const InputDecoration(
                labelText: "Semester",
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text("All Semesters"),
                ),
                ...semesters.map(
                  (s) => DropdownMenuItem<String?>(value: s, child: Text(s)),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  selectedSemester = val;
                });
              },
            ),
          ),
          if (!isSuperAdmin && selectedUniName != null)
            ListTile(
              leading: const Icon(Icons.school),
              title: Text(selectedUniName!),
              subtitle: const Text('Your University (locked)'),
            ),
          // Department Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: DropdownButtonFormField<String?>(
              value: selectedDept,
              decoration: const InputDecoration(
                labelText: "Department",
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text("All Departments"),
                ),
                ...departments.map(
                  (d) => DropdownMenuItem<String?>(
                    value: d['id'] as String,
                    child: Text(d['name']),
                  ),
                ),
              ],
              onChanged: isDepartmentAdmin
                  ? null
                  : (val) async {
                      setState(() {
                        selectedDept = val;
                        selectedDeptName = val != null
                            ? departments.firstWhere(
                                (e) => e['id'] == val,
                              )['name']
                            : null;
                        selectedSection = null;
                        selectedSectionName = null;
                        sections = [];
                      });
                      if (val != null && selectedUni != null) {
                        await _fetchSections(selectedUni!, val);
                      }
                    },
            ),
          ),
          // Section Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: DropdownButtonFormField<String?>(
              value: selectedSection,
              decoration: const InputDecoration(
                labelText: "Section",
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text("All Sections"),
                ),
                ...sections.map(
                  (s) => DropdownMenuItem<String?>(
                    value: s['id'] as String,
                    child: Text(s['name']),
                  ),
                ),
              ],
              onChanged: (val) {
                setState(() {
                  selectedSection = val;
                  selectedSectionName = val != null
                      ? sections.firstWhere((e) => e['id'] == val)['name']
                      : null;
                });
              },
            ),
          ),
          // Shift Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
            child: DropdownButtonFormField<String?>(
              value: selectedShift,
              decoration: const InputDecoration(
                labelText: "Shift",
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: const [
                DropdownMenuItem<String?>(
                  value: 'morning',
                  child: Text("Morning"),
                ),
                DropdownMenuItem<String?>(
                  value: 'evening',
                  child: Text("Evening"),
                ),
              ],
              onChanged: (val) =>
                  setState(() => selectedShift = val ?? 'morning'),
            ),
          ),
          // Manage Marketplaces - removed from drawer; accessible via Dashboard tab
          // Recruiter Requests (visible to admins)
          if (isSuperAdmin || isUniversityAdmin) ...[
            ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text('Notifications'),
              subtitle: const Text('View admin notifications'),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AdminNotifications(
                        adminUniId: isUniversityAdmin ? selectedUni : null)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.work_outline),
              title: const Text('Recruiter Requests'),
              subtitle: const Text('Approve or review recruiter job requests'),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RecruiterRequestsAdmin(
                        adminUniId: isUniversityAdmin ? selectedUni : null)));
              },
            ),
            // --- ADDED ANNOUNCEMENT MANAGER ---
            ListTile(
              leading: const Icon(Icons.campaign, color: Colors.orange),
              title: const Text('Manage Announcements'),
              subtitle: const Text('Post & edit university announcements'),
              onTap: () {
                if (selectedUni == null) {
                  Get.back(); // close drawer
                  Get.snackbar("Context Required",
                      "Please select a University from the dropdown above to manage its announcements.",
                      backgroundColor: Colors.orange.shade100,
                      duration: const Duration(seconds: 4));
                  return;
                }
                Navigator.pop(context); // Close drawer
                Get.to(() => AdminAnnouncementView(
                      uniId: selectedUni!,
                      adminName: userName,
                    ));
              },
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================
  // GRID TIMETABLE (ORIGINAL - KEEPING THE GOOD STUFF!)
  // ==========================================
  Widget _buildGridTimetable() {
    if (selectedUni == null) {
      return const Center(
        child: Text("Please select a University from the sidebar"),
      );
    }

    if (selectedDept == null) {
      return const Center(
        child: Text("Please select a Department from the sidebar"),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _service.getAdminTimetableStream(
        uniId: selectedUni!,
        deptId: selectedDept,
        sectionId: selectedSection,
        shift: selectedShift,
        semester: selectedSemester,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = snapshot.data!.docs;
        final conflicts = _detectConflicts(allDocs);

        return Column(
          children: [
            _buildLegend(conflicts.length),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: _buildTimetableGrid(allDocs, conflicts),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLegend(int conflictCount) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildLegendItem(
            Colors.green.shade100,
            'Empty Slot',
            Icons.add_circle,
          ),
          _buildLegendItem(Colors.orange.shade100, 'Lab', Icons.science),
          if (conflictCount > 0)
            _buildLegendItem(
              Colors.red.shade100,
              'Conflict ($conflictCount)',
              Icons.warning,
            ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, IconData icon) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 12),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildTimetableGrid(
    List<QueryDocumentSnapshot> docs,
    List<String> conflicts,
  ) {
    final timeSlots = _getTimeSlots(selectedShift);
    const cellWidth = 180.0;
    const cellHeight = 100.0;
    const headerHeight = 60.0;
    const timeColumnWidth = 80.0;

    final Map<String, List<QueryDocumentSnapshot>> classesByCell = {};

    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final day = data['day'] as String;
      final startTime = data['start'] as String;
      final startMin = _timeToMinutes(startTime);

      String? matchedSlotStart;
      for (var slot in timeSlots) {
        final s = slot['start']!;
        final e = slot['end']!;
        final sMin = _timeToMinutes(s);
        final eMin = _timeToMinutes(e);
        if (startMin >= sMin && startMin < eMin) {
          matchedSlotStart = s;
          break;
        }
      }

      final normalizedKey =
          '$day-${_normalizeToHHMM(matchedSlotStart ?? startTime)}';
      classesByCell.putIfAbsent(normalizedKey, () => []).add(doc);
    }

    return SizedBox(
      width: timeColumnWidth + (days.length * cellWidth),
      height: headerHeight + (timeSlots.length * cellHeight),
      child: Stack(
        children: [
          _buildGridSkeleton(
            timeSlots,
            cellWidth,
            cellHeight,
            headerHeight,
            timeColumnWidth,
          ),
          ..._buildClassOverlaysGrouped(
            classesByCell,
            conflicts,
            timeSlots,
            cellWidth,
            cellHeight,
            headerHeight,
            timeColumnWidth,
          ),
        ],
      ),
    );
  }

  Widget _buildGridSkeleton(
    List<Map<String, String>> timeSlots,
    double cellWidth,
    double cellHeight,
    double headerHeight,
    double timeColumnWidth,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: timeColumnWidth,
              height: headerHeight,
              decoration: BoxDecoration(
                color: Colors.indigo.shade700,
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: const Center(
                child: Text(
                  'Time',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            ...days.map(
              (day) => Container(
                width: cellWidth,
                height: headerHeight,
                decoration: BoxDecoration(
                  color: Colors.indigo,
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Center(
                  child: Text(
                    day,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        ...timeSlots.map((slot) {
          return Row(
            children: [
              Container(
                width: timeColumnWidth,
                height: cellHeight,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  border: Border.all(color: Colors.grey.shade300, width: 1),
                ),
                child: Center(
                  child: Text(
                    '${_formatTime12(slot['start'] ?? '')}\n${_formatTime12(slot['end'] ?? '')}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              ...days.map((day) {
                return _buildEmptyCell(
                  day: day,
                  slot: slot,
                  width: cellWidth,
                  height: cellHeight,
                );
              }),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildEmptyCell({
    required String day,
    required Map<String, String> slot,
    required double width,
    required double height,
  }) {
    return DragTarget<Map<String, dynamic>>(
      onWillAccept: (data) => true,
      onAccept: (data) => _handleDrop(data, day, slot['start']!),
      builder: (context, candidateData, rejectedData) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: candidateData.isNotEmpty
                ? Colors.blue.shade100
                : Colors.green.shade50,
            border: Border.all(color: Colors.grey.shade300, width: 1),
          ),
          child: Center(
            child: IconButton(
              icon: Icon(
                Icons.add_circle,
                color: Colors.green.shade300,
                size: 32,
              ),
              onPressed: () => _showQuickAddDialog(day, slot['start']!),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildClassOverlaysGrouped(
    Map<String, List<QueryDocumentSnapshot>> classesByCell,
    List<String> conflicts,
    List<Map<String, String>> timeSlots,
    double cellWidth,
    double cellHeight,
    double headerHeight,
    double timeColumnWidth,
  ) {
    const slotDuration = 80;
    final overlays = <Widget>[];

    classesByCell.forEach((cellKey, cellDocs) {
      if (cellDocs.isEmpty) return;

      final firstData = cellDocs.first.data() as Map<String, dynamic>;
      final day = firstData['day'] as String;
      final dayIndex = days.indexOf(day);
      if (dayIndex == -1) return;

      final startTime = firstData['start'] as String;
      final startMin = _timeToMinutes(startTime);
      final firstSlotStart = _timeToMinutes(timeSlots.first['start']!);
      final minutesFromFirstSlot = startMin - firstSlotStart;

      final cellTop =
          headerHeight + (minutesFromFirstSlot / slotDuration) * cellHeight;
      final cellLeft = timeColumnWidth + (dayIndex * cellWidth);

      final classCount = cellDocs.length;
      final classWidth = (cellWidth - 8) / classCount;

      for (var i = 0; i < cellDocs.length; i++) {
        final doc = cellDocs[i];
        final data = doc.data() as Map<String, dynamic>;
        final endTime = data['end'] as String;
        final endMin = _timeToMinutes(endTime);
        final duration = endMin - startMin;
        final classHeight = (duration / slotDuration) * cellHeight;
        final hasConflict = conflicts.contains(doc.id);

        overlays.add(
          Positioned(
            top: cellTop,
            left: cellLeft + 4 + (i * classWidth),
            width: classWidth - 4,
            height: classHeight - 8,
            child: _buildDraggableClass(doc, data, hasConflict),
          ),
        );
      }
    });

    return overlays;
  }

  Widget _buildDraggableClass(
    DocumentSnapshot doc,
    Map<String, dynamic> data,
    bool hasConflict,
  ) {
    final dataWithId = Map<String, dynamic>.from(data);
    dataWithId['_docId'] = doc.id;
    final isLab = data['isLab'] ?? false;
    final colorValue = data['colorValue'] ?? 0xFF2196F3;

    Color bgColor;
    Color textColor;

    if (hasConflict) {
      bgColor = Colors.red.shade100;
      textColor = Colors.black;
    } else if (isLab) {
      bgColor = Colors.orange.shade100;
      textColor = Colors.black;
    } else {
      bgColor = Color(colorValue);
      textColor = Colors.white;
    }

    return Draggable<Map<String, dynamic>>(
      data: {
        'docId': doc.id,
        'start': data['start'],
        'end': data['end'],
        'subject': data['subject'],
        'location': data['location'],
        'teacher': data['teacher'],
        'day': data['day'],
        'colorValue': colorValue,
        'isLab': isLab,
      },
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            data['subject'],
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildClassContent(dataWithId, bgColor, textColor, hasConflict),
      ),
      child: _buildClassContent(dataWithId, bgColor, textColor, hasConflict),
    );
  }

  Widget _buildClassContent(
    Map<String, dynamic> data,
    Color bgColor,
    Color textColor,
    bool hasConflict,
  ) {
    final isLab = data['isLab'] ?? false;
    final sectionName = data['sectionId'] ?? '';

    return GestureDetector(
      onTap: () => _showClassDetails(data),
      onLongPress: () => _showEditClassDialog(data),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: hasConflict ? Border.all(color: Colors.red, width: 2) : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    data['subject'],
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isLab)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      'LAB',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            if (selectedSection == null && sectionName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Sec: $sectionName',
                style: TextStyle(
                  color: textColor.withOpacity(0.9),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              '${data['start']} - ${data['end']}',
              style: TextStyle(color: textColor.withOpacity(0.85), fontSize: 8),
            ),
            Text(
              '📍 ${data['location']}',
              style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 8),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '👤 ${data['teacher']}',
              style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 8),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (hasConflict)
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                  '⚠️ CONFLICT',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<String> _detectConflicts(List<QueryDocumentSnapshot> docs) {
    final conflictIds = <String>[];

    for (var i = 0; i < docs.length; i++) {
      final data1 = docs[i].data() as Map<String, dynamic>;

      for (var j = i + 1; j < docs.length; j++) {
        final data2 = docs[j].data() as Map<String, dynamic>;

        if (data1['day'] != data2['day']) continue;

        final start1 = _timeToMinutes(data1['start']);
        final end1 = _timeToMinutes(data1['end']);
        final start2 = _timeToMinutes(data2['start']);
        final end2 = _timeToMinutes(data2['end']);

        final overlap = (start1 < end2 && end1 > start2);

        if (overlap) {
          if (data1['location'].toString().toLowerCase() ==
              data2['location'].toString().toLowerCase()) {
            conflictIds.add(docs[i].id);
            conflictIds.add(docs[j].id);
          }

          if (data1['teacher'].toString().toLowerCase() ==
              data2['teacher'].toString().toLowerCase()) {
            conflictIds.add(docs[i].id);
            conflictIds.add(docs[j].id);
          }
        }
      }
    }

    return conflictIds.toSet().toList();
  }

  Future<void> _handleDrop(
    Map<String, dynamic> classData,
    String newDay,
    String newStart,
  ) async {
    final docId = classData['docId'] as String;
    final oldDay = classData['day'] as String;
    final oldStart = classData['start'] as String;

    if (oldDay == newDay && oldStart == newStart) return;

    final isLab = classData['isLab'] ?? false;
    final endTime = _calculateEndTime(newStart, isLab);

    final conflict = await _service.checkConflict(
      uniId: selectedUni!,
      day: newDay,
      startTime: newStart,
      endTime: endTime,
      room: classData['location'],
      teacher: classData['teacher'],
      excludeDocId: docId,
    );

    if (conflict != null) {
      Get.snackbar(
        "Cannot Move",
        conflict,
        backgroundColor: Colors.red.shade100,
        duration: const Duration(seconds: 4),
      );
      return;
    }

    await _db
        .collection('universities')
        .doc(selectedUni!)
        .collection('timetables')
        .doc(docId)
        .update({'day': newDay, 'start': newStart, 'end': endTime});

    Get.snackbar(
      "Moved",
      "Class moved successfully",
      backgroundColor: Colors.green.shade100,
    );
  }

  void _showQuickAddDialog(String day, String startTime) {
    if (selectedSection == null) {
      Get.snackbar("Info", "Please select a specific section to add a class");
      return;
    }

    final subjectCtrl = TextEditingController();
    final teacherCtrl = TextEditingController();
    final roomCtrl = TextEditingController();
    bool isLab = false;

    Get.defaultDialog(
      title: "Quick Add Class",
      content: StatefulBuilder(
        builder: (context, setState) {
          final endTime = _calculateEndTime(startTime, isLab);

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "$day - $startTime to $endTime",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  title: const Text("Lab Session?"),
                  value: isLab,
                  onChanged: (val) => setState(() => isLab = val),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: subjectCtrl,
                  decoration: const InputDecoration(
                    labelText: "Subject",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: roomCtrl,
                  decoration: const InputDecoration(
                    labelText: "Room",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: teacherCtrl,
                  decoration: const InputDecoration(
                    labelText: "Teacher",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      confirm: ElevatedButton(
        child: const Text("Add"),
        onPressed: () async {
          final endTime = _calculateEndTime(startTime, isLab);

          final conflict = await _service.checkConflict(
            uniId: selectedUni!,
            day: day,
            startTime: startTime,
            endTime: endTime,
            room: roomCtrl.text.trim(),
            teacher: teacherCtrl.text.trim(),
          );

          if (conflict != null) {
            Get.snackbar(
              "Conflict!",
              conflict,
              backgroundColor: Colors.red.shade100,
            );
            return;
          }

          await _service.addClass(
            uniId: selectedUni!,
            data: {
              'departmentId': selectedDept,
              'sectionId': selectedSection,
              'shift': selectedShift,
              'semester': selectedSemester,
              'day': day,
              'start': startTime,
              'end': endTime,
              'subject': subjectCtrl.text.trim(),
              'location': roomCtrl.text.trim(),
              'teacher': teacherCtrl.text.trim(),
              'isLab': isLab,
              'colorValue': Colors
                  .primaries[
                      (subjectCtrl.text.length) % Colors.primaries.length]
                  .value,
              'createdAt': FieldValue.serverTimestamp(),
            },
          );

          Get.back();
          Get.snackbar(
            "Success",
            "Class added",
            backgroundColor: Colors.green.shade100,
          );
        },
      ),
      cancel: TextButton(
        onPressed: () => Get.back(),
        child: const Text("Cancel"),
      ),
    );
  }

  void _showClassDetails(Map<String, dynamic> data) {
    final docId = data['_docId'] ?? data['docId'];
    Get.dialog(
      AlertDialog(
        title: Text(data['subject'] ?? ''),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Day', data['day'] ?? ''),
            _buildDetailRow(
              'Time',
              '${data['start'] ?? ''} - ${data['end'] ?? ''}',
            ),
            _buildDetailRow('Room', data['location'] ?? ''),
            _buildDetailRow('Teacher', data['teacher'] ?? ''),
            _buildDetailRow('Section', data['sectionId'] ?? 'N/A'),
            _buildDetailRow(
              'Type',
              (data['isLab'] ?? false) ? 'Lab (180 min)' : 'Lecture (80 min)',
            ),
            _buildDetailRow('Shift', data['shift'] ?? 'N/A'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Close')),
          if (isSuperAdmin)
            TextButton(
              onPressed: () {
                Get.back();
                Get.defaultDialog(
                  title: 'Delete Class',
                  middleText: 'Are you sure you want to delete this class?',
                  textConfirm: 'Delete',
                  textCancel: 'Cancel',
                  confirmTextColor: Colors.white,
                  onConfirm: () async {
                    if (docId == null || selectedUni == null) {
                      Get.back();
                      Get.snackbar(
                        'Error',
                        'Unable to delete: missing identifiers',
                      );
                      return;
                    }
                    await _service.deleteClass(selectedUni!, docId.toString());
                    Get.back();
                    Get.snackbar(
                      'Deleted',
                      'Class removed',
                      backgroundColor: Colors.green.shade100,
                    );
                  },
                );
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ElevatedButton(
            onPressed: () {
              Get.back();
              _showEditClassDialog(data);
            },
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _showEditClassDialog(Map<String, dynamic> data) {
    final subjectCtrl = TextEditingController(text: data['subject']);
    final teacherCtrl = TextEditingController(text: data['teacher']);
    final roomCtrl = TextEditingController(text: data['location']);
    String day = data['day'];
    String startTime = data['start'];
    bool isLab = data['isLab'] ?? false;

    Get.defaultDialog(
      title: "Edit Class",
      content: StatefulBuilder(
        builder: (context, setState) {
          final availableSlots = _getAvailableSlots(selectedShift, isLab);
          if (!availableSlots.contains(startTime)) {
            startTime = availableSlots.first;
          }
          final endTime = _calculateEndTime(startTime, isLab);

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text("Is this a Lab?"),
                  subtitle: Text(
                    isLab ? "Duration: 180 minutes" : "Duration: 80 minutes",
                  ),
                  value: isLab,
                  onChanged: (val) => setState(() => isLab = val),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField(
                  value: day,
                  items: days
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => day = v!),
                  decoration: const InputDecoration(
                    labelText: "Day",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: startTime,
                  items: availableSlots
                      .map(
                        (slot) => DropdownMenuItem(
                          value: slot,
                          child: Text(
                            '$slot - ${_calculateEndTime(slot, isLab)}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => startTime = v!),
                  decoration: const InputDecoration(
                    labelText: "Time Slot",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: subjectCtrl,
                  decoration: const InputDecoration(
                    labelText: "Subject",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: roomCtrl,
                  decoration: const InputDecoration(
                    labelText: "Room No",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: teacherCtrl,
                  decoration: const InputDecoration(
                    labelText: "Teacher Name",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      confirm: ElevatedButton(
        child: const Text("Update"),
        onPressed: () async {
          final endTime = _calculateEndTime(startTime, isLab);

          final conflict = await _service.checkConflict(
            uniId: selectedUni!,
            day: day,
            startTime: startTime,
            endTime: endTime,
            room: roomCtrl.text.trim(),
            teacher: teacherCtrl.text.trim(),
            excludeDocId: data['docId'],
          );

          if (conflict != null) {
            Get.snackbar(
              "Conflict Detected!",
              conflict,
              backgroundColor: Colors.red.shade100,
              duration: const Duration(seconds: 5),
            );
            return;
          }

          await _db
              .collection('universities')
              .doc(selectedUni!)
              .collection('timetables')
              .doc(data['docId'])
              .update({
            'day': day,
            'start': startTime,
            'end': endTime,
            'subject': subjectCtrl.text.trim(),
            'location': roomCtrl.text.trim(),
            'teacher': teacherCtrl.text.trim(),
            'isLab': isLab,
          });

          Get.back();
          Get.snackbar(
            "Success",
            "Class updated successfully",
            backgroundColor: Colors.green.shade100,
          );
        },
      ),
      cancel: TextButton(
        onPressed: () => Get.back(),
        child: const Text("Cancel"),
      ),
    );
  }

  void _showAddClassDialog() {
    if (selectedUni == null ||
        selectedDept == null ||
        selectedSection == null) {
      Get.snackbar(
        'Missing Info',
        'Please select University, Department and Section from the sidebar.',
      );
      return;
    }

    final subjectCtrl = TextEditingController();
    final teacherCtrl = TextEditingController();
    final roomCtrl = TextEditingController();
    String day = 'Monday';
    String startTime = selectedShift == 'morning' ? '08:00' : '14:40';
    bool isLab = false;

    Get.defaultDialog(
      title: "Add Class",
      content: StatefulBuilder(
        builder: (context, setState) {
          final availableSlots = _getAvailableSlots(selectedShift, isLab);
          if (!availableSlots.contains(startTime)) {
            startTime = availableSlots.first;
          }
          final endTime = _calculateEndTime(startTime, isLab);

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "$selectedDeptName - $selectedSectionName ($selectedShift)",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  title: const Text("Is this a Lab?"),
                  subtitle: Text(isLab ? "180 minutes" : "80 minutes"),
                  value: isLab,
                  onChanged: (val) => setState(() => isLab = val),
                ),
                DropdownButtonFormField(
                  value: day,
                  items: days
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setState(() => day = v!),
                  decoration: const InputDecoration(
                    labelText: "Day",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: startTime,
                  items: availableSlots
                      .map(
                        (slot) => DropdownMenuItem(
                          value: slot,
                          child: Text(
                            '$slot - ${_calculateEndTime(slot, isLab)}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => startTime = v!),
                  decoration: const InputDecoration(
                    labelText: "Time",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: subjectCtrl,
                  decoration: const InputDecoration(
                    labelText: "Subject",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: roomCtrl,
                  decoration: const InputDecoration(
                    labelText: "Room",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: teacherCtrl,
                  decoration: const InputDecoration(
                    labelText: "Teacher",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      confirm: ElevatedButton(
        child: const Text("Add"),
        onPressed: () async {
          final endTime = _calculateEndTime(startTime, isLab);

          final conflict = await _service.checkConflict(
            uniId: selectedUni!,
            day: day,
            startTime: startTime,
            endTime: endTime,
            room: roomCtrl.text.trim(),
            teacher: teacherCtrl.text.trim(),
          );

          if (conflict != null) {
            Get.snackbar(
              "Conflict!",
              conflict,
              backgroundColor: Colors.red.shade100,
            );
            return;
          }

          await _service.addClass(
            uniId: selectedUni!,
            data: {
              'departmentId': selectedDept,
              'sectionId': selectedSection,
              'shift': selectedShift,
              'semester': selectedSemester,
              'day': day,
              'start': startTime,
              'end': endTime,
              'subject': subjectCtrl.text.trim(),
              'location': roomCtrl.text.trim(),
              'teacher': teacherCtrl.text.trim(),
              'isLab': isLab,
              'colorValue': Colors
                  .primaries[
                      (subjectCtrl.text.length) % Colors.primaries.length]
                  .value,
              'createdAt': FieldValue.serverTimestamp(),
            },
          );

          Get.back();
          Get.snackbar(
            "Success",
            "Class added",
            backgroundColor: Colors.green.shade100,
          );
        },
      ),
      cancel: TextButton(
        onPressed: () => Get.back(),
        child: const Text("Cancel"),
      ),
    );
  }

  // ==========================================
  // USER MANAGER WITH CONTEXT FILTERING
  // ==========================================
  Widget _buildUserManager() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            "Manage Users - ${_getContextTitle()}",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _safeCollectionStream(_db.collection('users')),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'Failed to load users: ${snapshot.error}',
                          textAlign: TextAlign.center,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.red[700]),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () async {
                          setState(() {});
                        },
                        child: const Text('Retry'),
                      )
                    ],
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final allUsers = snapshot.data!.docs;

              final filteredUsers = allUsers.where((doc) {
                final data = doc.data() as Map<String, dynamic>;

                // Semester filter (applies to all roles if selected)
                if (selectedSemester != null && selectedSemester!.isNotEmpty) {
                  if ((data['semester'] ?? '') != selectedSemester)
                    return false;
                }

                if (isSuperAdmin) {
                  if (selectedUni != null && data['uniId'] != selectedUni) {
                    return false;
                  }
                  return true;
                }

                if (isUniversityAdmin) {
                  if (data['uniId'] != selectedUni) return false;

                  if (selectedDept != null &&
                      data['departmentId'] != selectedDept) {
                    return false;
                  }

                  if (selectedSection != null &&
                      data['sectionId'] != selectedSection) {
                    return false;
                  }

                  return true;
                }

                if (isDepartmentAdmin) {
                  if (data['uniId'] != selectedUni) return false;
                  if (data['departmentId'] != selectedDept) return false;

                  if (selectedSection != null &&
                      data['sectionId'] != selectedSection) {
                    return false;
                  }

                  return true;
                }

                return false;
              }).toList();

              if (filteredUsers.isEmpty) {
                return const Center(
                  child: Text('No users found in this context'),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filteredUsers.length,
                itemBuilder: (context, index) {
                  final userDoc = filteredUsers[index];
                  final userData = userDoc.data() as Map<String, dynamic>;
                  return _buildUserCard(userDoc.id, userData);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUserCard(String uid, Map<String, dynamic> userData) {
    final role = userData['role'] ?? 'student';
    final name = userData['name'] ?? 'No Name';
    final email = userData['email'] ?? '';

    IconData roleIcon;
    Color roleColor;

    switch (role) {
      case 'super_admin':
        roleIcon = Icons.admin_panel_settings;
        roleColor = Colors.purple;
        break;
      case 'admin':
        roleIcon = Icons.shield;
        roleColor = Colors.indigo;
        break;
      default:
        roleIcon = Icons.person;
        roleColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: roleColor.withOpacity(0.2),
          child: Icon(roleIcon, color: roleColor),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('$email\nRole: $role'),
        isThreeLine: true,
        trailing: ElevatedButton(
          onPressed: () => _showRoleChangeDialog(uid, userData),
          child: const Text('Edit Role'),
        ),
      ),
    );
  }

  void _showRoleChangeDialog(String uid, Map<String, dynamic> userData) {
    String newRole = userData['role'] ?? 'student';

    Get.defaultDialog(
      title: "Change Role: ${userData['name']}",
      content: StatefulBuilder(
        builder: (context, setState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: newRole,
                isExpanded: true,
                items: (isSuperAdmin
                        ? ['student', 'admin', 'super_admin']
                        : ['student', 'admin'])
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setState(() => newRole = v!),
              ),
              if (newRole == 'admin') ...[
                const SizedBox(height: 16),
                const Text(
                  'Admin Scope:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text('University: ${selectedUniName ?? "None"}'),
                Text('Department: ${selectedDeptName ?? "University-wide"}'),
              ],
            ],
          );
        },
      ),
      textConfirm: "Save",
      onConfirm: () async {
        try {
          Map<String, dynamic>? scope;
          if (newRole == 'admin') {
            scope = {};
            if (selectedUni != null) scope['uniId'] = selectedUni;
            if (selectedDept != null) scope['deptId'] = selectedDept;
          }

          await _service.updateUserRole(uid, newRole, scope);
          Get.back();
          Get.snackbar(
            'Success',
            'Role updated',
            backgroundColor: Colors.green.shade100,
          );
        } catch (e) {
          Get.back();
          Get.snackbar(
            'Error',
            e.toString(),
            backgroundColor: Colors.red.shade100,
          );
        }
      },
    );
  }

  // ==========================================
  // WIZARD MENU FOR DATA ENTRY
  // ==========================================
  void _showWizardMenu() {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Setup Wizard',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.school, color: Colors.purple),
              title: const Text('Add University'),
              subtitle: const Text('Start a new university setup'),
              onTap: () {
                Get.back();
                _startUniversityWizard();
              },
            ),
            if (selectedUni != null)
              ListTile(
                leading: const Icon(Icons.business, color: Colors.indigo),
                title: const Text('Add Department'),
                subtitle: Text(
                  'To ${selectedUniName ?? "selected university"}',
                ),
                onTap: () {
                  Get.back();
                  _startDepartmentWizard();
                },
              ),
            if (selectedDept != null)
              ListTile(
                leading: const Icon(Icons.group, color: Colors.teal),
                title: const Text('Add Section'),
                subtitle: Text(
                  'To ${selectedDeptName ?? "selected department"}',
                ),
                onTap: () {
                  Get.back();
                  _startSectionWizard();
                },
              ),
            ListTile(
              leading: const Icon(Icons.vpn_key, color: Colors.orange),
              title: const Text('Generate Faculty Invite'),
              subtitle: const Text('Create invite code for professors'),
              onTap: () {
                Get.back();
                _showGenerateInviteDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _startUniversityWizard() async {
    final ctrl = TextEditingController();
    final result = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Add University'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'University Name',
            hintText: 'e.g., Air University',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) {
                Get.snackbar('Error', 'Please enter a name');
                return;
              }
              await _service.addUniversity(ctrl.text.trim());
              await _fetchAllUniversities();
              Get.back(result: true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true) {
      final continueSetup = await Get.defaultDialog<bool>(
        title: 'Success!',
        middleText: 'University added. Would you like to add departments now?',
        textConfirm: 'Yes, Add Departments',
        textCancel: 'Done',
        onConfirm: () => Get.back(result: true),
        onCancel: () => Get.back(result: false),
      );

      if (continueSetup == true) {
        if (universities.isNotEmpty) {
          selectedUni = universities.last['id'] as String;
          selectedUniName = universities.last['name'] as String;
          await _fetchDepartments(selectedUni!);
          setState(() {});
          _startDepartmentWizard();
        }
      }
    }
  }

  void _startDepartmentWizard() async {
    if (selectedUni == null) {
      Get.snackbar('Error', 'Please select a university first');
      return;
    }

    final ctrl = TextEditingController();
    final result = await Get.dialog<bool>(
      AlertDialog(
        title: Text('Add Department to ${selectedUniName ?? "University"}'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Department Name',
            hintText: 'e.g., Computer Science',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) {
                Get.snackbar('Error', 'Please enter a name');
                return;
              }
              await _service.addDepartment(selectedUni!, ctrl.text.trim());
              await _fetchDepartments(selectedUni!);
              Get.back(result: true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true) {
      final continueSetup = await Get.defaultDialog<bool>(
        title: 'Success!',
        middleText: 'Department added. Would you like to add sections now?',
        textConfirm: 'Yes, Add Sections',
        textCancel: 'Done',
        onConfirm: () => Get.back(result: true),
        onCancel: () => Get.back(result: false),
      );

      if (continueSetup == true) {
        if (departments.isNotEmpty) {
          selectedDept = departments.last['id'] as String;
          selectedDeptName = departments.last['name'] as String;
          await _fetchSections(selectedUni!, selectedDept!);
          setState(() {});
          _startSectionWizard();
        }
      }
    }
  }

  void _startSectionWizard() async {
    if (selectedUni == null || selectedDept == null) {
      Get.snackbar('Error', 'Please select university and department first');
      return;
    }

    final ctrl = TextEditingController();
    await Get.dialog(
      AlertDialog(
        title: Text('Add Section to ${selectedDeptName ?? "Department"}'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Section Name',
            hintText: 'e.g., Section A',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) {
                Get.snackbar('Error', 'Please enter a name');
                return;
              }
              await _service.addSection(
                selectedUni!,
                selectedDept!,
                ctrl.text.trim(),
              );
              await _fetchSections(selectedUni!, selectedDept!);
              Get.back();
              Get.snackbar(
                'Success',
                'Section added',
                backgroundColor: Colors.green.shade100,
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // -----------------------
  // DELETE ACTIONS (Super Admin)
  // -----------------------
  void _showDeleteUniversityDialog() {
    if (!isSuperAdmin) return;
    if (universities.isEmpty) {
      Get.snackbar('None', 'No universities available to delete');
      return;
    }

    String? toDelete;
    Get.dialog(
      AlertDialog(
        title: const Text('Delete University'),
        content: StatefulBuilder(
          builder: (c, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: toDelete,
                  items: universities
                      .map(
                        (u) => DropdownMenuItem(
                          value: u['id'] as String,
                          child: Text(u['name']),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => toDelete = v),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Warning: This will delete the entire university and all related data.',
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (toDelete == null) return;
              try {
                await _service.deleteUniversity(toDelete!);
                await _fetchAllUniversities();
                if (selectedUni == toDelete) {
                  selectedUni = null;
                  selectedUniName = null;
                }
                setState(() {});
                Get.back();
                Get.snackbar(
                  'Deleted',
                  'University removed',
                  backgroundColor: Colors.green.shade100,
                );
              } catch (e) {
                Get.snackbar(
                  'Error',
                  e.toString(),
                  backgroundColor: Colors.red.shade100,
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDepartmentDialog() {
    if (!isSuperAdmin || selectedUni == null) return;
    if (departments.isEmpty) {
      Get.snackbar('None', 'No departments available to delete');
      return;
    }

    String? toDelete;
    Get.dialog(
      AlertDialog(
        title: const Text('Delete Department'),
        content: StatefulBuilder(
          builder: (c, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: toDelete,
                  items: departments
                      .map(
                        (d) => DropdownMenuItem(
                          value: d['id'] as String,
                          child: Text(d['name']),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => toDelete = v),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Warning: This will delete the department and related timetables.',
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              if (toDelete == null) return;
              try {
                await _service.deleteDepartment(selectedUni!, toDelete!);
                await _fetchDepartments(selectedUni!);
                if (selectedDept == toDelete) {
                  selectedDept = null;
                  selectedDeptName = null;
                }
                setState(() {});
                Get.back();
                Get.snackbar(
                  'Deleted',
                  'Department removed',
                  backgroundColor: Colors.green.shade100,
                );
              } catch (e) {
                Get.snackbar(
                  'Error',
                  e.toString(),
                  backgroundColor: Colors.red.shade100,
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDeleteSectionDialog() {
    if (!isSuperAdmin || selectedUni == null || selectedDept == null) return;
    if (sections.isEmpty) {
      Get.snackbar('None', 'No sections available to delete');
      return;
    }

    String? toDelete;
    Get.dialog(
      AlertDialog(
        title: const Text('Delete Section'),
        content: StatefulBuilder(
          builder: (c, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: toDelete,
                  items: sections
                      .map(
                        (s) => DropdownMenuItem(
                          value: s['id'] as String,
                          child: Text(s['name']),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => toDelete = v),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Warning: This will delete the section and related timetables.',
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () async {
              if (toDelete == null) return;
              try {
                await _service.deleteSection(
                  selectedUni!,
                  selectedDept!,
                  toDelete!,
                );
                await _fetchSections(selectedUni!, selectedDept!);
                if (selectedSection == toDelete) {
                  selectedSection = null;
                  selectedSectionName = null;
                }
                setState(() {});
                Get.back();
                Get.snackbar(
                  'Deleted',
                  'Section removed',
                  backgroundColor: Colors.green.shade100,
                );
              } catch (e) {
                Get.snackbar(
                  'Error',
                  e.toString(),
                  backgroundColor: Colors.red.shade100,
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDeleteSemesterDialog() {
    if (!isSuperAdmin || selectedUni == null) return;
    String? sem;
    Get.dialog(
      AlertDialog(
        title: const Text('Delete Semester'),
        content: StatefulBuilder(
          builder: (c, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: sem,
                  hint: const Text('Select semester'),
                  items: semesters
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setState(() => sem = v),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Warning: This will delete all classes for the selected semester.',
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.brown),
            onPressed: () async {
              if (sem == null) return;
              try {
                await _service.deleteSemester(selectedUni!, sem!);
                setState(() {});
                Get.back();
                Get.snackbar(
                  'Deleted',
                  'Semester classes removed',
                  backgroundColor: Colors.green.shade100,
                );
              } catch (e) {
                Get.snackbar(
                  'Error',
                  e.toString(),
                  backgroundColor: Colors.red.shade100,
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDeleteShiftDialog() {
    if (!isSuperAdmin || selectedUni == null) return;
    String? sft = selectedShift;
    Get.dialog(
      AlertDialog(
        title: const Text('Delete Shift'),
        content: StatefulBuilder(
          builder: (c, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: sft,
                  hint: const Text('Select shift'),
                  items: const [
                    DropdownMenuItem(value: 'morning', child: Text('Morning')),
                    DropdownMenuItem(value: 'evening', child: Text('Evening')),
                  ],
                  onChanged: (v) => setState(() => sft = v),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Warning: This will delete all classes for the selected shift.',
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purpleAccent,
            ),
            onPressed: () async {
              if (sft == null) return;
              try {
                await _service.deleteShift(selectedUni!, sft!);
                setState(() {});
                Get.back();
                Get.snackbar(
                  'Deleted',
                  'Shift classes removed',
                  backgroundColor: Colors.green.shade100,
                );
              } catch (e) {
                Get.snackbar(
                  'Error',
                  e.toString(),
                  backgroundColor: Colors.red.shade100,
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // HELPER METHODS
  // ==========================================
  List<Map<String, String>> _getTimeSlots(String shift) {
    if (shift == 'morning') {
      // Morning: 08:00 - 16:00 (80-minute slots)
      return [
        {'start': '08:00', 'end': '09:20'},
        {'start': '09:20', 'end': '10:40'},
        {'start': '10:40', 'end': '12:00'},
        {'start': '12:00', 'end': '13:20'},
        {'start': '13:20', 'end': '14:40'},
        {'start': '14:40', 'end': '16:00'},
      ];
    } else {
      // Evening: 14:40 - 21:20
      return [
        {'start': '14:40', 'end': '16:00'},
        {'start': '16:00', 'end': '17:20'},
        {'start': '17:20', 'end': '18:40'},
        {'start': '18:40', 'end': '20:00'},
        {'start': '20:00', 'end': '21:20'},
      ];
    }
  }

  List<String> _getAvailableSlots(String shift, bool isLab) {
    if (shift == 'morning') {
      if (isLab) return ['08:00', '11:00'];
      return ['08:00', '09:20', '10:40', '12:00', '13:20'];
    } else {
      if (isLab) return ['14:40', '17:40'];
      return ['14:40', '16:00', '17:20', '18:40', '20:00'];
    }
  }

  int _timeToMinutes(String time) {
    try {
      final match = RegExp(r"(\d{1,2}:\d{2})").firstMatch(time);
      final normalized = match != null ? match.group(1)! : time;
      if (!normalized.contains(':')) return 0;
      final parts = normalized.split(':');
      final h = int.tryParse(parts[0].replaceAll(RegExp(r'\D'), '')) ?? 0;
      final m = int.tryParse(parts[1].replaceAll(RegExp(r'\D'), '')) ?? 0;
      return h * 60 + m;
    } catch (_) {
      return 0;
    }
  }

  String _normalizeToHHMM(String time) {
    try {
      final match = RegExp(r"(\d{1,2}:\d{2})").firstMatch(time);
      final normalized = match != null ? match.group(1)! : time;
      if (!normalized.contains(':')) return '00:00';
      final parts = normalized.split(':');
      final h = int.tryParse(parts[0].replaceAll(RegExp(r'\D'), '')) ?? 0;
      final m = int.tryParse(parts[1].replaceAll(RegExp(r'\D'), '')) ?? 0;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    } catch (_) {
      return '00:00';
    }
  }

  String _calculateEndTime(String startTime, bool isLab) {
    final startMin = _timeToMinutes(startTime);
    final duration = isLab ? 180 : 80;
    final endMin = startMin + duration;
    final hours = (endMin ~/ 60).toString().padLeft(2, '0');
    final mins = (endMin % 60).toString().padLeft(2, '0');
    return '$hours:$mins';
  }

  String _formatTime12(String t24) {
    try {
      final parts = t24.split(':');
      var h = int.parse(parts[0]);
      final m = parts.length > 1 ? parts[1] : '00';
      final suffix = h < 12 ? 'AM' : 'PM';
      final displayH = (h % 12 == 0) ? 12 : (h % 12);
      return '$displayH:$m $suffix';
    } catch (_) {
      return t24;
    }
  }
}
