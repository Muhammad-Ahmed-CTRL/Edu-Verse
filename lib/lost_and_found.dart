import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:get/get.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
// Ensure you have these files in your project, or remove imports if unused
// shared.dart removed from this file to avoid unused-import issues
import 'auth.dart';
import 'notifications.dart';
import 'theme_colors.dart';

// ==========================================
// PHONE VALIDATION HELPER
// ==========================================

class PhoneValidator {
  static bool isValidPhone(String phone) {
    final phoneRegex = RegExp(r'^(\+92|0)[0-9]{10}$');
    return phoneRegex.hasMatch(phone.replaceAll(' ', '').replaceAll('-', ''));
  }

  static String formatPhone(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('0')) {
      return '+92' + cleaned.substring(1);
    }
    return cleaned;
  }
}

// Sanitize phone for WhatsApp / tel URIs.
// Returns digits-only international number (no +) suitable for wa.me links.
String sanitizePhoneForWhatsApp(String phone) {
  if (phone == null) return '';
  String p = phone.toString().trim();
  if (p.isEmpty) return '';
  // Strip all non-digit characters
  String digits = p.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  // If number starts with a local 0 (e.g., 0311...), convert to country code 92
  if (digits.startsWith('0')) {
    digits = '92' + digits.substring(1);
  }
  return digits;
}

// ==========================================
// HELPER WIDGET FOR IMAGE DISPLAY
// ==========================================

class SmartImageDisplay extends StatelessWidget {
  final String imageData;
  final double width;
  final double height;
  final BoxFit fit;

  const SmartImageDisplay({
    super.key,
    required this.imageData,
    this.width = double.infinity,
    this.height = 300,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (imageData.startsWith('/9j/') || imageData.startsWith('iVBOR')) {
      try {
        Uint8List bytes = base64Decode(imageData);
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bytes, width: width, height: height, fit: fit),
        );
      } catch (e) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.broken_image),
        );
      }
    } else {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: imageData,
          width: width,
          height: height,
          fit: fit,
          placeholder: (c, u) => Container(
            color: Colors.grey[300],
            width: width,
            height: height,
          ),
          errorWidget: (c, u, e) => Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.broken_image),
          ),
        ),
      );
    }
  }
}

// ==========================================
// MODELS & METHODS
// ==========================================

class Post {
  final String description,
      uid,
      postId,
      username,
      postUrl,
      title,
      category,
      postType,
      location,
      phone,
      uniId;
  final datePublished;

  Post({
    required this.uniId,
    required this.category,
    required this.postType,
    required this.location,
    required this.description,
    required this.uid,
    required this.postId,
    required this.username,
    required this.datePublished,
    required this.postUrl,
    required this.title,
    required this.phone,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'uid': uid,
        'postId': postId,
        'username': username,
        'datePublished': datePublished,
        'postUrl': postUrl,
        'title': title,
        'category': category,
        'postType': postType,
        'location': location,
        'phone': phone,
        'uniId': uniId,
      };
}

class FirestoreMethods {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> uploadPost(
    String description,
    Uint8List file,
    String uid,
    String username,
    String title,
    String category,
    String location,
    String postType,
    String phone,
    String uniId,
  ) async {
    try {
      String base64Image = base64Encode(file);
      String postId = const Uuid().v1();
      Post post = Post(
        description: description,
        uid: uid,
        username: username,
        postId: postId,
        datePublished: DateTime.now(),
        postUrl: base64Image,
        category: category,
        location: location,
        postType: postType,
        title: title,
        phone: phone,
        uniId: uniId,
      );

      // Write to root mirror collection for admin/global queries
      await _firestore.collection('posts').doc(postId).set(post.toJson());

      // Also write under the university-specific lost_and_found collection
      if (uniId.isNotEmpty) {
        await _firestore
            .collection('universities')
            .doc(uniId)
            .collection('lost_and_found')
            .doc(postId)
            .set(post.toJson());
      }
      return postId;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deletePost(String postId) async {
    // Delete from root posts and from the university subcollection if present.
    final rootRef = _firestore.collection('posts').doc(postId);
    final doc = await rootRef.get();
    String uniId = '';
    if (doc.exists) {
      final Map<String, dynamic>? _d = doc.data() as Map<String, dynamic>?;
      uniId = _d?['uniId'] ?? '';
    }

    final batch = _firestore.batch();
    batch.delete(rootRef);
    if (uniId.isNotEmpty) {
      final uniRef = _firestore
          .collection('universities')
          .doc(uniId)
          .collection('lost_and_found')
          .doc(postId);
      batch.delete(uniRef);
    }
    await batch.commit();
  }

  Future<String> updatePost(
    String postId,
    String title,
    String description,
    String location,
    String category,
    String phone,
  ) async {
    try {
      final rootRef = _firestore.collection('posts').doc(postId);
      final doc = await rootRef.get();
      String uniId = '';
      if (doc.exists) {
        final Map<String, dynamic>? _d = doc.data() as Map<String, dynamic>?;
        uniId = _d?['uniId'] ?? '';
      }

      final batch = _firestore.batch();
      batch.update(rootRef, {
        'title': title,
        'description': description,
        'location': location,
        'category': category,
        'phone': phone,
      });
      if (uniId.isNotEmpty) {
        final uniRef = _firestore
            .collection('universities')
            .doc(uniId)
            .collection('lost_and_found')
            .doc(postId);
        batch.update(uniRef, {
          'title': title,
          'description': description,
          'location': location,
          'category': category,
          'phone': phone,
        });
      }
      await batch.commit();
      return "Success";
    } catch (e) {
      return e.toString();
    }
  }
}

// ==========================================
// LANDING PAGE
// ==========================================

class LostAndFoundLandingPage extends StatefulWidget {
  const LostAndFoundLandingPage({super.key});
  @override
  State<LostAndFoundLandingPage> createState() =>
      _LostAndFoundLandingPageState();
}

class _LostAndFoundLandingPageState extends State<LostAndFoundLandingPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String name = "User";

  @override
  void initState() {
    super.initState();
    AuthService().getName().then((val) {
      if (val.isNotEmpty) setState(() => name = val);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _timeAgo(DateTime date) {
    final d = DateTime.now().difference(date);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    var user = AuthService().currentUser;
    // Use theme colors
    final backgroundColor = getAppBackgroundColor(context);
    final cardColor = getAppCardColor(context);
    final textColor = getAppTextColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: kPrimaryColor, // Header background
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Get.back(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.school,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Eduverse',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Lost & Found',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Get.to(() => const ProfileView()),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundImage: NetworkImage(
                        user?.photoURL ?? "https://via.placeholder.com/150",
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content area
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      // Search and Filters
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: TextField(
                                  controller: _searchCtrl,
                                  style: TextStyle(color: textColor),
                                  decoration: InputDecoration(
                                    hintText: 'Search',
                                    hintStyle:
                                        TextStyle(color: Colors.grey[400]),
                                    prefixIcon: Icon(Icons.search,
                                        color: Colors.grey[400]),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
                                  onSubmitted: (query) {
                                    if (query.isNotEmpty) {
                                      Get.to(() =>
                                          PostsListView(initialSearch: query));
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => Get.to(() => const PostsListView()),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      'Filters',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.tune,
                                        size: 18, color: textColor),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Action Cards
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    Get.to(() => const CreatePostView()),
                                child: Container(
                                  height: 160,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFB8C5FF),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 56,
                                        height: 56,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.4),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.add_circle_outline,
                                          color: Color(0xFF2D1B69),
                                          size: 32,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Report Lost or\nFound Item',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Color(0xFF2D1B69),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          height: 1.3,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Post an advert for an item.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: const Color(0xFF2D1B69)
                                              .withOpacity(0.7),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    Get.to(() => const PostsListView()),
                                child: Container(
                                  height: 160,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF4CC),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 56,
                                        height: 56,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.4),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.list_alt,
                                          color: Color(0xFF8B6914),
                                          size: 28,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Browse All Items',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Color(0xFF8B6914),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          height: 1.3,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Search for lost\nbelongings.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: const Color(0xFF8B6914)
                                              .withOpacity(0.7),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Recently Reported Items
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Recently Reported Items',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Get.to(() => const PostsListView()),
                              child: const Text(
                                'See All',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: kPrimaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Recent items horizontal list
                      SizedBox(
                        height: 200,
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('posts')
                              .orderBy('datePublished', descending: true)
                              .limit(10)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            if (!snapshot.hasData ||
                                snapshot.data!.docs.isEmpty) {
                              return Center(
                                child: Text('No items yet',
                                    style: TextStyle(color: textColor)),
                              );
                            }

                            final docs = snapshot.data!.docs;
                            return ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: docs.length,
                              itemBuilder: (context, index) {
                                final doc = docs[index];
                                final data = doc.data() as Map<String, dynamic>;

                                DateTime date;
                                final ts = data['datePublished'];
                                if (ts is Timestamp) {
                                  date = ts.toDate();
                                } else if (ts is DateTime) {
                                  date = ts;
                                } else {
                                  date = DateTime.tryParse(ts.toString()) ??
                                      DateTime.now();
                                }

                                final postType = data['postType'] ?? 'Found';
                                final isLost = postType == 'Lost';

                                return GestureDetector(
                                  onTap: () =>
                                      Get.to(() => PostDetailView(snap: doc)),
                                  child: Container(
                                    width: 140,
                                    margin: const EdgeInsets.only(right: 16),
                                    decoration: BoxDecoration(
                                      color: cardColor,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.06),
                                          blurRadius: 10,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              const BorderRadius.vertical(
                                            top: Radius.circular(16),
                                          ),
                                          child: SmartImageDisplay(
                                            imageData: data['postUrl'] ?? '',
                                            width: 140,
                                            height: 110,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                data['title'] ?? 'No title',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: textColor,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                postType,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: isLost
                                                      ? const Color(0xFFE53935)
                                                      : const Color(0xFF43A047),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _timeAgo(date),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// POSTS LIST VIEW WITH FILTERS
// ==========================================

class PostsListView extends StatefulWidget {
  final String? initialSearch;
  const PostsListView({super.key, this.initialSearch});

  @override
  State<PostsListView> createState() => _PostsListViewState();
}

class _PostsListViewState extends State<PostsListView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String uniId = '';
  String currentUserUid = '';
  String currentUserRole = 'student';
  String selectedCategory = 'All';
  String selectedType = 'All';
  bool sortByEarliest = false;
  bool showFilters = false;

  List<String> categories() =>
      ['All', 'Gadgets', 'Books', 'Id-Card', 'Bottle', 'Other'];
  List<String> types() => ['All', 'Found', 'Lost'];

  @override
  void initState() {
    super.initState();
    if (widget.initialSearch != null) {
      _searchCtrl.text = widget.initialSearch!;
    }
    // load current user's university id for scoping posts
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = AuthService().currentUser;
      if (user != null) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          final Map<String, dynamic>? _d = doc.data() as Map<String, dynamic>?;
          setState(() {
            uniId = _d?['uniId'] ?? '';
            currentUserUid = user.uid;
            currentUserRole = _d?['role'] ?? 'student';
          });
        } catch (e) {
          // ignore
        }
      }
    });
  }

  String _timeAgo(DateTime date) {
    final d = DateTime.now().difference(date);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  bool _matchesSearch(Map<String, dynamic> data, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    final fields = [
      (data['title'] ?? '').toString(),
      (data['description'] ?? '').toString(),
      (data['location'] ?? '').toString(),
      (data['username'] ?? '').toString(),
    ];
    return fields.any((f) => f.toLowerCase().contains(q));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = getAppBackgroundColor(context);
    final cardColor = getAppCardColor(context);
    final textColor = getAppTextColor(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: kPrimaryColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Get.back(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Lost & Found',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Get.to(() => const ProfileView()),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundImage: NetworkImage(
                        AuthService().currentUser?.photoURL ??
                            "https://via.placeholder.com/150",
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content area
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // Search and Filters
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _searchCtrl,
                                style: TextStyle(color: textColor),
                                decoration: InputDecoration(
                                  hintText: 'Search',
                                  hintStyle: TextStyle(color: Colors.grey[400]),
                                  prefixIcon: Icon(Icons.search,
                                      color: Colors.grey[400]),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () =>
                                setState(() => showFilters = !showFilters),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: showFilters
                                    ? kPrimaryColor
                                    : cardColor,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'Filters',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: showFilters
                                          ? Colors.white
                                          : textColor,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.tune,
                                    size: 18,
                                    color: showFilters
                                        ? Colors.white
                                        : textColor,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Filter chips
                    if (showFilters) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Category',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: categories().map((cat) {
                                  final isSelected = selectedCategory == cat;
                                  return GestureDetector(
                                    onTap: () =>
                                        setState(() => selectedCategory = cat),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? kPrimaryColor
                                            : (isDark ? Colors.grey[800] : const Color(0xFFF5F5F5)),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        cat,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: isSelected
                                              ? Colors.white
                                              : textColor,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Type',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: types().map((type) {
                                  final isSelected = selectedType == type;
                                  return GestureDetector(
                                    onTap: () =>
                                        setState(() => selectedType = type),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? kPrimaryColor
                                            : (isDark ? Colors.grey[800] : const Color(0xFFF5F5F5)),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        type,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: isSelected
                                              ? Colors.white
                                              : textColor,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // List
                    Expanded(
                      child: uniId.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('posts')
                                  .where('uniId', isEqualTo: uniId)
                                  .snapshots(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                if (!snapshot.hasData ||
                                    snapshot.data!.docs.isEmpty) {
                                  return const Center(
                                    child: Text('No items found',
                                        style: TextStyle(color: Colors.grey)),
                                  );
                                }

                                List<QueryDocumentSnapshot> docs =
                                    snapshot.data!.docs;
                                List<QueryDocumentSnapshot> filtered =
                                    docs.where((doc) {
                                  final data =
                                      doc.data() as Map<String, dynamic>;
                                  // Normalize category values for robust matching
                                  final docCategory = (data['category'] ?? '')
                                      .toString()
                                      .trim()
                                      .toLowerCase();
                                  final selCategory = selectedCategory
                                      .toString()
                                      .trim()
                                      .toLowerCase();
                                  if (selCategory != 'all' &&
                                      docCategory != selCategory) {
                                    return false;
                                  }
                                  if (selectedType != 'All' &&
                                      (data['postType'] ?? 'Found') !=
                                          selectedType) {
                                    return false;
                                  }
                                  if (!_matchesSearch(data, _searchCtrl.text)) {
                                    return false;
                                  }
                                  return true;
                                }).toList();

                                filtered.sort((a, b) {
                                  DateTime da, db;
                                  final A = a.data() as Map<String, dynamic>;
                                  final B = b.data() as Map<String, dynamic>;
                                  final ta = A['datePublished'];
                                  final tb = B['datePublished'];
                                  if (ta is Timestamp) {
                                    da = ta.toDate();
                                  } else if (ta is DateTime) {
                                    da = ta;
                                  } else {
                                    da = DateTime.tryParse(ta.toString()) ??
                                        DateTime.now();
                                  }
                                  if (tb is Timestamp) {
                                    db = tb.toDate();
                                  } else if (tb is DateTime) {
                                    db = tb;
                                  } else {
                                    db = DateTime.tryParse(tb.toString()) ??
                                        DateTime.now();
                                  }
                                  return sortByEarliest
                                      ? da.compareTo(db)
                                      : db.compareTo(da);
                                });

                                if (filtered.isEmpty) {
                                  return const Center(
                                    child: Text('No items match filters',
                                        style: TextStyle(color: Colors.grey)),
                                  );
                                }

                                return GridView.builder(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    childAspectRatio: 0.75,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                  ),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final doc = filtered[index];
                                    final Map<String, dynamic>? data =
                                        doc.data() as Map<String, dynamic>?;

                                    DateTime date;
                                    final ts = data?['datePublished'];
                                    if (ts is Timestamp) {
                                      date = ts.toDate();
                                    } else if (ts is DateTime) {
                                      date = ts;
                                    } else {
                                      date = DateTime.tryParse(ts.toString()) ??
                                          DateTime.now();
                                    }

                                    final postType =
                                        data?['postType'] ?? 'Found';
                                    final isLost = postType == 'Lost';

                                    return GestureDetector(
                                      onTap: () => Get.to(
                                          () => PostDetailView(snap: doc)),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: cardColor,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.06),
                                              blurRadius: 10,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                top: Radius.circular(16),
                                              ),
                                              child: SmartImageDisplay(
                                                imageData:
                                                    data?['postUrl'] ?? '',
                                                width: double.infinity,
                                                height: 140,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                            Expanded(
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      data?['title'] ??
                                                          'No title',
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: textColor,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      postType,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: isLost
                                                            ? const Color(
                                                                0xFFE53935)
                                                            : const Color(
                                                                0xFF43A047),
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    Text(
                                                      _timeAgo(date),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// CREATE POST VIEW
// ==========================================

class CreatePostView extends StatefulWidget {
  const CreatePostView({super.key});
  @override
  State<CreatePostView> createState() => _CreatePostViewState();
}

class _CreatePostViewState extends State<CreatePostView> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _location = TextEditingController();
  final _phone = TextEditingController();
  String postType = "Found";
  String category = "Gadgets";
  Uint8List? _file;
  bool isLoading = false;

  selectImage() async {
    final ImagePicker picker = ImagePicker();
    XFile? file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      var bytes = await file.readAsBytes();
      setState(() => _file = bytes);
    }
  }

  post() async {
    if (_file == null) {
      Get.snackbar("Error", "Please select an image",
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade100);
      return;
    }
    if (_phone.text.isEmpty) {
      Get.snackbar("Error", "Please enter your phone number",
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade100);
      return;
    }
    if (!PhoneValidator.isValidPhone(_phone.text)) {
      Get.snackbar(
          "Error", "Phone format invalid. Use +923295008120 or 03295008120",
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade100);
      return;
    }
    setState(() => isLoading = true);
    try {
      var user = AuthService().currentUser!;
      String name = await AuthService().getName();
      // fetch user's university id from users collection
      String uniId = '';
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final Map<String, dynamic>? _d = doc.data() as Map<String, dynamic>?;
        uniId = _d?['uniId'] ?? '';
      } catch (e) {
        uniId = '';
      }
      String formattedPhone = PhoneValidator.formatPhone(_phone.text);
      String res = await FirestoreMethods().uploadPost(
        _desc.text,
        _file!,
        user.uid,
        name,
        _title.text,
        category,
        _location.text,
        postType,
        formattedPhone,
        uniId,
      );
      setState(() => isLoading = false);
      // uploadPost now returns the created `postId` on success.
      Get.back();
      Get.snackbar("Success", "Post created",
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green.shade100);

      // Trigger a lost-and-found notification for this university.
      try {
        await NotificationService().notifyLostAndFound(
          universityId: uniId,
          itemName: _title.text,
          isLost: postType.toLowerCase().contains('lost'),
          postId: res,
        );
      } catch (e) {
        debugPrint('Failed to trigger lost&found notification: $e');
      }
    } catch (e) {
      setState(() => isLoading = false);
      Get.snackbar("Error", e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade100);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = getAppBackgroundColor(context);
    final cardColor = getAppCardColor(context);
    final textColor = getAppTextColor(context);

    return Scaffold(
      backgroundColor: kPrimaryColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Get.back(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Create Post',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            // Content
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: selectImage,
                              child: Container(
                                height: 200,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: _file == null
                                    ? Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.add_photo_alternate,
                                              size: 50,
                                              color: Colors.grey[400]),
                                          const SizedBox(height: 8),
                                          Text('Tap to add photo',
                                              style: TextStyle(
                                                  color: Colors.grey[600])),
                                        ],
                                      )
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Image.memory(_file!,
                                            fit: BoxFit.cover),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Type',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => postType = "Found"),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      decoration: BoxDecoration(
                                        color: postType == "Found"
                                            ? kPrimaryColor
                                            : cardColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: postType == "Found"
                                              ? kPrimaryColor
                                              : Colors.grey[300]!,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'Found',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: postType == "Found"
                                                ? Colors.white
                                                : textColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => postType = "Lost"),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      decoration: BoxDecoration(
                                        color: postType == "Lost"
                                            ? kPrimaryColor
                                            : cardColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: postType == "Lost"
                                              ? kPrimaryColor
                                              : Colors.grey[300]!,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          'Lost',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: postType == "Lost"
                                                ? Colors.white
                                                : textColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            _buildTextField(
                              'Category',
                              null,
                              enabled: true,
                              suffix: DropdownButton<String>(
                                value: category,
                                underline: const SizedBox(),
                                items: [
                                  'Gadgets',
                                  'Books',
                                  'Id-Card',
                                  'Bottle',
                                  'Other'
                                ]
                                    .map((e) => DropdownMenuItem(
                                        value: e, child: Text(e)))
                                    .toList(),
                                onChanged: (v) => setState(() => category = v!),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildTextField('Title', _title),
                            const SizedBox(height: 16),
                            _buildTextField('Description', _desc, maxLines: 3),
                            const SizedBox(height: 16),
                            _buildTextField('Location', _location),
                            const SizedBox(height: 16),
                            _buildTextField('Phone Number', _phone,
                                hint: '+923115428907 or 03115428907',
                                keyboardType: TextInputType.phone),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: post,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimaryColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Post Ad',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController? controller, {
    String? hint,
    int maxLines = 1,
    bool enabled = true,
    Widget? suffix,
    TextInputType? keyboardType,
  }) {
    final textColor = getAppTextColor(context);
    final cardColor = getAppCardColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: TextField(
            controller: controller,
            enabled: enabled,
            maxLines: maxLines,
            keyboardType: keyboardType,
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
              suffix: suffix,
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// POST DETAIL VIEW
// ==========================================

class PostDetailView extends StatefulWidget {
  final dynamic snap;
  const PostDetailView({super.key, required this.snap});

  @override
  State<PostDetailView> createState() => _PostDetailViewState();
}

class _PostDetailViewState extends State<PostDetailView> {
  String currentUserUid = '';
  String currentUserRole = 'student';
  String currentUserUni = '';

  @override
  void initState() {
    super.initState();
    final user = AuthService().currentUser;
    if (user != null) {
      currentUserUid = user.uid;
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .then((doc) {
        final Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
        setState(() {
          currentUserRole = data?['role'] ?? 'student';
          currentUserUni = data?['uniId'] ?? '';
        });
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = getAppBackgroundColor(context);
    final textColor = getAppTextColor(context);

    final dynamic snap = widget.snap;
    Map<String, dynamic>? data;
    String docId = '';
    if (snap is DocumentSnapshot) {
      data = snap.data() as Map<String, dynamic>?;
      docId = snap.id;
    } else if (snap is QueryDocumentSnapshot) {
      data = snap.data() as Map<String, dynamic>?;
      docId = snap.id;
    } else if (snap is Map<String, dynamic>) {
      data = snap as Map<String, dynamic>?;
    }

    var isOwner =
        currentUserUid.isNotEmpty && currentUserUid == (data?['uid'] ?? '');
    final postUni = (data?['uniId'] ?? '').toString();
    final canEditOrDelete = isOwner ||
        currentUserRole == 'super_admin' ||
        (currentUserRole == 'uni_admin' && postUni == currentUserUni);

    return Scaffold(
      backgroundColor: kPrimaryColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Get.back(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (canEditOrDelete)
                    PopupMenuButton(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          child: const Text("Edit"),
                          onTap: () => Future.delayed(
                            Duration.zero,
                            () => Get.to(() => EditPostView(snap: snap)),
                          ),
                        ),
                        PopupMenuItem(
                          child: const Text("Delete"),
                          onTap: () => Future.delayed(
                            Duration.zero,
                            () => _showDeleteConfirmation(context),
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox(width: 36),
                ],
              ),
            ),
            // Content
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SmartImageDisplay(
                        imageData: data?['postUrl'] ?? '',
                        height: 300,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data?['title'] ?? '',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Posted by: ${data?['username'] ?? ''}",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: snap['postType'] == 'Lost'
                                    ? Colors.red.shade50
                                    : Colors.green.shade50,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                snap['postType'] ?? 'Found',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      (data?['postType'] ?? 'Found') == 'Lost'
                                          ? const Color(0xFFE53935)
                                          : const Color(0xFF43A047),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              data?['description'] ?? '',
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                color: textColor.withOpacity(0.8),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                const Icon(Icons.location_on,
                                    size: 20, color: Color(0xFF666666)),
                                const SizedBox(width: 8),
                                Text(
                                  data?['location'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Color(0xFF666666),
                                  ),
                                ),
                              ],
                            ),
                            if (!isOwner) ...[
                              const SizedBox(height: 32),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: () async {
                                    String phone = (data?['phone'] ?? '')
                                        .toString()
                                        .trim();
                                    if (phone.isEmpty) {
                                      Get.snackbar(
                                          "Error", "Phone number not available",
                                          snackPosition: SnackPosition.BOTTOM);
                                      return;
                                    }
                                    // Sanitize and build whatsapp link
                                    final waNumber =
                                        sanitizePhoneForWhatsApp(phone);
                                    if (waNumber.isEmpty) {
                                      Get.snackbar(
                                          "Error", "Invalid phone number",
                                          snackPosition: SnackPosition.BOTTOM);
                                      return;
                                    }

                                    final waUri =
                                        Uri.parse('https://wa.me/$waNumber');
                                    try {
                                      await launchUrl(waUri);
                                    } catch (e) {
                                      // Fallback to tel: using international + prefix
                                      final telNumber =
                                          waNumber.startsWith('92')
                                              ? '+$waNumber'
                                              : '+$waNumber';
                                      final telUri =
                                          Uri.parse('tel:$telNumber');
                                      try {
                                        await launchUrl(telUri);
                                      } catch (e2) {
                                        Get.snackbar("Error",
                                            "Could not open contact method",
                                            snackPosition:
                                                SnackPosition.BOTTOM);
                                      }
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kPrimaryColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text(
                                    'Contact',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    Get.dialog(
      AlertDialog(
        title: const Text("Delete Post"),
        content: const Text("Are you sure you want to delete this post?"),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              Get.back();
              try {
                final dynamic s = widget.snap;
                String id = '';
                if (s is DocumentSnapshot)
                  id = s.id;
                else if (s is QueryDocumentSnapshot)
                  id = s.id;
                else if (s is Map<String, dynamic>)
                  id = (s['postId'] ?? '') as String;
                await FirestoreMethods().deletePost(id);
                Get.back();
                Get.snackbar("Success", "Post deleted",
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: Colors.green.shade100);
              } catch (e) {
                Get.snackbar("Error", "Failed to delete post: $e",
                    snackPosition: SnackPosition.BOTTOM,
                    backgroundColor: Colors.red.shade100);
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// EDIT POST VIEW
// ==========================================

class EditPostView extends StatefulWidget {
  final dynamic snap;
  const EditPostView({super.key, required this.snap});

  @override
  State<EditPostView> createState() => _EditPostViewState();
}

class _EditPostViewState extends State<EditPostView> {
  late TextEditingController _title;
  late TextEditingController _desc;
  late TextEditingController _location;
  late TextEditingController _phone;
  late String category;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.snap['title']);
    _desc = TextEditingController(text: widget.snap['description']);
    _location = TextEditingController(text: widget.snap['location']);
    _phone = TextEditingController(text: widget.snap['phone']);
    category = widget.snap['category'] ?? 'Other';
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _location.dispose();
    _phone.dispose();
    super.dispose();
  }

  _updatePost() async {
    if (_title.text.isEmpty ||
        _desc.text.isEmpty ||
        _location.text.isEmpty ||
        _phone.text.isEmpty) {
      Get.snackbar("Error", "All fields are required",
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade100);
      return;
    }
    if (!PhoneValidator.isValidPhone(_phone.text)) {
      Get.snackbar(
          "Error", "Phone format invalid. Use +923115428907 or 03115428907",
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade100);
      return;
    }
    setState(() => isLoading = true);
    try {
      String formattedPhone = PhoneValidator.formatPhone(_phone.text);
      String res = await FirestoreMethods().updatePost(
        widget.snap['postId'],
        _title.text,
        _desc.text,
        _location.text,
        category,
        formattedPhone,
      );
      setState(() => isLoading = false);
      if (res == "Success") {
        Get.back();
        Get.snackbar("Success", "Post updated",
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.green.shade100);
      } else {
        Get.snackbar("Error", res,
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red.shade100);
      }
    } catch (e) {
      setState(() => isLoading = false);
      Get.snackbar("Error", e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade100);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = getAppBackgroundColor(context);

    return Scaffold(
      backgroundColor: kPrimaryColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Get.back(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Edit Post',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            // Content
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      _buildTextField(
                        'Category',
                        null,
                        enabled: true,
                        suffix: DropdownButton<String>(
                          value: category,
                          underline: const SizedBox(),
                          items: [
                            'Gadgets',
                            'Books',
                            'Id-Card',
                            'Bottle',
                            'Other'
                          ]
                              .map((e) =>
                                  DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setState(() => category = v!),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildTextField('Title', _title),
                      const SizedBox(height: 16),
                      _buildTextField('Description', _desc, maxLines: 3),
                      const SizedBox(height: 16),
                      _buildTextField('Location', _location),
                      const SizedBox(height: 16),
                      _buildTextField('Phone Number', _phone,
                          hint: '+923115428907 or 03115428907',
                          keyboardType: TextInputType.phone),
                      const SizedBox(height: 32),
                      isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _updatePost,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimaryColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Update Post',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController? controller, {
    String? hint,
    int maxLines = 1,
    bool enabled = true,
    Widget? suffix,
    TextInputType? keyboardType,
  }) {
    final textColor = getAppTextColor(context);
    final cardColor = getAppCardColor(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: TextField(
            controller: controller,
            enabled: enabled,
            maxLines: maxLines,
            keyboardType: keyboardType,
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
              suffix: suffix,
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// PROFILE VIEW
// ==========================================

class ProfileView extends StatelessWidget {
  const ProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    var user = AuthService().currentUser!;
    final backgroundColor = getAppBackgroundColor(context);
    final cardColor = getAppCardColor(context);
    final textColor = getAppTextColor(context);

    return Scaffold(
      backgroundColor: kPrimaryColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Get.back(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'My Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            // Content
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: NetworkImage(
                        user.photoURL ?? "https://via.placeholder.com/150",
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user.email ?? "",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () async {
                            await AuthService().logOut();
                            Get.offAllNamed('/login');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade400,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Logout',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'My Posts',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: StreamBuilder(
                        stream: FirebaseFirestore.instance
                            .collection('posts')
                            .where('uid', isEqualTo: user.uid)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          if (snapshot.data!.docs.isEmpty) {
                            return const Center(
                              child: Text('No posts yet',
                                  style: TextStyle(color: Colors.grey)),
                            );
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: snapshot.data!.docs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final doc = snapshot.data!.docs[index];
                              final data = doc.data() as Map<String, dynamic>;

                              DateTime date;
                              final ts = data['datePublished'];
                              if (ts is Timestamp) {
                                date = ts.toDate();
                              } else if (ts is DateTime) {
                                date = ts;
                              } else {
                                date = DateTime.tryParse(ts.toString()) ??
                                    DateTime.now();
                              }

                              final d = DateTime.now().difference(date);
                              String ago;
                              if (d.inSeconds < 60)
                                ago = '${d.inSeconds}s ago';
                              else if (d.inMinutes < 60)
                                ago = '${d.inMinutes}m ago';
                              else if (d.inHours < 24)
                                ago = '${d.inHours}h ago';
                              else if (d.inDays < 7)
                                ago = '${d.inDays}d ago';
                              else
                                ago = '${date.day}/${date.month}/${date.year}';

                              final postType = data['postType'] ?? 'Found';

                              return GestureDetector(
                                onTap: () =>
                                    Get.to(() => PostDetailView(snap: doc)),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: cardColor,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.all(12),
                                    leading: SizedBox(
                                      width: 60,
                                      height: 60,
                                      child: SmartImageDisplay(
                                        imageData: data['postUrl'],
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    title: Text(
                                      data['title'] ?? '',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: textColor,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '$postType • ${data['location'] ?? ''} • $ago',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ),
                                    trailing: FutureBuilder<DocumentSnapshot?>(
                                      future: () async {
                                        final user = AuthService().currentUser;
                                        if (user == null) return null;
                                        try {
                                          return await FirebaseFirestore
                                              .instance
                                              .collection('users')
                                              .doc(user.uid)
                                              .get();
                                        } catch (e) {
                                          return null;
                                        }
                                      }(),
                                      builder: (context, usrSnap) {
                                        final postOwner =
                                            (data['uid'] ?? '').toString();
                                        final postUni =
                                            (data['uniId'] ?? '').toString();

                                        final currentUserUid =
                                            AuthService().currentUser?.uid ??
                                                '';
                                        final usrData = usrSnap.data?.data()
                                            as Map<String, dynamic>?;
                                        final currentUserRole =
                                            usrData?['role'] ?? 'student';
                                        final currentUserUni =
                                            usrData?['uniId'] ?? '';

                                        final canEditOrDelete = currentUserUid
                                                .isNotEmpty &&
                                            (currentUserUid == postOwner ||
                                                currentUserRole ==
                                                    'super_admin' ||
                                                (currentUserRole ==
                                                        'uni_admin' &&
                                                    postUni == currentUserUni));

                                        if (!canEditOrDelete)
                                          return const SizedBox.shrink();

                                        return PopupMenuButton<String>(
                                          onSelected: (v) async {
                                            if (v == 'edit') {
                                              Get.to(() =>
                                                  EditPostView(snap: doc));
                                            } else if (v == 'delete') {
                                              final confirmed =
                                                  await Get.dialog<bool>(
                                                AlertDialog(
                                                  title:
                                                      const Text('Delete Post'),
                                                  content: const Text(
                                                    'Are you sure you want to delete this post?',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Get.back(
                                                          result: false),
                                                      child:
                                                          const Text('Cancel'),
                                                    ),
                                                    TextButton(
                                                      onPressed: () => Get.back(
                                                          result: true),
                                                      child: const Text(
                                                        'Delete',
                                                        style: TextStyle(
                                                            color: Colors.red),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirmed == true) {
                                                try {
                                                  await FirestoreMethods()
                                                      .deletePost(
                                                          data['postId'] ??
                                                              doc.id);
                                                  Get.snackbar(
                                                      'Success', 'Post deleted',
                                                      snackPosition:
                                                          SnackPosition.BOTTOM,
                                                      backgroundColor: Colors
                                                          .green.shade100);
                                                } catch (e) {
                                                  Get.snackbar('Error',
                                                      'Failed to delete: $e',
                                                      snackPosition:
                                                          SnackPosition.BOTTOM,
                                                      backgroundColor:
                                                          Colors.red.shade100);
                                                }
                                              }
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            const PopupMenuItem(
                                                value: 'edit',
                                                child: Text('Edit')),
                                            const PopupMenuItem(
                                                value: 'delete',
                                                child: Text('Delete')),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}