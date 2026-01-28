// lib/complaints/views/admin_complaint_list.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/admin_complaint_controller.dart';
import '../models/complaint_model.dart';

class AdminComplaintList extends StatelessWidget {
  final String? adminViewUniId;

  AdminComplaintList({Key? key, this.adminViewUniId}) : super(key: key);

  final controller = Get.put(AdminComplaintController());

  @override
  Widget build(BuildContext context) {
    // If admin supplies a uniId from the dashboard, ensure controller uses it
    if (adminViewUniId != null &&
        adminViewUniId!.isNotEmpty &&
        controller.selectedUniId.value != adminViewUniId) {
      controller.setSelectedUniversity(adminViewUniId!);
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          title: const Text(
            'Complaint Dashboard',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 22,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TabBar(
                onTap: (index) {
                  controller.changeFilter(ComplaintStatus.values[index]);
                },
                indicator: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey[600],
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(text: 'Pending'),
                  Tab(text: 'In Progress'),
                  Tab(text: 'Resolved'),
                ],
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            Obx(() {
              if (controller.isSuperAdmin.value) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Text('University:',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Obx(() {
                          final items = controller.universities;
                          return DropdownButtonFormField<String>(
                            value: controller.selectedUniId.value.isEmpty
                                ? ''
                                : controller.selectedUniId.value,
                            items: [
                              const DropdownMenuItem<String>(
                                  value: '', child: Text('All Universities')),
                              ...items
                                  .map((m) => DropdownMenuItem<String>(
                                      value: m['id'] ?? '',
                                      child: Text(m['name'] ?? m['id'] ?? '')))
                                  .toList(),
                            ],
                            onChanged: (v) {
                              controller.setSelectedUniversity(v ?? '');
                            },
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            }),
            Expanded(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildComplaintList(),
                  _buildComplaintList(),
                  _buildComplaintList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComplaintList() {
    return Obx(() {
      if (controller.isLoading.value && controller.complaints.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }

      if (controller.complaints.isEmpty) {
        return _buildEmptyState();
      }

      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: controller.complaints.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final complaint = controller.complaints[index];
          return _buildComplaintCard(complaint);
        },
      );
    });
  }

  Widget _buildComplaintCard(ComplaintModel complaint) {
    return GestureDetector(
      onTap: () => controller.openActionSheet(complaint),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Colored urgency strip
              Container(
                width: 6,
                decoration: BoxDecoration(
                  color: _getUrgencyColor(complaint.urgency),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  complaint.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Obx(() {
                                  final profile = controller
                                      .studentProfiles[complaint.studentId];
                                  final studentName =
                                      profile?['name'] ?? complaint.studentName;
                                  final uniName =
                                      controller.uniNames[complaint.uniId] ??
                                          complaint.uniName;
                                  return Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          studentName != null &&
                                                  studentName.isNotEmpty
                                              ? 'By: $studentName'
                                              : (complaint.isAnonymous
                                                  ? 'By: Anonymous'
                                                  : 'By: ${complaint.studentId}'),
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[700]),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      if (complaint.uniId.isNotEmpty)
                                        Flexible(
                                          child: Text(
                                            uniName != null &&
                                                    uniName.isNotEmpty
                                                ? 'University: $uniName'
                                                : 'University: ${complaint.uniId}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[700]),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  );
                                }),
                                const SizedBox(height: 6),
                                Obx(() {
                                  final profile = controller
                                      .studentProfiles[complaint.studentId];
                                  final deptName = profile?['deptName'] ??
                                      complaint.deptName;
                                  final sectionName = profile?['sectionName'] ??
                                      complaint.sectionName;
                                  final semester = profile?['semester'] ??
                                      complaint.semester;
                                  final shift =
                                      profile?['shift'] ?? complaint.shift;
                                  if ((deptName ?? '').isEmpty &&
                                      (sectionName ?? '').isEmpty &&
                                      (semester ?? '').isEmpty &&
                                      (shift ?? '').isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      if (deptName != null &&
                                          deptName.isNotEmpty)
                                        _smallInfoChip(
                                            Icons.business, deptName),
                                      if (sectionName != null &&
                                          sectionName.isNotEmpty)
                                        _smallInfoChip(
                                            Icons.group, sectionName),
                                      if (semester != null &&
                                          semester.isNotEmpty)
                                        _smallInfoChip(
                                            Icons.book, 'Sem $semester'),
                                      if (shift != null && shift.isNotEmpty)
                                        _smallInfoChip(Icons.wb_sunny, shift),
                                    ],
                                  );
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildUrgencyBadge(complaint.urgency),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        complaint.description,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            _getCategoryIcon(complaint.category),
                            size: 16,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            complaint.category.displayName,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(
                            Icons.access_time,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('MMM dd, yyyy')
                                .format(complaint.createdAt),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          const Spacer(),
                          if (complaint.isAnonymous)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.shield,
                                    size: 14,
                                    color: Colors.purple.shade700,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Anonymous',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.purple.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (complaint.adminReply != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.admin_panel_settings,
                                size: 18,
                                color: Colors.blue.shade700,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Reply: ${complaint.adminReply!}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.blue.shade900,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
              Padding(
                padding: const EdgeInsets.all(16),
                child: Icon(
                  Icons.chevron_right,
                  color: Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUrgencyBadge(ComplaintUrgency urgency) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _getUrgencyColor(urgency).withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        urgency.displayName,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _getUrgencyColor(urgency),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inbox,
              size: 80,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          Obx(() {
            String message;
            switch (controller.currentFilter.value) {
              case ComplaintStatus.pending:
                message = 'No pending complaints';
                break;
              case ComplaintStatus.inProgress:
                message = 'No complaints in progress';
                break;
              case ComplaintStatus.resolved:
                message = 'No resolved complaints';
                break;
            }
            return Text(
              message,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            );
          }),
          const SizedBox(height: 8),
          Text(
            'New complaints will appear here',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Color _getUrgencyColor(ComplaintUrgency urgency) {
    switch (urgency) {
      case ComplaintUrgency.low:
        return Colors.green;
      case ComplaintUrgency.medium:
        return Colors.orange;
      case ComplaintUrgency.high:
        return Colors.red;
    }
  }

  IconData _getCategoryIcon(ComplaintCategory category) {
    switch (category) {
      case ComplaintCategory.academic:
        return Icons.school;
      case ComplaintCategory.infrastructure:
        return Icons.business;
      case ComplaintCategory.wifiTech:
        return Icons.wifi;
      case ComplaintCategory.harassment:
        return Icons.report_problem;
      case ComplaintCategory.other:
        return Icons.more_horiz;
    }
  }

  Widget _smallInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey[700]),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}
