// lib/complaints/views/student_complaint_view.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../controllers/complaint_controller.dart';
import '../models/complaint_model.dart';
import 'create_complaint_screen.dart';

// --- IMPORT GLOBAL THEME ---
import '../../theme_colors.dart';

class StudentComplaintView extends StatelessWidget {
  StudentComplaintView({Key? key}) : super(key: key);

  final controller = Get.put(ComplaintController());

  @override
  Widget build(BuildContext context) {
    // Dynamic Theme Colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = getAppBackgroundColor(context);
    final appBarColor = isDark ? kDarkBackgroundColor : kWhiteColor;
    final fgColor = getAppTextColor(context);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: appBarColor,
        foregroundColor: fgColor,
        title: Text(
          'My Reports',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 22,
            color: fgColor,
          ),
        ),
        iconTheme: IconThemeData(color: fgColor),
      ),
      body: Column(
        children: [
          _buildStatisticsHeader(context),
          const SizedBox(height: 16),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value && controller.complaints.isEmpty) {
                return const Center(child: CircularProgressIndicator(color: kPrimaryColor));
              }

              if (controller.complaints.isEmpty) {
                return _buildEmptyState(context);
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: controller.complaints.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final complaint = controller.complaints[index];
                  return _buildComplaintCard(context, complaint);
                },
              );
            }),
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [kSecondaryColor, kPrimaryColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: kPrimaryColor.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => Get.to(() => const CreateComplaintScreen()),
          backgroundColor: Colors.transparent,
          elevation: 0,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('New Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildStatisticsHeader(BuildContext context) {
    return Obx(() {
      final stats = controller.statistics;
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [kSecondaryColor, kPrimaryColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: kPrimaryColor.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Complaint Summary',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Pending',
                  stats['pending'] ?? 0,
                  Icons.pending_outlined,
                  Colors.yellow.shade100,
                ),
                _buildStatItem(
                  'In Progress',
                  stats['inProgress'] ?? 0,
                  Icons.sync,
                  Colors.blue.shade100,
                ),
                _buildStatItem(
                  'Resolved',
                  stats['resolved'] ?? 0,
                  Icons.check_circle_outline,
                  Colors.green.shade100,
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _buildStatItem(String label, int count, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.black87, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildComplaintCard(BuildContext context, ComplaintModel complaint) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // ✅ FIX: Transparent Light Card in Dark Mode
    final cardColor = isDark ? Colors.white.withOpacity(0.1) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.grey[600];
    
    // For popup menu background (solid color needed for readability)
    final menuColor = isDark ? kDarkBackgroundColor : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          // Subtle shadow only in light mode, or very faint in dark mode
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.0 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
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
                          child: Text(
                            complaint.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusBadge(complaint.status),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, color: subTextColor),
                          color: menuColor, // Solid background for menu
                          onSelected: (v) async {
                            if (v == 'delete') {
                              final confirm = await Get.defaultDialog<bool>(
                                title: 'Confirm Delete',
                                titleStyle: TextStyle(color: isDark ? Colors.white : Colors.black),
                                middleText: 'Delete this complaint?',
                                middleTextStyle: TextStyle(color: subTextColor),
                                backgroundColor: menuColor,
                                textConfirm: 'Delete',
                                textCancel: 'Cancel',
                                confirmTextColor: Colors.white,
                                buttonColor: Colors.red,
                                onConfirm: () => Get.back(result: true),
                                onCancel: () => Get.back(result: false),
                              );
                              if (confirm == true) {
                                await controller.deleteComplaint(complaint.id);
                              }
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem<String>(
                              value: 'delete',
                              child: Text('Delete',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (complaint.isAnonymous) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.visibility_off,
                              size: 14, color: subTextColor),
                          const SizedBox(width: 6),
                          Text(
                            'Submitted anonymously',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: subTextColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _getCategoryIcon(complaint.category),
                          size: 16,
                          color: subTextColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          complaint.category.displayName,
                          style: TextStyle(
                            fontSize: 13,
                            color: subTextColor,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: subTextColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('MMM dd, yyyy')
                              .format(complaint.createdAt),
                          style: TextStyle(
                            fontSize: 13,
                            color: subTextColor,
                          ),
                        ),
                      ],
                    ),
                    if (complaint.adminReply != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.blue.withOpacity(0.15) : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.admin_panel_settings,
                              size: 18,
                              color: isDark ? Colors.blue.shade200 : Colors.blue.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                complaint.adminReply!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.blue.shade100 : Colors.blue.shade900,
                                ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(ComplaintStatus status) {
    Color bgColor;
    Color textColor;

    switch (status) {
      case ComplaintStatus.pending:
        bgColor = Colors.yellow.shade100;
        textColor = Colors.yellow.shade900;
        break;
      case ComplaintStatus.inProgress:
        bgColor = Colors.blue.shade100;
        textColor = Colors.blue.shade900;
        break;
      case ComplaintStatus.resolved:
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade900;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.displayName,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.grey[700];
    final subTextColor = isDark ? Colors.white70 : Colors.grey[500];
    final iconBg = isDark ? Colors.white10 : Colors.grey[200];

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.assignment_turned_in,
              size: 80,
              color: Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No complaints yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the button below to submit your first report',
            style: TextStyle(
              fontSize: 14,
              color: subTextColor,
            ),
            textAlign: TextAlign.center,
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
}