// lib/complaints/services/complaint_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/complaint_model.dart';

class ComplaintService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static const String _collectionName = 'complaints';
  static const String _anonymousId = 'ANONYMOUS_USER';

  // Submit a new complaint
  Future<String> submitComplaint({
    required String title,
    required String description,
    required ComplaintCategory category,
    required ComplaintUrgency urgency,
    required bool isAnonymous,
    required String uniId,
    required String deptId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Basic validation: ensure university and department are provided
      if (uniId.isEmpty || deptId.isEmpty) {
        throw Exception(
            'Missing university or department information in user profile. Please update your profile.');
      }

      final complaint = ComplaintModel(
        id: '',
        title: title,
        description: description,
        category: category,
        urgency: urgency,
        status: ComplaintStatus.pending,
        isAnonymous: isAnonymous,
        // Always record the submitting user's uid so the student can see
        // their own complaint progress even when they choose to remain
        // anonymous to admins. The `isAnonymous` flag controls whether
        // display fields (like `studentName`) are populated.
        studentId: user.uid,
        uniId: uniId,
        deptId: deptId,
        createdAt: DateTime.now(),
      );

      // Attempt to enrich complaint with submitter display fields so admin UI
      // doesn't need to perform extra lookups at render time. If any of the
      // fields are unavailable, they will be omitted.
      String? studentName;
      String? uniName;
      String? deptName;
      String? sectionId;
      String? sectionName;
      String? semester;
      String? shift;

      if (!isAnonymous) {
        try {
          final userDoc =
              await _firestore.collection('users').doc(user!.uid).get();
          final udata = userDoc.data();
          if (udata != null) {
            studentName = (udata['displayName'] ??
                udata['name'] ??
                user.displayName) as String?;
            // user profile may already contain friendly dept/section names
            deptName = udata['deptName'] ?? udata['departmentName'] as String?;
            sectionId = udata['sectionId'] ?? udata['section'] as String?;
            sectionName = udata['sectionName'] as String?;
            semester = udata['semester']?.toString();
            shift = udata['shift']?.toString();
          }

          // Resolve university name
          final uniDoc =
              await _firestore.collection('universities').doc(uniId).get();
          if (uniDoc.exists) {
            final u = uniDoc.data();
            uniName = (u?['name'] ?? u?['title']) as String?;
          }

          // If deptName or sectionName missing, try resolving from university
          if ((deptName == null || deptName.isEmpty) && deptId.isNotEmpty) {
            final ddoc = await _firestore
                .collection('universities')
                .doc(uniId)
                .collection('departments')
                .doc(deptId)
                .get();
            final ddata = ddoc.data();
            deptName =
                (ddata?['name'] ?? ddata?['title']) as String? ?? deptName;
          }
          if ((sectionName == null || sectionName.isEmpty) &&
              sectionId != null &&
              sectionId!.isNotEmpty) {
            final sdoc = await _firestore
                .collection('universities')
                .doc(uniId)
                .collection('sections')
                .doc(sectionId)
                .get();
            final sdata = sdoc.data();
            sectionName =
                (sdata?['name'] ?? sdata?['title']) as String? ?? sectionName;
          }
        } catch (_) {
          // Non-fatal: enrichment failed, proceed without extra fields
        }
      }

      // Rebuild complaint data to include optional display fields
      // If the complaint was submitted anonymously, do not include
      // the `studentName` field so admins see it as anonymous. Otherwise
      // include the resolved `studentName` for admin context.
      final enriched = complaint.copyWith(
        studentName: isAnonymous ? null : studentName,
        uniName: uniName,
        deptName: deptName,
        sectionId: sectionId,
        sectionName: sectionName,
        semester: semester,
        shift: shift,
      );

      try {
        // Create in a batch: write to root collection and mirror under universities/{uniId}/complaints
        final docRef = _firestore.collection(_collectionName).doc();
        final uniRef = _firestore
            .collection('universities')
            .doc(uniId)
            .collection('complaints')
            .doc(docRef.id);

        final data = enriched.toFirestore();

        final batch = _firestore.batch();
        batch.set(docRef, data);
        batch.set(uniRef, data);
        await batch.commit();

        // Notify student that complaint was submitted
        try {
          final studentId = enriched.studentId;
          if (studentId != null && studentId.isNotEmpty) {
            await NotificationService().notifyComplaintStatus(
              userId: studentId,
              universityId: uniId,
              isResolved: false,
              complaintTitle: enriched.title,
              complaintId: docRef.id,
            );
          }
        } catch (e) {
          debugPrint('Failed to notify complaint submission: $e');
        }

        return docRef.id;
      } on FirebaseException catch (fe) {
        if (fe.code == 'permission-denied') {
          throw Exception(
              'Permission denied when creating complaint. Check Firestore security rules and ensure authenticated users are allowed to create complaints. (${fe.message})');
        }
        rethrow;
      }
    } catch (e) {
      throw Exception('Failed to submit complaint: $e');
    }
  }

  // Get student's own complaints stream
  Stream<List<ComplaintModel>> getStudentComplaints() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    // Read from root collection where studentId == uid
    return _firestore
        .collection(_collectionName)
        .where('studentId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ComplaintModel.fromFirestore(doc))
            .toList());
  }

  // Get all complaints for admin (filtered by university and department)
  Stream<List<ComplaintModel>> getAdminComplaints({
    required String uniId,
    required String deptId,
    ComplaintStatus? statusFilter,
  }) {
    // Build base query. Only apply `uniId` filter if provided — passing an
    // empty string will otherwise restrict results to uniId == ''.
    Query query = _firestore.collection(_collectionName);

    if (uniId.isNotEmpty) {
      query = query.where('uniId', isEqualTo: uniId);
    }

    if (deptId.isNotEmpty) {
      query = query.where('deptId', isEqualTo: deptId);
    }

    if (statusFilter != null) {
      query = query.where('status', isEqualTo: statusFilter.name);
    }

    return query.orderBy('createdAt', descending: true).snapshots().map(
        (snapshot) => snapshot.docs
            .map((doc) => ComplaintModel.fromFirestore(doc))
            .toList());
  }

  // Fallback: fetch a small set of recent complaints without composite filters.
  // Useful when composite index is missing or building — returns an empty
  // list on failure so callers can gracefully handle it.
  Future<List<ComplaintModel>> getRecentComplaintsFallback(
      {int limit = 20}) async {
    try {
      final snapshot = await _firestore
          .collection(_collectionName)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => ComplaintModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      // Log and return empty so UI can decide what to show.
      print('ComplaintService: fallback fetch failed: $e');
      return [];
    }
  }

  // Fallback: fetch recent complaints for a specific student without ordering
  // that could require a composite index. This helps student view when the
  // ordered snapshots query fails due to missing composite index.
  Future<List<ComplaintModel>> getStudentComplaintsFallback(
      {required String studentId, int limit = 20}) async {
    try {
      final snapshot = await _firestore
          .collection(_collectionName)
          .where('studentId', isEqualTo: studentId)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => ComplaintModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('ComplaintService: student fallback fetch failed: $e');
      return [];
    }
  }

  // Update complaint status
  Future<void> updateComplaintStatus({
    required String complaintId,
    required ComplaintStatus newStatus,
  }) async {
    try {
      // Update both root doc and mirrored uni doc if present
      final rootRef = _firestore.collection(_collectionName).doc(complaintId);
      final doc = await rootRef.get();
      if (!doc.exists) throw Exception('Complaint not found');
      final uniId = doc.data()?['uniId'] ?? '';

      final batch = _firestore.batch();
      batch.update(rootRef, {
        'status': newStatus.name,
        'updatedAt': FieldValue.serverTimestamp()
      });
      if (uniId != '') {
        final uniRef = _firestore
            .collection('universities')
            .doc(uniId)
            .collection('complaints')
            .doc(complaintId);
        batch.update(uniRef, {
          'status': newStatus.name,
          'updatedAt': FieldValue.serverTimestamp()
        });
      }
      await batch.commit();
      // Notify the student of the status update
      try {
        final studentId = doc.data()?['studentId'] as String? ?? '';
        if (studentId.isNotEmpty) {
          await NotificationService().notifyComplaintStatus(
            userId: studentId,
            universityId: uniId,
            isResolved: newStatus == ComplaintStatus.resolved,
            complaintTitle: doc.data()?['title'] ?? 'Complaint',
            complaintId: complaintId,
          );
        }
      } catch (e) {
        debugPrint('Failed to notify complaint status change: $e');
      }
    } catch (e) {
      throw Exception('Failed to update status: $e');
    }
  }

  // Add admin reply
  Future<void> addAdminReply({
    required String complaintId,
    required String reply,
  }) async {
    try {
      final rootRef = _firestore.collection(_collectionName).doc(complaintId);
      final doc = await rootRef.get();
      if (!doc.exists) throw Exception('Complaint not found');
      final uniId = doc.data()?['uniId'] ?? '';

      final batch = _firestore.batch();
      batch.update(rootRef,
          {'adminReply': reply, 'updatedAt': FieldValue.serverTimestamp()});
      if (uniId != '') {
        final uniRef = _firestore
            .collection('universities')
            .doc(uniId)
            .collection('complaints')
            .doc(complaintId);
        batch.update(uniRef,
            {'adminReply': reply, 'updatedAt': FieldValue.serverTimestamp()});
      }
      await batch.commit();
      // Notify student of admin reply (use current status to determine resolved)
      try {
        final docAfter = await rootRef.get();
        final studentId = docAfter.data()?['studentId'] as String? ?? '';
        final isResolved = (docAfter.data()?['status'] as String?) == ComplaintStatus.resolved.name;
        if (studentId.isNotEmpty) {
          await NotificationService().notifyComplaintStatus(
            userId: studentId,
            universityId: uniId,
            isResolved: isResolved,
            complaintTitle: docAfter.data()?['title'] ?? 'Complaint',
            complaintId: complaintId,
          );
        }
      } catch (e) {
        debugPrint('Failed to notify complaint status change: $e');
      }
    } catch (e) {
      throw Exception('Failed to add reply: $e');
    }
  }

  // Update status and add reply together
  Future<void> updateComplaintWithReply({
    required String complaintId,
    required ComplaintStatus newStatus,
    required String reply,
  }) async {
    try {
      final rootRef = _firestore.collection(_collectionName).doc(complaintId);
      final doc = await rootRef.get();
      if (!doc.exists) throw Exception('Complaint not found');
      final uniId = doc.data()?['uniId'] ?? '';

      final batch = _firestore.batch();
      batch.update(rootRef, {
        'status': newStatus.name,
        'adminReply': reply,
        'updatedAt': FieldValue.serverTimestamp()
      });
      if (uniId != '') {
        final uniRef = _firestore
            .collection('universities')
            .doc(uniId)
            .collection('complaints')
            .doc(complaintId);
        batch.update(uniRef, {
          'status': newStatus.name,
          'adminReply': reply,
          'updatedAt': FieldValue.serverTimestamp()
        });
      }
      await batch.commit();
      // Notify student of status + reply
      try {
        final docAfter = await rootRef.get();
        final studentId = docAfter.data()?['studentId'] as String? ?? '';
        if (studentId.isNotEmpty) {
          await NotificationService().notifyComplaintStatus(
            userId: studentId,
            universityId: uniId,
            isResolved: newStatus == ComplaintStatus.resolved,
            complaintTitle: docAfter.data()?['title'] ?? 'Complaint',
            complaintId: complaintId,
          );
        }
      } catch (e) {
        debugPrint('Failed to notify complaint update with reply: $e');
      }
    } catch (e) {
      throw Exception('Failed to update complaint: $e');
    }
  }

  // Get complaint statistics for student
  Future<Map<String, int>> getStudentStatistics() async {
    final user = _auth.currentUser;
    if (user == null) return {'pending': 0, 'inProgress': 0, 'resolved': 0};

    try {
      final snapshot = await _firestore
          .collection(_collectionName)
          .where('studentId', isEqualTo: user.uid)
          .get();

      int pending = 0;
      int inProgress = 0;
      int resolved = 0;

      for (var doc in snapshot.docs) {
        final complaint = ComplaintModel.fromFirestore(doc);
        switch (complaint.status) {
          case ComplaintStatus.pending:
            pending++;
            break;
          case ComplaintStatus.inProgress:
            inProgress++;
            break;
          case ComplaintStatus.resolved:
            resolved++;
            break;
        }
      }

      return {
        'pending': pending,
        'inProgress': inProgress,
        'resolved': resolved,
      };
    } catch (e) {
      return {'pending': 0, 'inProgress': 0, 'resolved': 0};
    }
  }

  // Delete a complaint (optional, for students to remove their own)
  Future<void> deleteComplaint(String complaintId) async {
    try {
      final rootRef = _firestore.collection(_collectionName).doc(complaintId);
      final doc = await rootRef.get();
      if (!doc.exists) return;
      final uniId = doc.data()?['uniId'] ?? '';

      final batch = _firestore.batch();
      batch.delete(rootRef);
      if (uniId != '') {
        final uniRef = _firestore
            .collection('universities')
            .doc(uniId)
            .collection('complaints')
            .doc(complaintId);
        batch.delete(uniRef);
      }
      await batch.commit();
    } catch (e) {
      throw Exception('Failed to delete complaint: $e');
    }
  }
}
