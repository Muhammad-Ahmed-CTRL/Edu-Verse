// lib/complaints/controllers/complaint_controller.dart

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/complaint_model.dart';
import '../services/complaint_service.dart';

class ComplaintController extends GetxController {
  final ComplaintService _service = ComplaintService();

  final complaints = <ComplaintModel>[].obs;
  final isLoading = false.obs;
  final statistics = <String, int>{}.obs;
  StreamSubscription<List<ComplaintModel>>? _studentSub;

  // Form controllers
  final titleController = TextEditingController();
  final descriptionController = TextEditingController();
  final selectedCategory = Rx<ComplaintCategory?>(null);
  final selectedUrgency = ComplaintUrgency.low.obs;
  final isAnonymous = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadStudentComplaints();
    loadStatistics();
  }

  @override
  void onClose() {
    titleController.dispose();
    descriptionController.dispose();
    _studentSub?.cancel();
    super.onClose();
  }

  void loadStudentComplaints() {
    isLoading.value = true;

    // Cancel any existing subscription to avoid duplicates on reload/login
    _studentSub?.cancel();

    _studentSub = _service.getStudentComplaints().listen(
      (data) {
        complaints.value = data;
        isLoading.value = false;
      },
      onError: (error) async {
        isLoading.value = false;
        print('ComplaintController: error loading student complaints: $error');

        String message = 'Failed to load complaints';
        if (error is FirebaseException) {
          message = '${message}: ${error.message}';
          final msg = error.message ?? '';
          final urlMatch =
              RegExp(r'(https?:\/\/\S*indexes?\S*)').firstMatch(msg);
          if (urlMatch != null) {
            final url = urlMatch.group(0)!;
            // Offer to open index creation page for developers/admins.
            Get.defaultDialog(
              title: 'Index Required',
              middleText:
                  'A Firestore composite index may be required for your complaints query. Open the console to create it?',
              textConfirm: 'Open Index',
              onConfirm: () async {
                Get.back();
                try {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    Get.snackbar('Error', 'Cannot open browser for index link',
                        snackPosition: SnackPosition.BOTTOM);
                  }
                } catch (e) {
                  Get.snackbar('Error', 'Failed to open index link: $e',
                      snackPosition: SnackPosition.BOTTOM);
                }
              },
              textCancel: 'Cancel',
            );
          }
        } else if (error != null) {
          message = '${message}: $error';
        }

        Get.snackbar(
          'Error',
          message,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade100,
          colorText: Colors.red.shade900,
        );

        // Try a lightweight fallback fetch that avoids composite index need.
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final fallback = await _service.getStudentComplaintsFallback(
              studentId: user.uid, limit: 20);
          if (fallback.isNotEmpty) {
            print(
                'ComplaintController: fallback returned ${fallback.length} complaints');
            complaints.value = fallback;
            Get.snackbar(
                'Notice', 'Showing recent complaints while index builds',
                snackPosition: SnackPosition.BOTTOM);
          }
        }
      },
    );
  }

  Future<void> loadStatistics() async {
    final stats = await _service.getStudentStatistics();
    statistics.value = stats;
  }

  Future<void> submitComplaint({
    required String uniId,
    required String deptId,
  }) async {
    if (titleController.text.trim().isEmpty) {
      Get.snackbar(
        'Required',
        'Please enter a title',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange.shade100,
        colorText: Colors.orange.shade900,
      );
      return;
    }

    if (descriptionController.text.trim().isEmpty) {
      Get.snackbar(
        'Required',
        'Please enter a description',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange.shade100,
        colorText: Colors.orange.shade900,
      );
      return;
    }

    if (selectedCategory.value == null) {
      Get.snackbar(
        'Required',
        'Please select a category',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange.shade100,
        colorText: Colors.orange.shade900,
      );
      return;
    }

    try {
      // capture anonymity choice so we can inform the student after submit
      final bool wasAnonymous = isAnonymous.value;

      isLoading.value = true;

      await _service.submitComplaint(
        title: titleController.text.trim(),
        description: descriptionController.text.trim(),
        category: selectedCategory.value!,
        urgency: selectedUrgency.value,
        isAnonymous: isAnonymous.value,
        uniId: uniId,
        deptId: deptId,
      );

      // Clear form
      titleController.clear();
      descriptionController.clear();
      selectedCategory.value = null;
      selectedUrgency.value = ComplaintUrgency.low;
      isAnonymous.value = false;

      isLoading.value = false;

      Get.back();
      Get.snackbar(
        'Success',
        'Complaint submitted successfully',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade100,
        colorText: Colors.green.shade900,
        icon: const Icon(Icons.check_circle, color: Colors.green),
      );

      await loadStatistics();

      // If the student submitted anonymously, show a brief confirmation
      // dialog clarifying that admins will see the complaint as anonymous
      // but the student can still track progress in their view.
      if (wasAnonymous) {
        // small delay to ensure previous navigation/dialogs settled
        await Future.delayed(const Duration(milliseconds: 150));
        Get.defaultDialog(
          title: 'Submitted Anonymously',
          middleText:
              'Your report was submitted anonymously to admins. Only you can track its progress in My Reports.',
          textConfirm: 'OK',
          onConfirm: () => Get.back(),
        );
      }
    } catch (e) {
      isLoading.value = false;
      Get.snackbar(
        'Error',
        'Failed to submit complaint: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade100,
        colorText: Colors.red.shade900,
      );
    }
  }

  void selectCategory(ComplaintCategory category) {
    selectedCategory.value = category;
  }

  void selectUrgency(ComplaintUrgency urgency) {
    selectedUrgency.value = urgency;
  }

  void toggleAnonymous(bool value) {
    isAnonymous.value = value;
  }

  Future<void> deleteComplaint(String complaintId) async {
    try {
      isLoading.value = true;
      await _service.deleteComplaint(complaintId);
      isLoading.value = false;
      Get.snackbar(
        'Deleted',
        'Complaint removed',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green.shade100,
        colorText: Colors.green.shade900,
      );
      loadStudentComplaints();
      await loadStatistics();
    } catch (e) {
      isLoading.value = false;
      Get.snackbar(
        'Error',
        'Failed to delete complaint: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade100,
        colorText: Colors.red.shade900,
      );
    }
  }
}
