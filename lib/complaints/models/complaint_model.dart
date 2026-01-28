// lib/complaints/models/complaint_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

enum ComplaintCategory {
  academic,
  infrastructure,
  wifiTech,
  harassment,
  other;

  String get displayName {
    switch (this) {
      case ComplaintCategory.academic:
        return 'Academic';
      case ComplaintCategory.infrastructure:
        return 'Infrastructure';
      case ComplaintCategory.wifiTech:
        return 'WiFi/Tech';
      case ComplaintCategory.harassment:
        return 'Harassment';
      case ComplaintCategory.other:
        return 'Other';
    }
  }
}

enum ComplaintUrgency {
  low,
  medium,
  high;

  String get displayName {
    switch (this) {
      case ComplaintUrgency.low:
        return 'Low';
      case ComplaintUrgency.medium:
        return 'Medium';
      case ComplaintUrgency.high:
        return 'High';
    }
  }
}

enum ComplaintStatus {
  pending,
  inProgress,
  resolved;

  String get displayName {
    switch (this) {
      case ComplaintStatus.pending:
        return 'Pending';
      case ComplaintStatus.inProgress:
        return 'In Progress';
      case ComplaintStatus.resolved:
        return 'Resolved';
    }
  }
}

class ComplaintModel {
  final String id;
  final String title;
  final String description;
  final ComplaintCategory category;
  final ComplaintUrgency urgency;
  final ComplaintStatus status;
  final bool isAnonymous;
  final String studentId;
  final String uniId;
  final String deptId;
  final DateTime createdAt;
  final String? adminReply;
  final DateTime? updatedAt;
  final String? studentName;
  final String? uniName;
  final String? deptName;
  final String? sectionId;
  final String? sectionName;
  final String? semester;
  final String? shift;

  ComplaintModel({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.urgency,
    required this.status,
    required this.isAnonymous,
    required this.studentId,
    required this.uniId,
    required this.deptId,
    required this.createdAt,
    this.adminReply,
    this.updatedAt,
    this.studentName,
    this.uniName,
    this.deptName,
    this.sectionId,
    this.sectionName,
    this.semester,
    this.shift,
  });

  factory ComplaintModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ComplaintModel(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      category: ComplaintCategory.values.firstWhere(
        (e) => e.name == data['category'],
        orElse: () => ComplaintCategory.other,
      ),
      urgency: ComplaintUrgency.values.firstWhere(
        (e) => e.name == data['urgency'],
        orElse: () => ComplaintUrgency.low,
      ),
      status: ComplaintStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => ComplaintStatus.pending,
      ),
      isAnonymous: data['isAnonymous'] ?? false,
      studentId: data['studentId'] ?? '',
      uniId: data['uniId'] ?? '',
      deptId: data['deptId'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      adminReply: data['adminReply'],
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      studentName: data['studentName'] ?? data['studentDisplayName'] ?? null,
      uniName: data['uniName'] ?? null,
      deptName: data['deptName'] ?? null,
      sectionId: data['sectionId'] ?? null,
      sectionName: data['sectionName'] ?? null,
      semester: data['semester'] ?? null,
      shift: data['shift'] ?? null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'description': description,
      'category': category.name,
      'urgency': urgency.name,
      'status': status.name,
      'isAnonymous': isAnonymous,
      'studentId': studentId,
      'uniId': uniId,
      'deptId': deptId,
      'createdAt': Timestamp.fromDate(createdAt),
      'adminReply': adminReply,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      if (studentName != null) 'studentName': studentName,
      if (uniName != null) 'uniName': uniName,
      if (deptName != null) 'deptName': deptName,
      if (sectionId != null) 'sectionId': sectionId,
      if (sectionName != null) 'sectionName': sectionName,
      if (semester != null) 'semester': semester,
      if (shift != null) 'shift': shift,
    };
  }

  ComplaintModel copyWith({
    String? id,
    String? title,
    String? description,
    ComplaintCategory? category,
    ComplaintUrgency? urgency,
    ComplaintStatus? status,
    bool? isAnonymous,
    String? studentId,
    String? uniId,
    String? deptId,
    DateTime? createdAt,
    String? adminReply,
    DateTime? updatedAt,
    String? studentName,
    String? uniName,
    String? deptName,
    String? sectionId,
    String? sectionName,
    String? semester,
    String? shift,
  }) {
    return ComplaintModel(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      urgency: urgency ?? this.urgency,
      status: status ?? this.status,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      studentId: studentId ?? this.studentId,
      uniId: uniId ?? this.uniId,
      deptId: deptId ?? this.deptId,
      createdAt: createdAt ?? this.createdAt,
      adminReply: adminReply ?? this.adminReply,
      updatedAt: updatedAt ?? this.updatedAt,
      studentName: studentName ?? this.studentName,
      uniName: uniName ?? this.uniName,
      deptName: deptName ?? this.deptName,
      sectionId: sectionId ?? this.sectionId,
      sectionName: sectionName ?? this.sectionName,
      semester: semester ?? this.semester,
      shift: shift ?? this.shift,
    );
  }
}
