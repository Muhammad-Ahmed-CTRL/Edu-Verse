import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img_lib;

import 'announcement_service.dart';
import 'announcement_model.dart';
import 'announcement_widgets.dart';

class AdminAnnouncementView extends StatelessWidget {
  final String uniId;
  final String adminName;

  const AdminAnnouncementView({super.key, required this.uniId, required this.adminName});

  @override
  Widget build(BuildContext context) {
    final service = AnnouncementService();

    return Scaffold(
      backgroundColor: AppTheme.kBackgroundColor,
      appBar: AppBar(
        title: const Text("Manage Announcements"),
        backgroundColor: AppTheme.kWhiteColor,
        foregroundColor: AppTheme.kDarkTextColor,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(context, null, service),
        backgroundColor: AppTheme.kPrimaryColor,
        icon: const Icon(Icons.add),
        label: const Text("Create"),
      ),
      body: StreamBuilder<List<Announcement>>(
        stream: service.getAnnouncementsStream(uniId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final err = snapshot.error;
            // Attempt to extract any Firestore index creation URL and print it to console
            try {
              final msg = err.toString();
              final urlMatch = RegExp(r'https?://[^\s)]+create_composite[^\s)]+').firstMatch(msg);
              if (urlMatch != null) {
                final url = urlMatch.group(0);
                debugPrint('Firestore index creation URL: $url');
              } else {
                // fallback: any https URL
                final anyUrl = RegExp(r'https?://[^\s)]+').firstMatch(msg)?.group(0);
                if (anyUrl != null) debugPrint('Firestore URL: $anyUrl');
              }
            } catch (_) {}

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text('Failed to load announcements', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(err.toString(), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: () => service.getAnnouncementsStream(uniId), child: const Text('Retry')),
                    const SizedBox(height: 8),
                    const Text('Tip: open the Firestore console link printed in the debug console to create the required index.'),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final list = snapshot.data!;
          if (list.isEmpty) return const Center(child: Text("No announcements posted."));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AnnouncementCard(
                  announcement: list[index],
                  isAdmin: true,
                  onTap: () {},
                  onDelete: () => _confirmDelete(context, list[index].id, service),
                  onEdit: () => _showEditor(context, list[index], service),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(child: Icon(Icons.image, color: Colors.grey)),
    );
  }

  void _showEditor(BuildContext context, Announcement? announcement, AnnouncementService service) {
    final titleCtrl = TextEditingController(text: announcement?.title);
    final contentCtrl = TextEditingController(text: announcement?.content);
    String? pickedBase64 = announcement?.imageBase64;

    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(announcement == null ? "New Announcement" : "Edit Announcement", 
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: "Title", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: contentCtrl, maxLines: 4, decoration: const InputDecoration(labelText: "Content", border: OutlineInputBorder())),
                const SizedBox(height: 12),
                // Image picker / preview (no URL field anymore)
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        final ImagePicker picker = ImagePicker();
                        final XFile? file = await picker.pickImage(source: ImageSource.gallery);
                        if (file != null) {
                          final bytes = await file.readAsBytes();

                          // Compress / resize using `image` package
                          try {
                            img_lib.Image? image = img_lib.decodeImage(bytes);
                            if (image != null) {
                              // limit max width to 1200 and maintain aspect ratio
                              final maxWidth = 1200;
                              if (image.width > maxWidth) {
                                image = img_lib.copyResize(image, width: maxWidth);
                              }
                              // encode as JPEG with quality 80
                              final jpg = img_lib.encodeJpg(image, quality: 80);
                              pickedBase64 = base64Encode(jpg);
                            } else {
                              // fallback: raw bytes
                              pickedBase64 = base64Encode(bytes);
                            }
                          } catch (e) {
                            // fallback to sending raw bytes if compression fails
                            pickedBase64 = base64Encode(bytes);
                          }
                        }
                      },
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Pick Image'),
                    ),
                    const SizedBox(width: 12),
                    if (pickedBase64 != null)
                      Flexible(child: SizedBox(height: 64, child: Image.memory(base64Decode(pickedBase64!))))
                    else
                      Flexible(child: SizedBox(height: 64, child: _buildPlaceholderImage())),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.kPrimaryColor,
                    minimumSize: const Size(double.infinity, 48)
                  ),
                  onPressed: () async {
                    if (titleCtrl.text.isEmpty || contentCtrl.text.isEmpty) {
                      Get.snackbar("Error", "Title and content required", backgroundColor: Colors.red.shade100);
                      return;
                    }
                    
                    Get.back(); // Close dialog
                    
                    if (announcement == null) {
                      await service.createAnnouncement(
                        title: titleCtrl.text,
                        content: contentCtrl.text,
                        imageBase64: pickedBase64,
                        uniId: uniId,
                        authorName: adminName,
                      );
                      Get.snackbar("Success", "Posted successfully!", backgroundColor: Colors.green.shade100);
                    } else {
                      await service.updateAnnouncement(
                        docId: announcement.id,
                        title: titleCtrl.text,
                        content: contentCtrl.text,
                        imageBase64: pickedBase64,
                      );
                      Get.snackbar("Success", "Updated successfully!", backgroundColor: Colors.green.shade100);
                    }
                  },
                  child: Text(announcement == null ? "Post" : "Update"),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, String docId, AnnouncementService service) {
    Get.defaultDialog(
      title: "Delete?",
      middleText: "This cannot be undone.",
      textConfirm: "Delete",
      textCancel: "Cancel",
      confirmTextColor: Colors.white,
      onConfirm: () {
        service.deleteAnnouncement(docId);
        Get.back();
      },
    );
  }
}