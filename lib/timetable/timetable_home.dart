import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:reclaimify/theme_colors.dart'; // Ensure this matches your pubspec.yaml name
import '../homepage/admin_dashboard.dart';
import '../shared.dart';
import 'timetable_service.dart';

class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _service = TimetableService();

  String? uniId, deptId, sectionId, shift;
  String? semester;
  bool isSuperAdmin = false;
  bool isAdmin = false;

  List<Map<String, dynamic>> universities = [];
  List<Map<String, dynamic>> departments = [];
  List<Map<String, dynamic>> sections = [];

  bool isLoading = true;
  String selectedDay = 'Monday';
  bool _showGridLayout = false;

  // ONLY 5 DAYS - NO SATURDAY
  final List<String> days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday'
  ];

  @override
  void initState() {
    super.initState();
    _loadUserContext();
  }

  Future<void> _loadUserContext() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => isLoading = false);
      return;
    }

    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            final role = data?['role']?.toString();
            isSuperAdmin = (role == 'super_admin');
            isAdmin = (role == 'admin' || role == 'super_admin');

            uniId = data?['uniId']?.toString();
            deptId = data?['departmentId']?.toString();
            sectionId = data?['sectionId']?.toString();
            shift = data?['shift']?.toString();
            semester = data?['semester']?.toString();

            final adminScope = data?['adminScope'] as Map<String, dynamic>?;
            if (uniId == null &&
                adminScope != null &&
                adminScope['uniId'] != null) {
              uniId = adminScope['uniId']?.toString();
            }
          });
        }

        if (isSuperAdmin) {
          await _fetchUniversities();
        }
      }
    } catch (e) {
      debugPrint('Error loading user context: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _fetchUniversities() async {
    try {
      final list = await _service.getAllUniversities();
      if (mounted) {
        setState(() {
          universities = list;
        });
      }
    } catch (e) {
      debugPrint('Error fetching universities: $e');
    }
  }

  Future<void> _fetchDepartments(String universityId) async {
    try {
      final list = await _service.getDepartments(universityId);
      if (mounted) {
        setState(() {
          departments = list;
        });
      }
    } catch (e) {
      debugPrint('Error fetching departments: $e');
    }
  }

  Future<void> _fetchSections(String universityId, String departmentId) async {
    try {
      final list = await _service.getSections(universityId, departmentId);
      if (mounted) {
        setState(() {
          sections = list;
        });
      }
    } catch (e) {
      debugPrint('Error fetching sections: $e');
    }
  }

  /// Helper to get a card surface color that is distinctly lighter than the background in Dark Mode.
  Color _getCardSurfaceColor(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // In dark mode, use a lighter purple/blue shade (0xFF3F376F) so it pops against the dark bg (0xFF2D2557).
    // In light mode, use white.
    return isDark ? const Color(0xFF3F376F) : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: getAppBackgroundColor(context),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (uniId == null) {
      if (isSuperAdmin) {
        return _buildSuperAdminUniversitySelector();
      }
      return Scaffold(
        backgroundColor: getAppBackgroundColor(context),
        appBar: AppBar(
          title: const Text('My Timetable'),
          backgroundColor: isSuperAdmin ? Colors.purple : AppColors.mainColor,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Text(
            "Error: No University Linked to your account",
            style: TextStyle(color: getAppTextColor(context)),
          ),
        ),
      );
    }

    if (isSuperAdmin && (deptId == null || sectionId == null)) {
      return _buildSuperAdminDepartmentSelector();
    }

    return _buildTimetableView();
  }

  Widget _buildSuperAdminUniversitySelector() {
    final cardColor = _getCardSurfaceColor(context);

    if (universities.isEmpty) {
      return Scaffold(
        backgroundColor: getAppBackgroundColor(context),
        appBar: AppBar(
          title: const Text('My Timetable'),
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.school, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'No universities found.',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: getAppTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please add a university from the Admin Dashboard.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
                onPressed: _fetchUniversities,
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.admin_panel_settings),
                label: const Text('Open Admin Dashboard'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminDashboard()),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: getAppBackgroundColor(context),
      appBar: AppBar(
        title: const Text('Select University'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are signed in as Super Admin.',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: getAppTextColor(context),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please select a university to view its timetable.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              value: (() {
                final uniqueUnis = {
                  for (var u in universities) (u['id'] as String): u
                }.values.toList();
                return uniqueUnis.any((u) => u['id'] == uniId) ? uniId : null;
              })(),
              items: (() {
                final uniqueUnis = {
                  for (var u in universities) (u['id'] as String): u
                }.values.toList();
                return uniqueUnis
                    .map((u) => DropdownMenuItem<String>(
                        value: u['id'] as String,
                        child: Text(
                          u['name'] ?? u['id']!,
                          style: TextStyle(color: getAppTextColor(context)),
                        )))
                    .toList();
              })(),
              dropdownColor: cardColor,
              onChanged: (val) async {
                setState(() {
                  uniId = val;
                  deptId = null;
                  sectionId = null;
                });
                if (val != null) {
                  await _fetchDepartments(val);
                }
              },
              decoration: InputDecoration(
                labelText: 'University',
                filled: true,
                fillColor: cardColor,
                border: const OutlineInputBorder(),
                labelStyle: TextStyle(color: getAppTextColor(context)),
              ),
            ),
            const SizedBox(height: 16),
            if (isAdmin)
              ElevatedButton.icon(
                icon: const Icon(Icons.admin_panel_settings),
                label: const Text('Go to Admin Dashboard'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminDashboard()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuperAdminDepartmentSelector() {
    final cardColor = _getCardSurfaceColor(context);

    return Scaffold(
      backgroundColor: getAppBackgroundColor(context),
      appBar: AppBar(
        title: const Text('Select Department & Section'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() {
            uniId = null;
            deptId = null;
            sectionId = null;
          }),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'University: ${universities.firstWhere((u) => u['id'] == uniId, orElse: () => {
                    'name': uniId
                  })['name']}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: getAppTextColor(context),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select a department and section to view the timetable:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              value: (() {
                final uniqueDepts = {
                  for (var d in departments) (d['id'] as String): d
                }.values.toList();
                return uniqueDepts.any((d) => d['id'] == deptId)
                    ? deptId
                    : null;
              })(),
              items: (() {
                final uniqueDepts = {
                  for (var d in departments) (d['id'] as String): d
                }.values.toList();
                return uniqueDepts
                    .map((d) => DropdownMenuItem<String>(
                        value: d['id'] as String,
                        child: Text(
                          d['name'] ?? d['id']!,
                          style: TextStyle(color: getAppTextColor(context)),
                        )))
                    .toList();
              })(),
              dropdownColor: cardColor,
              onChanged: (val) async {
                setState(() {
                  deptId = val;
                  sectionId = null;
                });
                if (val != null && uniId != null) {
                  await _fetchSections(uniId!, val);
                }
              },
              decoration: InputDecoration(
                labelText: 'Department',
                filled: true,
                fillColor: cardColor,
                border: const OutlineInputBorder(),
                labelStyle: TextStyle(color: getAppTextColor(context)),
              ),
            ),
            const SizedBox(height: 16),
            if (deptId != null)
              DropdownButtonFormField<String>(
                value: (() {
                  final uniqueSecs = {
                    for (var s in sections) (s['id'] as String): s
                  }.values.toList();
                  return uniqueSecs.any((s) => s['id'] == sectionId)
                      ? sectionId
                      : null;
                })(),
                items: (() {
                  final uniqueSecs = {
                    for (var s in sections) (s['id'] as String): s
                  }.values.toList();
                  return uniqueSecs
                      .map((s) => DropdownMenuItem<String>(
                          value: s['id'] as String,
                          child: Text(
                            s['name'] ?? s['id']!,
                            style: TextStyle(color: getAppTextColor(context)),
                          )))
                      .toList();
                })(),
                dropdownColor: cardColor,
                onChanged: (val) => setState(() => sectionId = val),
                decoration: InputDecoration(
                  labelText: 'Section',
                  filled: true,
                  fillColor: cardColor,
                  border: const OutlineInputBorder(),
                  labelStyle: TextStyle(color: getAppTextColor(context)),
                ),
              ),
            const SizedBox(height: 16),
            if (deptId != null)
              DropdownButtonFormField<String>(
                value: shift ?? 'morning',
                items: [
                  DropdownMenuItem(
                      value: 'morning',
                      child: Text(
                        'Morning',
                        style: TextStyle(color: getAppTextColor(context)),
                      )),
                  DropdownMenuItem(
                      value: 'evening',
                      child: Text(
                        'Evening',
                        style: TextStyle(color: getAppTextColor(context)),
                      )),
                ],
                dropdownColor: cardColor,
                onChanged: (val) => setState(() => shift = val),
                decoration: InputDecoration(
                  labelText: 'Shift',
                  filled: true,
                  fillColor: cardColor,
                  border: const OutlineInputBorder(),
                  labelStyle: TextStyle(color: getAppTextColor(context)),
                ),
              ),
            const SizedBox(height: 24),
            if (isAdmin)
              ElevatedButton.icon(
                icon: const Icon(Icons.admin_panel_settings),
                label: const Text('Go to Admin Dashboard'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminDashboard()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimetableView() {
    return Scaffold(
      backgroundColor: getAppBackgroundColor(context),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Timetable'),
            Text(
              '${deptId?.toUpperCase()} - Sec $sectionId ($shift)',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: isSuperAdmin ? Colors.purple : AppColors.mainColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_showGridLayout ? Icons.view_list : Icons.grid_on),
            tooltip: 'Toggle timetable layout',
            onPressed: () => setState(() => _showGridLayout = !_showGridLayout),
          ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminDashboard()),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_showGridLayout) _buildDaySelector(),
          Expanded(
            child: _showGridLayout
                ? _buildLandscapeGridView()
                : _buildTimetableContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildDaySelector() {
    // Use the lighter card color for the day selector background too
    final cardColor = _getCardSurfaceColor(context);
    
    return Container(
      height: 60,
      color: cardColor, 
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        itemBuilder: (c, i) {
          final day = days[i];
          final isSelected = day == selectedDay;
          return GestureDetector(
            onTap: () => setState(() => selectedDay = day),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(
                border: isSelected
                    ? Border(
                        bottom: BorderSide(
                          color: isSuperAdmin
                              ? Colors.purple
                              : AppColors.mainColor,
                          width: 3,
                        ),
                      )
                    : null,
              ),
              child: Text(
                day,
                style: TextStyle(
                  color: isSelected
                      ? (isSuperAdmin ? Colors.purple : AppColors.mainColor)
                      : getAppTextColor(context).withOpacity(0.6),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimetableContent() {
    return StreamBuilder<QuerySnapshot>(
      stream: _service.getAdminTimetableStream(
        uniId: uniId!,
        deptId: deptId,
        sectionId: sectionId,
        shift: shift,
        semester: semester,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        final docs =
            snapshot.data!.docs.where((d) => d['day'] == selectedDay).toList();

        docs.sort(
            (a, b) => (a['start'] as String).compareTo(b['start'] as String));

        if (docs.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _buildClassCard(data);
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.weekend, size: 50, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text(
            "No classes on $selectedDay",
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildClassCard(Map<String, dynamic> data) {
    // Specifically use lighter surface color so cards pop against dark background
    final cardColor = _getCardSurfaceColor(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: Color(data['colorValue'] ?? 0xFF3498DB),
            width: 6,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 5,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                _formatTime12(data['start'] ?? ''),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: getAppTextColor(context),
                ),
              ),
              Text(
                _formatTime12(data['end'] ?? ''),
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['subject'],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: getAppTextColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      data['location'],
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 15),
                    Icon(Icons.person, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        data['teacher'],
                        style: TextStyle(color: Colors.grey[600]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // LANDSCAPE GRID: Days on LEFT, Times on TOP
  Widget _buildLandscapeGridView() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gridBorderColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;

    return StreamBuilder<QuerySnapshot>(
      stream: _service.getAdminTimetableStream(
        uniId: uniId!,
        deptId: deptId,
        sectionId: sectionId,
        shift: shift,
        semester: semester,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        final docs = snapshot.data!.docs;
        final timeSlots = _getTimeSlots(shift ?? 'morning');

        // Map classes by day and assign to the correct time slot (range-based)
        final Map<String, List<QueryDocumentSnapshot>> classesByCell = {};
        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final day = data['day'] as String? ?? '';

          // Skip Saturday
          if (day == 'Saturday') continue;

          final startTime = data['start'] as String? ?? '';
          final startMin = _timeToMinutes(startTime);

          // find matching slot by range
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

            final normalizedKey = '$day-${_normalizeToHHMM(matchedSlotStart ?? startTime)}';
            classesByCell.putIfAbsent(normalizedKey, () => []).add(doc);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            // LANDSCAPE: Days vertical, Times horizontal
            const dayColumnWidth = 55.0;
            const timeHeaderHeight = 45.0;

            final availableWidth = constraints.maxWidth - dayColumnWidth;
            final timeColumnWidth = availableWidth / timeSlots.length;

            final availableHeight = constraints.maxHeight - timeHeaderHeight;
            final dayRowHeight = availableHeight / days.length;

            return Column(
              children: [
                // Header Row - Time slots across the top
                Container(
                  height: timeHeaderHeight,
                  child: Row(
                    children: [
                      // Empty corner
                      SizedBox(
                        width: dayColumnWidth,
                        child: Container(
                          color: AppColors.mainColor,
                        ),
                      ),
                      // Time headers
                      ...timeSlots.map((slot) => SizedBox(
                            width: timeColumnWidth,
                            child: Container(
                              color: AppColors.mainColor,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Text(
                                    _formatTime12Hour(slot['start']!),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 9,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          )),
                    ],
                  ),
                ),

                // Rows for each day
                Expanded(
                  child: ListView.builder(
                    itemCount: days.length,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (context, dayIndex) {
                      final day = days[dayIndex];

                      return SizedBox(
                        height: dayRowHeight,
                        child: Row(
                          children: [
                            // Day name cell
                            SizedBox(
                              width: dayColumnWidth,
                              child: Container(
                                color: AppColors.mainColor,
                                child: Center(
                                  child: RotatedBox(
                                    quarterTurns: 0,
                                    child: Text(
                                      day.substring(0, 3).toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Class cells for each time slot
                            ...timeSlots.map((slot) {
                              final cellKey = '$day-${_normalizeToHHMM(slot['start']!)}';
                              final cellDocs = classesByCell[cellKey] ?? [];

                              return SizedBox(
                                width: timeColumnWidth,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: gridBorderColor,
                                      width: 0.5,
                                    ),
                                  ),
                                  child: cellDocs.isEmpty
                                      ? const SizedBox.shrink()
                                      : _buildGridClassCell(
                                          cellDocs.first,
                                          timeColumnWidth,
                                          dayRowHeight,
                                        ),
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildGridClassCell(
    QueryDocumentSnapshot doc,
    double width,
    double height,
  ) {
    final data = doc.data() as Map<String, dynamic>;
    final color = Color(data['colorValue'] ?? 0xFF3498DB);
    final subject = data['subject'] ?? '';
    final teacher = data['teacher'] ?? '';
    final location = data['location'] ?? '';

    return Container(
      width: width,
      height: height,
      color: color,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            subject,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          if (teacher.isNotEmpty)
            Text(
              teacher,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 8,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (location.isNotEmpty)
            Text(
              location,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 7,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  // TIME SLOTS - NO 9:20 SLOT
  List<Map<String, String>> _getTimeSlots(String shift) {
    if (shift == 'morning') {
      // Morning: 08:00 - 16:00 with 80-minute slots
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

  int _timeToMinutes(String time) {
    try {
      final match = RegExp(r"(\d{1,2}:\d{2})").firstMatch(time);
      final normalized = match != null ? match.group(1)! : time;
      if (!normalized.contains(':')) return 0;
      final parts = normalized.split(':');
      final h = int.tryParse(parts[0].replaceAll(RegExp(r'\D'), '')) ?? 0;
      final m = parts.length > 1
          ? int.tryParse(parts[1].replaceAll(RegExp(r'\D'), '')) ?? 0
          : 0;
      return h * 60 + m;
    } catch (_) {
      return 0;
    }
  }

  String _normalizeToHHMM(String time) {
    final mins = _timeToMinutes(time);
    final h = (mins ~/ 60).toString().padLeft(2, '0');
    final m = (mins % 60).toString().padLeft(2, '0');
    return '$h:$m';
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

  String _formatTime12Hour(String t24) {
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