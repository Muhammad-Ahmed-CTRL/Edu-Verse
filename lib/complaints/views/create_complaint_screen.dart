// lib/complaints/views/create_complaint_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/complaint_controller.dart';
import '../models/complaint_model.dart';
import '../../auth.dart';

class CreateComplaintScreen extends StatefulWidget {
  const CreateComplaintScreen({Key? key}) : super(key: key);

  @override
  State<CreateComplaintScreen> createState() => _CreateComplaintScreenState();
}

class _CreateComplaintScreenState extends State<CreateComplaintScreen> {
  final controller = Get.find<ComplaintController>();
  String uniId = '';
  String deptId = '';
  bool loadingProfile = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        loadingProfile = false;
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data();
        setState(() {
          uniId = data?['uniId'] ?? '';
          deptId = data?['departmentId'] ?? '';
          loadingProfile = false;
        });
      } else {
        setState(() => loadingProfile = false);
      }
    } catch (e) {
      setState(() => loadingProfile = false);
      Get.snackbar('Error', 'Failed to load profile: $e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Complaint'),
        backgroundColor: const Color(0xFF667EEA),
      ),
      body: loadingProfile
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller.titleController,
                      decoration: InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller.descriptionController,
                      maxLines: 6,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Category', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ComplaintCategory.values.map((c) {
                        final isSelected = controller.selectedCategory.value == c;
                        return ChoiceChip(
                          label: Text(c.displayName),
                          selected: isSelected,
                          onSelected: (_) => controller.selectCategory(c),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    const Text('Urgency', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Obx(() => Wrap(
                          spacing: 8,
                          children: ComplaintUrgency.values.map((u) {
                            final isSelected = controller.selectedUrgency.value == u;
                            return ChoiceChip(
                              label: Text(u.displayName),
                              selected: isSelected,
                              onSelected: (s) => controller.selectUrgency(u),
                            );
                          }).toList(),
                        )),
                    const SizedBox(height: 12),
                    Obx(() => SwitchListTile(
                          title: const Text('Submit Anonymously'),
                          value: controller.isAnonymous.value,
                          onChanged: controller.toggleAnonymous,
                        )),
                    const SizedBox(height: 20),
                    Obx(() => SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: controller.isLoading.value
                                ? null
                                : () {
                                    if (uniId.isEmpty || deptId.isEmpty) {
                                      Get.snackbar(
                                        'Missing Profile',
                                        'University or department not set in your profile. Please update your profile and try again.',
                                        snackPosition: SnackPosition.BOTTOM,
                                        backgroundColor: Colors.orange.shade100,
                                      );
                                      return;
                                    }
                                    controller.submitComplaint(uniId: uniId, deptId: deptId);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF667EEA),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: controller.isLoading.value
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text('Submit Complaint'),
                          ),
                        )),
                  ],
                ),
              ),
            ),
    );
  }
}
