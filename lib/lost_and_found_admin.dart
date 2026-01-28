import 'dart:async';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'lost_and_found.dart';

class LostAndFoundAdminList extends StatefulWidget {
  final String? adminViewUniId;
  const LostAndFoundAdminList({super.key, this.adminViewUniId});

  @override
  State<LostAndFoundAdminList> createState() => _LostAndFoundAdminListState();
}

class _LostAndFoundAdminListState extends State<LostAndFoundAdminList> {
  String? _resolvedUniId;
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _resolvedUniId = widget.adminViewUniId;
    if (_resolvedUniId == null || _resolvedUniId!.isEmpty) {
      _resolveCurrentUserUni();
    }
  }

  Future<void> _resolveCurrentUserUni() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!doc.exists) return;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return;
      setState(() {
        _resolvedUniId =
            (data['adminScope'] is Map && data['adminScope']['uniId'] != null)
                ? data['adminScope']['uniId'] as String
                : (data['uniId'] as String?);
      });
    } catch (e) {
      debugPrint('Failed to resolve user uniId: $e');
    }
  }

  Stream<QuerySnapshot> _postsStream() {
    final firestore = FirebaseFirestore.instance;

    if (_resolvedUniId == null || _resolvedUniId!.isEmpty) {
      return firestore
          .collection('posts')
          .orderBy('datePublished', descending: true)
          .snapshots()
          .handleError((e, st) => debugPrint('Posts stream error: $e'),
              test: (_) => true);
    }

    final subCol = firestore
        .collection('universities')
        .doc(_resolvedUniId)
        .collection('lost_and_found')
        .orderBy('datePublished', descending: true);

    final fallback = firestore
        .collection('posts')
        .where('uniId', isEqualTo: _resolvedUniId)
        .orderBy('datePublished', descending: true);

    final controller = StreamController<QuerySnapshot>.broadcast();
    StreamSubscription? sub;

    void startFallback() {
      sub = fallback.snapshots().listen((event) {
        if (!controller.isClosed) controller.add(event);
      }, onError: (e, st) {
        debugPrint('Fallback posts stream error: $e');
      });
    }

    controller.onListen = () {
      try {
        sub = subCol.snapshots().listen((event) {
          if (!controller.isClosed) controller.add(event);
        }, onError: (e, st) {
          debugPrint('Subcollection stream error, switching to fallback: $e');
          sub?.cancel();
          startFallback();
        });
      } catch (e) {
        debugPrint('Error starting subcollection stream: $e');
        startFallback();
      }
    };

    controller.onCancel = () async {
      await sub?.cancel();
      if (!controller.isClosed) await controller.close();
    };

    return controller.stream;
  }

  @override
  Widget build(BuildContext context) {
    final stream = _postsStream();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: StreamBuilder<QuerySnapshot>(
        stream: stream,
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
                      'Failed to load posts: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.red[700]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () async {
                      setState(() {
                        _resolvedUniId = widget.adminViewUniId;
                      });
                      if (_resolvedUniId == null || _resolvedUniId!.isEmpty) {
                        await _resolveCurrentUserUni();
                      }
                    },
                    child: const Text('Retry'),
                  )
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
                child: Text('No posts',
                    style: TextStyle(color: Colors.grey[600])));
          }

          final docs = snapshot.data!.docs;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>? ?? {};
              final title = data['title'] ?? 'No title';
              final uid = data['uid'] ?? '';
              final uniId = data['uniId'] ?? '';

              return Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text(title),
                  subtitle:
                      Text('Uni: ${uniId.toString()} • By: ${uid.toString()}'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'delete') {
                        final confirmed = await Get.dialog<bool>(AlertDialog(
                          title: const Text('Delete Post'),
                          content: const Text(
                              'Are you sure you want to delete this post?'),
                          actions: [
                            TextButton(
                                onPressed: () => Get.back(result: false),
                                child: const Text('Cancel')),
                            ElevatedButton(
                                onPressed: () => Get.back(result: true),
                                child: const Text('Delete')),
                          ],
                        ));
                        if (confirmed == true) {
                          try {
                            await FirestoreMethods().deletePost(doc.id);
                            Get.snackbar('Success', 'Post deleted',
                                snackPosition: SnackPosition.BOTTOM);
                          } catch (e) {
                            Get.snackbar('Error', 'Failed to delete: $e',
                                snackPosition: SnackPosition.BOTTOM);
                          }
                        }
                      } else if (v == 'view') {
                        Get.to(() => PostDetailView(snap: doc));
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'view', child: Text('View')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
