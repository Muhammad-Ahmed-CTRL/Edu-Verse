import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../notifications.dart';

class TimetableService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Standardizes time to comparable integers (e.g., "08:30" -> 510 minutes)
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

  /// Converts minutes back to HH:MM format
  String _minutesToTime(int minutes) {
    final hours = (minutes ~/ 60).toString().padLeft(2, '0');
    final mins = (minutes % 60).toString().padLeft(2, '0');
    return '$hours:$mins';
  }

  // ==========================================
  // REQUIREMENT 5: CONFLICT CHECK (University-Wide)
  // ==========================================

  /// Checks across the ENTIRE University for Room and Teacher clashes
  /// This is CRITICAL - conflicts must be detected university-wide, not just per department
  Future<String?> checkConflict({
    required String uniId,
    required String day,
    required String startTime,
    required String endTime,
    required String room,
    required String teacher,
    String? excludeDocId,
  }) async {
    final startMin = _timeToMinutes(startTime);
    final endMin = _timeToMinutes(endTime);

    // Query ALL timetables for this University on this Day
    final snap = await _db
        .collection('universities')
        .doc(uniId)
        .collection('timetables')
        .where('day', isEqualTo: day)
        .get();

    for (var doc in snap.docs) {
      if (doc.id == excludeDocId) continue;

      final data = doc.data();
      final existingStart = _timeToMinutes(data['start']);
      final existingEnd = _timeToMinutes(data['end']);

      // Check Time Overlap: (start < existingEnd) AND (end > existingStart)
      bool overlap = (startMin < existingEnd && endMin > existingStart);

      if (overlap) {
        // Room Conflict (Case insensitive)
        if (data['location'].toString().toLowerCase() == room.toLowerCase()) {
          return "CONFLICT: Room '$room' is already occupied by ${data['subject']} (${data['departmentId']} - Sec ${data['sectionId']}) from ${data['start']} to ${data['end']}.";
        }

        // Teacher Conflict (Case insensitive)
        if (data['teacher'].toString().toLowerCase() == teacher.toLowerCase()) {
          return "CONFLICT: Teacher '$teacher' is already teaching ${data['subject']} in ${data['location']} (${data['departmentId']} - Sec ${data['sectionId']}) from ${data['start']} to ${data['end']}.";
        }
      }
    }
    return null; // No conflict
  }

  // ==========================================
  // REQUIREMENT 5: PUSH NOTIFICATION HOOK
  // ==========================================

  /// Placeholder for FCM integration
  /// Call this whenever a class is added, moved, or cancelled
  /// Topic format: 'timetable_{uniId}_{deptId}'
  void sendPushNotification(String topic, String message) {
    // TODO: Integrate with Firebase Cloud Messaging
    // For now, just log the notification
    print('📢 NOTIFICATION to $topic: $message');

    // Future implementation:
    // await FirebaseMessaging.instance.sendMessage(
    //   to: '/topics/$topic',
    //   data: {
    //     'title': 'Timetable Update',
    //     'body': message,
    //     'click_action': 'FLUTTER_NOTIFICATION_CLICK',
    //   },
    // );
  }

  // ==========================================
  // BASIC TIMETABLE OPERATIONS
  // ==========================================

  Future<void> addClass({
    required String uniId,
    required Map<String, dynamic> data,
  }) async {
    final docRef = await _db
        .collection('universities')
        .doc(uniId)
        .collection('timetables')
        .add(data);

    // Trigger notification about the new class
    try {
      final notifier = NotificationService();
      final subject = data['subject']?.toString() ?? 'Timetable update';
      await notifier.notifyTimetableUpdate(
        universityId: uniId,
        className: subject,
        userId: null,
      );
    } catch (e) {
      // Non-fatal: log and continue
      debugPrint('Failed to notify timetable update: $e');
    }
  }

  Future<void> deleteClass(String uniId, String docId) async {
    await _db
        .collection('universities')
        .doc(uniId)
        .collection('timetables')
        .doc(docId)
        .delete();
  }

  Future<String?> updateClassTime({
    required String uniId,
    required String docId,
    required String newStart,
    required String newEnd,
    required String day,
    required String room,
    required String teacher,
  }) async {
    // REQUIREMENT 5: Check conflicts before update
    final conflict = await checkConflict(
      uniId: uniId,
      day: day,
      startTime: newStart,
      endTime: newEnd,
      room: room,
      teacher: teacher,
      excludeDocId: docId,
    );

    if (conflict != null) {
      return conflict;
    }

    // Fetch doc to read subject for notification
    final docRef = _db.collection('universities').doc(uniId).collection('timetables').doc(docId);
    final doc = await docRef.get();
    final subject = (doc.exists ? (doc.data()?['subject'] as String?) : null) ?? 'Timetable update';

    await docRef.update({'start': newStart, 'end': newEnd});

    // Notify students about timetable change
    try {
      final notifier = NotificationService();
      await notifier.notifyTimetableUpdate(
        universityId: uniId,
        className: subject,
      );
    } catch (e) {
      debugPrint('Failed to notify timetable update: $e');
    }

    return null; // Success
  }

  Future<void> updateUserRole(
    String uid,
    String role,
    Map<String, dynamic>? scope,
  ) async {
    // Use callable Cloud Function to perform privileged role updates and set claims.
    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('setUserRole');
      await callable.call(<String, dynamic>{
        'uid': uid,
        'role': role,
        'scope': scope,
      });
      return;
    } catch (e) {
      // If callable fails because Functions aren't deployed or billing, fallback to direct Firestore update.
      // This fallback may fail with permission-denied; bubble that to UI.
      try {
        final userRef = _db.collection('users').doc(uid);
        Map<String, dynamic> updateData = {'role': role};
        if (scope != null) {
          updateData['adminScope'] = scope;
        } else {
          updateData['adminScope'] = FieldValue.delete();
        }
        await userRef.update(updateData);
        // Maintain universities/{uni}/admins/{uid} doc when assigning admin via client fallback
        if (role == 'admin' && scope != null && scope['uniId'] != null) {
          final adminRef = _db
              .collection('universities')
              .doc(scope['uniId'])
              .collection('admins')
              .doc(uid);
          await adminRef.set({'deptId': scope['deptId']});
        } else {
          // remove admin docs if exist
          final unis = await _db.collection('universities').get();
          for (var u in unis.docs) {
            final adminRef = _db
                .collection('universities')
                .doc(u.id)
                .collection('admins')
                .doc(uid);
            final snap = await adminRef.get();
            if (snap.exists) await adminRef.delete();
          }
        }
        return;
      } catch (inner) {
        rethrow;
      }
    }
  }

  Stream<QuerySnapshot> getAdminTimetableStream({
    required String uniId,
    String? deptId,
    String? sectionId,
    String? shift,
    String? semester,
  }) {
    Query query =
        _db.collection('universities').doc(uniId).collection('timetables');

    if (deptId != null && deptId.isNotEmpty) {
      query = query.where('departmentId', isEqualTo: deptId);
    }
    if (sectionId != null && sectionId.isNotEmpty) {
      query = query.where('sectionId', isEqualTo: sectionId);
    }
    if (shift != null && shift.isNotEmpty) {
      query = query.where('shift', isEqualTo: shift);
    }
    if (semester != null && semester.isNotEmpty) {
      query = query.where('semester', isEqualTo: semester);
    }

    return query.snapshots();
  }

  Stream<QuerySnapshot> getStudentStream({
    required String uniId,
    required String deptId,
    required String sectionId,
    required String shift,
    String? semester,
  }) {
    Query query = _db
        .collection('universities')
        .doc(uniId)
        .collection('timetables')
        .where('departmentId', isEqualTo: deptId)
        .where('sectionId', isEqualTo: sectionId)
        .where('shift', isEqualTo: shift);
    if (semester != null && semester.isNotEmpty) {
      query = query.where('semester', isEqualTo: semester);
    }
    return query.snapshots();
  }

  // ==========================================
  // REQUIREMENT 4: STRUCTURAL CRUD OPERATIONS
  // ==========================================

  // === UNIVERSITY MANAGEMENT ===

  Future<String> addUniversity(String name) async {
    final docRef = await _db.collection('universities').add({
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<void> updateUniversity(String uniId, String name) async {
    await _db.collection('universities').doc(uniId).update({
      'name': name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteUniversity(String uniId) async {
    // Delete all subcollections first
    final deptSnap = await _db
        .collection('universities')
        .doc(uniId)
        .collection('departments')
        .get();

    for (var dept in deptSnap.docs) {
      await deleteDepartment(uniId, dept.id);
    }

    // Delete all timetables
    final timetableSnap = await _db
        .collection('universities')
        .doc(uniId)
        .collection('timetables')
        .get();

    for (var tt in timetableSnap.docs) {
      await tt.reference.delete();
    }

    // Finally delete the university document
    await _db.collection('universities').doc(uniId).delete();
  }

  Future<List<Map<String, dynamic>>> getAllUniversities() async {
    final snap = await _db.collection('universities').get();
    return snap.docs
        .map((d) => {'id': d.id, 'name': d['name'] ?? d.id})
        .toList();
  }

  // === DEPARTMENT MANAGEMENT ===

  Future<String> addDepartment(String uniId, String name) async {
    final docRef = await _db
        .collection('universities')
        .doc(uniId)
        .collection('departments')
        .add({'name': name, 'createdAt': FieldValue.serverTimestamp()});
    return docRef.id;
  }

  Future<void> updateDepartment(
    String uniId,
    String deptId,
    String name,
  ) async {
    await _db
        .collection('universities')
        .doc(uniId)
        .collection('departments')
        .doc(deptId)
        .update({'name': name, 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> deleteDepartment(String uniId, String deptId) async {
    // Delete all sections first
    final sectionSnap = await _db
        .collection('universities')
        .doc(uniId)
        .collection('departments')
        .doc(deptId)
        .collection('sections')
        .get();

    for (var section in sectionSnap.docs) {
      await section.reference.delete();
    }

    // Delete all timetables for this department
    final timetableSnap = await _db
        .collection('universities')
        .doc(uniId)
        .collection('timetables')
        .where('departmentId', isEqualTo: deptId)
        .get();

    for (var tt in timetableSnap.docs) {
      await tt.reference.delete();
    }

    // Finally delete the department document
    await _db
        .collection('universities')
        .doc(uniId)
        .collection('departments')
        .doc(deptId)
        .delete();
  }

  Future<List<Map<String, dynamic>>> getDepartments(String uniId) async {
    final snap = await _db
        .collection('universities')
        .doc(uniId)
        .collection('departments')
        .get();
    return snap.docs
        .map((d) => {'id': d.id, 'name': d['name'] ?? d.id})
        .toList();
  }

  // === SECTION MANAGEMENT ===

  Future<String> addSection(String uniId, String deptId, String name) async {
    final docRef = await _db
        .collection('universities')
        .doc(uniId)
        .collection('departments')
        .doc(deptId)
        .collection('sections')
        .add({'name': name, 'createdAt': FieldValue.serverTimestamp()});
    return docRef.id;
  }

  Future<void> updateSection(
    String uniId,
    String deptId,
    String sectionId,
    String name,
  ) async {
    await _db
        .collection('universities')
        .doc(uniId)
        .collection('departments')
        .doc(deptId)
        .collection('sections')
        .doc(sectionId)
        .update({'name': name, 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> deleteSection(
    String uniId,
    String deptId,
    String sectionId,
  ) async {
    // Delete all timetables for this section
    final timetableSnap = await _db
        .collection('universities')
        .doc(uniId)
        .collection('timetables')
        .where('departmentId', isEqualTo: deptId)
        .where('sectionId', isEqualTo: sectionId)
        .get();

    for (var tt in timetableSnap.docs) {
      await tt.reference.delete();
    }

    // Delete the section document
    await _db
        .collection('universities')
        .doc(uniId)
        .collection('departments')
        .doc(deptId)
        .collection('sections')
        .doc(sectionId)
        .delete();
  }

  /// Deletes all timetable entries for a given semester in a university.
  Future<void> deleteSemester(String uniId, String semester) async {
    final snap = await _db
        .collection('universities')
        .doc(uniId)
        .collection('timetables')
        .where('semester', isEqualTo: semester)
        .get();

    for (var doc in snap.docs) {
      await doc.reference.delete();
    }
  }

  /// Deletes all timetable entries for a given shift in a university.
  Future<void> deleteShift(String uniId, String shift) async {
    final snap = await _db
        .collection('universities')
        .doc(uniId)
        .collection('timetables')
        .where('shift', isEqualTo: shift)
        .get();

    for (var doc in snap.docs) {
      await doc.reference.delete();
    }
  }

  Future<List<Map<String, dynamic>>> getSections(
    String uniId,
    String deptId,
  ) async {
    final snap = await _db
        .collection('universities')
        .doc(uniId)
        .collection('departments')
        .doc(deptId)
        .collection('sections')
        .get();
    return snap.docs
        .map((d) => {'id': d.id, 'name': d['name'] ?? d.id})
        .toList();
  }

  // ==========================================
  // ADVANCED USER FILTERING
  // ==========================================

  /// Get filtered users based on admin scope and selections
  Future<List<Map<String, dynamic>>> getFilteredUsers({
    String? uniId,
    String? deptId,
    String? sectionId,
    String? shift,
    String? semester,
  }) async {
    Query query = _db.collection('users');

    if (uniId != null && uniId.isNotEmpty) {
      query = query.where('uniId', isEqualTo: uniId);
    }

    if (deptId != null && deptId.isNotEmpty) {
      query = query.where('departmentId', isEqualTo: deptId);
    }

    if (sectionId != null && sectionId.isNotEmpty) {
      query = query.where('sectionId', isEqualTo: sectionId);
    }

    if (shift != null && shift.isNotEmpty) {
      query = query.where('shift', isEqualTo: shift);
    }
    if (semester != null && semester.isNotEmpty) {
      query = query.where('semester', isEqualTo: semester);
    }

    final snap = await query.get();
    return snap.docs
        .map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>})
        .toList();
  }

  /// Count users in a specific context
  Future<int> countUsers({
    String? uniId,
    String? deptId,
    String? sectionId,
    String? shift,
    String? semester,
  }) async {
    final users = await getFilteredUsers(
      uniId: uniId,
      deptId: deptId,
      sectionId: sectionId,
      shift: shift,
      semester: semester,
    );
    return users.length;
  }

  /// Get statistics for admin dashboard
  Future<Map<String, dynamic>> getAdminStats({
    required String uniId,
    String? deptId,
    String? sectionId,
    String? semester,
  }) async {
    int totalClasses = 0;
    int totalStudents = 0;
    int totalTeachers = 0;

    // Count classes
    Query classQuery =
        _db.collection('universities').doc(uniId).collection('timetables');

    if (deptId != null && deptId.isNotEmpty) {
      classQuery = classQuery.where('departmentId', isEqualTo: deptId);
    }

    if (sectionId != null && sectionId.isNotEmpty) {
      classQuery = classQuery.where('sectionId', isEqualTo: sectionId);
    }
    if (semester != null && semester.isNotEmpty) {
      classQuery = classQuery.where('semester', isEqualTo: semester);
    }

    final classSnap = await classQuery.get();
    totalClasses = classSnap.docs.length;

    // Count unique teachers
    final teachers = classSnap.docs
        .map((d) => (d.data() as Map)['teacher'] as String)
        .toSet();
    totalTeachers = teachers.length;

    // Count students
    final students = await getFilteredUsers(
      uniId: uniId,
      deptId: deptId,
      sectionId: sectionId,
    );
    totalStudents = students.where((u) => u['role'] == 'student').length;

    return {
      'totalClasses': totalClasses,
      'totalStudents': totalStudents,
      'totalTeachers': totalTeachers,
    };
  }

  // ==========================================
  // BATCH OPERATIONS FOR WIZARD FLOW
  // ==========================================

  /// Creates a complete hierarchy: University -> Departments -> Sections
  Future<Map<String, String>> createCompleteHierarchy({
    required String uniName,
    required List<String> departmentNames,
    required List<String> sectionNames,
  }) async {
    // Create university
    final uniId = await addUniversity(uniName);

    final deptIds = <String>[];

    // Create departments
    for (final deptName in departmentNames) {
      final deptId = await addDepartment(uniId, deptName);
      deptIds.add(deptId);

      // Create sections for each department
      for (final sectionName in sectionNames) {
        await addSection(uniId, deptId, sectionName);
      }
    }

    return {
      'uniId': uniId,
      'firstDeptId': deptIds.isNotEmpty ? deptIds.first : '',
    };
  }

  /// Validates if a time slot is available across the university
  Future<bool> isSlotAvailable({
    required String uniId,
    required String day,
    required String startTime,
    required String endTime,
    required String room,
  }) async {
    final conflict = await checkConflict(
      uniId: uniId,
      day: day,
      startTime: startTime,
      endTime: endTime,
      room: room,
      teacher: '',
    );
    return conflict == null;
  }

  /// Get all conflicts for a specific day/shift
  Future<List<Map<String, dynamic>>> getConflictsForDay({
    required String uniId,
    required String day,
    String? shift,
  }) async {
    Query query = _db
        .collection('universities')
        .doc(uniId)
        .collection('timetables')
        .where('day', isEqualTo: day);

    if (shift != null && shift.isNotEmpty) {
      query = query.where('shift', isEqualTo: shift);
    }

    final snap = await query.get();
    final classes = snap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      return {'id': d.id, ...data};
    }).toList();

    final conflicts = <Map<String, dynamic>>[];

    for (var i = 0; i < classes.length; i++) {
      for (var j = i + 1; j < classes.length; j++) {
        final c1 = classes[i];
        final c2 = classes[j];

        final start1 = _timeToMinutes(c1['start']);
        final end1 = _timeToMinutes(c1['end']);
        final start2 = _timeToMinutes(c2['start']);
        final end2 = _timeToMinutes(c2['end']);

        final overlap = (start1 < end2 && end1 > start2);

        if (overlap) {
          if (c1['location'].toString().toLowerCase() ==
              c2['location'].toString().toLowerCase()) {
            conflicts.add({
              'type': 'room',
              'class1': c1,
              'class2': c2,
              'resource': c1['location'],
            });
          }

          if (c1['teacher'].toString().toLowerCase() ==
              c2['teacher'].toString().toLowerCase()) {
            conflicts.add({
              'type': 'teacher',
              'class1': c1,
              'class2': c2,
              'resource': c1['teacher'],
            });
          }
        }
      }
    }

    return conflicts;
  }
}
