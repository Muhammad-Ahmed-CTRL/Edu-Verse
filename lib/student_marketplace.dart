import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'shared.dart';
import 'lost_and_found.dart';
import 'notifications.dart';
import 'poster/marketplace_poster_slideshow.dart';

// --- IMPORT GLOBAL THEME ---
import 'theme_colors.dart';

// Minimal, robust marketplace implementation to restore app compilation.

String formatPrice(dynamic price) {
  if (price == null) return '0';
  if (price is num) return price.toStringAsFixed(0);
  final parsed = double.tryParse(price.toString());
  return parsed != null ? parsed.toStringAsFixed(0) : price.toString();
}

// ==========================================
// SHIMMER LOADING WIDGET
// ==========================================

class ShimmerLoading extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const ShimmerLoading(
      {super.key,
      required this.width,
      required this.height,
      this.borderRadius = const BorderRadius.all(Radius.circular(16))});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Darker shimmer for dark mode
    final baseColor = isDark ? Colors.white10 : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.white24 : Colors.grey[200]!;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final val = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                (val - 0.3).clamp(0.0, 1.0),
                val.clamp(0.0, 1.0),
                (val + 0.3).clamp(0.0, 1.0)
              ],
              begin: const Alignment(-1.0, -0.3),
              end: const Alignment(1.0, 0.3),
            ),
          ),
        );
      },
    );
  }
}

class MarketplaceService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot> getBannersStream(String uniId) {
    return _db
        .collection('universities')
        .doc(uniId)
        .collection('marketplace_banners')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> getItemsStream(String uniId, {String? category}) {
    Query q = _db
        .collection('universities')
        .doc(uniId)
        .collection('marketplace_items')
        .where('status', isEqualTo: 'available');
    if (category != null && category != 'All') {
      q = q.where('category', isEqualTo: category);
    }
    return q.snapshots();
  }

  Future<String> addItem(
      {required String uniId,
      required String uid,
      required String username,
      required String title,
      required double price,
      required String description,
      required String category,
      required String condition,
      required String phone,
      required Uint8List imageData}) async {
    try {
      final base64Image = base64Encode(imageData);
      final docRef = await _db
          .collection('universities')
          .doc(uniId)
          .collection('marketplace_items')
          .add({
        'uid': uid,
        'username': username,
        'title': title,
        'price': price,
        'description': description,
        'category': category,
        'condition': condition,
        'phone': phone,
        'imageData': base64Image,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'available',
      });

      // Notify university about new marketplace item
      try {
        await NotificationService().notifyMarketplace(
          universityId: uniId,
          itemName: title,
          price: price.toStringAsFixed(0),
          postId: docRef.id,
          imageUrl: null,
        );
      } catch (e) {
        debugPrint('Failed to notify marketplace: $e');
      }

      return docRef.id;
    } catch (e) {
      debugPrint('addItem error: $e');
      return e.toString();
    }
  }

  Future<void> deleteItem(String uniId, String itemId) async {
    await _db
        .collection('universities')
        .doc(uniId)
        .collection('marketplace_items')
        .doc(itemId)
        .delete();
  }

  Stream<QuerySnapshot> getMyItemsStream(String uniId, String userId) {
    return _db
        .collection('universities')
        .doc(uniId)
        .collection('marketplace_items')
        .where('uid', isEqualTo: userId)
        .snapshots();
  }

  Stream<QuerySnapshot> getMyItemsAcrossUniversitiesStream(String userId) {
    return _db
        .collectionGroup('marketplace_items')
        .where('uid', isEqualTo: userId)
        .snapshots();
  }

  Stream<QuerySnapshot> getAllItemsAcrossUniversitiesStream(
      {String? category}) {
    Query q = _db
        .collectionGroup('marketplace_items')
        .where('status', isEqualTo: 'available');
    if (category != null && category != 'All') {
      q = q.where('category', isEqualTo: category);
    }
    return q.snapshots();
  }

  Future<String> updateItem(
      {required String uniId,
      required String itemId,
      required String title,
      required double price,
      required String description,
      required String category,
      required String condition,
      required String phone}) async {
    try {
      await _db
          .collection('universities')
          .doc(uniId)
          .collection('marketplace_items')
          .doc(itemId)
          .update({
        'title': title,
        'price': price,
        'description': description,
        'category': category,
        'condition': condition,
        'phone': phone,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return 'Success';
    } catch (e) {
      debugPrint('updateItem error: $e');
      return e.toString();
    }
  }

  Future<String> addBanner(
      {required String uniId,
      required Uint8List imageData,
      required String title}) async {
    try {
      final base64Image = base64Encode(imageData);
      await _db
          .collection('universities')
          .doc(uniId)
          .collection('marketplace_banners')
          .add({
        'title': title,
        'imageData': base64Image,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return 'Success';
    } catch (e) {
      debugPrint('addBanner error: $e');
      return e.toString();
    }
  }

  Future<void> deleteBanner(String uniId, String bannerId) async {
    await _db
        .collection('universities')
        .doc(uniId)
        .collection('marketplace_banners')
        .doc(bannerId)
        .delete();
  }
}

class StudentMarketplace extends StatefulWidget {
  final String? adminViewUniId;
  const StudentMarketplace({super.key, this.adminViewUniId});

  @override
  State<StudentMarketplace> createState() => _StudentMarketplaceState();
}

class _StudentMarketplaceState extends State<StudentMarketplace> {
  final MarketplaceService _service = MarketplaceService();
  final TextEditingController _searchController = TextEditingController();
  String selectedCategory = 'All';

  // UI controllers / state
  final ScrollController _scrollController = ScrollController();
  final PageController _bannerController =
      PageController(viewportFraction: 0.9);
  int _currentBanner = 0;

  // user context
  String? userId;
  String userRole = 'student';

  final List<String> categories = [
    'All',
    'Books',
    'Gadgets',
    'Notes',
    'Dorm Essentials',
    'Clothing',
    'Stationery',
    'Other'
  ];

  String? _resolvedUniId;

  @override
  void initState() {
    super.initState();
    _resolveUniId();
  }

  @override
  void didUpdateWidget(covariant StudentMarketplace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.adminViewUniId != oldWidget.adminViewUniId) {
      setState(() {
        _resolvedUniId = widget.adminViewUniId;
      });
    }
  }

  Future<void> _resolveUniId() async {
    if (widget.adminViewUniId != null && widget.adminViewUniId!.isNotEmpty) {
      _resolvedUniId = widget.adminViewUniId;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _resolvedUniId = widget.adminViewUniId;
        userId = null;
        userRole = 'student';
      });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data() as Map<String, dynamic>?;
      final role = data?['role'] as String? ?? 'student';

      String? uniId = widget.adminViewUniId;
      if (uniId == null || uniId.isEmpty) {
        if (data != null &&
            data['adminScope'] is Map &&
            data['adminScope']['uniId'] != null) {
          uniId = data['adminScope']['uniId']?.toString();
        } else {
          uniId = data?['uniId'] as String?;
        }
      }
      setState(() {
        _resolvedUniId = uniId;
        userId = user.uid;
        userRole = role;
      });
    } catch (e) {
      debugPrint('Failed to resolve user context: $e');
      setState(() {
        _resolvedUniId = widget.adminViewUniId;
        userId = user.uid;
        userRole = 'student';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic Theme
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: kPrimaryColor,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              title: const Text(
                'Marketplace',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    // Uses Global Theme Colors
                    colors: [kPrimaryColor, kSecondaryColor],
                  ),
                ),
              ),
            ),
            actions: [
              if (userRole == 'admin' || userRole == 'super_admin')
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate,
                      color: Colors.white),
                  tooltip: 'Add Banner',
                  onPressed: () => Get.to(() => AddBannerView(
                      uniId: _resolvedUniId ?? widget.adminViewUniId!)),
                ),
              IconButton(
                icon:
                    const Icon(Icons.inventory_2_outlined, color: Colors.white),
                tooltip: 'My Ads',
                onPressed: () {
                  final uid = userId ?? FirebaseAuth.instance.currentUser?.uid;
                  if (uid == null) {
                    MySnackBar().mySnackBar(
                      header: 'Not signed in',
                      content: 'Please sign in to view your ads',
                      bgColor: Colors.red.shade100,
                    );
                    return;
                  }
                  final uni = _resolvedUniId ?? widget.adminViewUniId;
                  if (uni == null) {
                    MySnackBar().mySnackBar(
                      header: 'University not set',
                      content:
                          'Your account does not have a university assigned.',
                      bgColor: Colors.red.shade100,
                    );
                    return;
                  }
                  Get.to(() => MyAdsView(uniId: uni, userId: uid));
                },
              ),
            ],
          ),

          // Sticky Search Bar
          SliverPersistentHeader(
            pinned: true,
            delegate: _SearchBarDelegate(
                controller: _searchController,
                onChanged: () => setState(() {})),
          ),

          // Poster slideshow
          SliverToBoxAdapter(child: MarketplacePosterSlideshow()),

          // Banner carousel
          SliverToBoxAdapter(child: _premiumBannerSection()),

          // Category pills
          SliverToBoxAdapter(child: _buildCategoryPills()),

          // Items grid
          _buildItemsGrid(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_resolvedUniId == null) {
            MySnackBar().mySnackBar(
              header: 'University not set',
              content:
                  'Your account does not have a university assigned. Please update your profile.',
              bgColor: Colors.red.shade100,
            );
            return;
          }
          Get.to(() => SellItemView(uniId: _resolvedUniId!));
        },
        label: const Text('Sell', style: TextStyle(color: Colors.white)),
        icon: const Icon(Icons.add, color: Colors.white),
        backgroundColor: kPrimaryColor,
      ),
    );
  }

  // Premium banner section
  Widget _buildDefaultBanner() {
    return Container(
      height: 200,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: [kPrimaryColor, kSecondaryColor]),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: kPrimaryColor.withOpacity(0.25),
              blurRadius: 20,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.store, color: Colors.white, size: 56),
          const SizedBox(height: 12),
          const Text('Student Marketplace',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Buy & sell within your university',
              style: TextStyle(color: Colors.white.withOpacity(0.9))),
        ]),
      ),
    );
  }

  Widget _premiumBannerSection() {
    if (_resolvedUniId == null) return _buildDefaultBanner();

    return StreamBuilder<QuerySnapshot>(
      stream: _service.getBannersStream(_resolvedUniId!),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildDefaultBanner();
        }
        final banners = snapshot.data!.docs;
        return SizedBox(
          height: 220,
          child: BannerCarousel(
            banners: banners,
            isAdmin: (userRole == 'admin' || userRole == 'super_admin'),
            onDelete: (index) async {
              final id = banners[index].id;
              _confirmDeleteBanner(id);
            },
          ),
        );
      },
    );
  }

  Widget _buildCategoryPills() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardTheme.color ?? kWhiteColor;
    final textColor = isDark ? Colors.white70 : kDarkTextColor;

    return SizedBox(
      height: 70,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final isSelected = selectedCategory == category;
          return Padding(
            padding: const EdgeInsets.only(right: 12, top: 12, bottom: 12),
            child: GestureDetector(
              onTap: () => setState(() => selectedCategory = category),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(colors: [
                          kPrimaryColor,
                          kSecondaryColor
                        ])
                      : null,
                  color: isSelected ? null : cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color:
                            Colors.black.withOpacity(isSelected ? 0.12 : 0.04),
                        blurRadius: isSelected ? 14 : 6,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: Text(category,
                    style: TextStyle(
                        color: isSelected ? Colors.white : textColor,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w600)),
              ),
            ),
          );
        },
      ),
    );
  }

  // Builds items grid
  Widget _buildItemsGrid() {
    final stream = _resolvedUniId == null
        ? _service.getAllItemsAcrossUniversitiesStream(
            category: selectedCategory == 'All' ? null : selectedCategory)
        : _service.getItemsStream(_resolvedUniId!,
            category: selectedCategory == 'All' ? null : selectedCategory);

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.72,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12),
              delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      const ShimmerLoading(width: double.infinity, height: 260),
                  childCount: 6),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return SliverFillRemaining(
            child: Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_bag_outlined,
                        size: 100, color: Colors.grey[300]),
                    const SizedBox(height: 24),
                    Text('No items found',
                        style: TextStyle(
                            fontSize: 20,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('Be the first to post something!',
                        style:
                            TextStyle(fontSize: 16, color: Colors.grey[500])),
                  ]),
            ),
          );
        }

        final docs = List<QueryDocumentSnapshot>.from(snapshot.data!.docs);
        final items = docs.where((doc) {
          if (_searchController.text.isEmpty) return true;
          final data = doc.data() as Map<String, dynamic>;
          final q = _searchController.text.toLowerCase();
          return (data['title'] ?? '').toString().toLowerCase().contains(q) ||
              (data['description'] ?? '').toString().toLowerCase().contains(q);
        }).toList();

        if (items.isEmpty) {
          return const SliverFillRemaining(
              child: Center(child: Text('No items match your search')));
        }

        items.sort((a, b) {
          final ta = (a.data() as Map<String, dynamic>)['createdAt'];
          final tb = (b.data() as Map<String, dynamic>)['createdAt'];
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return (tb as Timestamp).compareTo(ta as Timestamp);
        });

        return SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12),
            delegate: SliverChildBuilderDelegate((context, index) {
              final doc = items[index];
              final data = doc.data() as Map<String, dynamic>;
              final parentUni =
                  doc.reference.parent.parent?.id ?? _resolvedUniId ?? '';
              return _StaggeredItemCard(
                  index: index,
                  itemId: doc.id,
                  data: data,
                  uniId: parentUni,
                  userId: userId,
                  userRole: userRole,
                  onDelete: () => _confirmDeleteItem(parentUni, doc.id));
            }, childCount: items.length),
          ),
        );
      },
    );
  }

  void _confirmDeleteBanner(String bannerId) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Banner'),
        content: const Text('Are you sure you want to delete this banner?'),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Get.back();
              try {
                final uni = _resolvedUniId ?? widget.adminViewUniId;
                if (uni != null) await _service.deleteBanner(uni, bannerId);
                MySnackBar().mySnackBar(
                    header: 'Success',
                    content: 'Banner deleted',
                    bgColor: Colors.green.shade100);
              } catch (e) {
                MySnackBar().mySnackBar(
                    header: 'Error',
                    content: 'Failed to delete banner',
                    bgColor: Colors.red.shade100);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteItem(String uniId, String itemId) {
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Item'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Get.back();
              try {
                final uni = (uniId.isNotEmpty ? uniId : null) ??
                    _resolvedUniId ??
                    widget.adminViewUniId;
                if (uni != null) await _service.deleteItem(uni, itemId);
                MySnackBar().mySnackBar(
                    header: 'Success',
                    content: 'Item deleted',
                    bgColor: Colors.green.shade100);
              } catch (e) {
                MySnackBar().mySnackBar(
                    header: 'Error',
                    content: 'Failed to delete item',
                    bgColor: Colors.red.shade100);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// Simple image display helper
class MarketplaceImageDisplay extends StatelessWidget {
  final String imageData;
  final double? height;
  final double? width;
  final BoxFit fit;

  const MarketplaceImageDisplay(
      {super.key,
      required this.imageData,
      this.height,
      this.width,
      this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    if (imageData.isEmpty) {
      return Container(color: Colors.grey[200], height: height, width: width);
    }
    if (imageData.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageData,
        height: height,
        width: width,
        fit: fit,
        placeholder: (c, s) =>
            Container(color: Colors.grey[200], height: height, width: width),
        errorWidget: (c, s, e) =>
            Container(color: Colors.grey[200], height: height, width: width),
      );
    }

    try {
      final bytes = base64Decode(imageData);
      return Image.memory(bytes, height: height, width: width, fit: fit);
    } catch (_) {
      return Container(color: Colors.grey[200], height: height, width: width);
    }
  }
}

// Carousel
class MarketplaceImageCarousel extends StatefulWidget {
  final List<String> images;
  final double? height;
  final double? width;
  final BoxFit fit;

  const MarketplaceImageCarousel({
    super.key,
    required this.images,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
  });

  @override
  State<MarketplaceImageCarousel> createState() =>
      _MarketplaceImageCarouselState();
}

// BannerCarousel
class BannerCarousel extends StatefulWidget {
  final List<QueryDocumentSnapshot> banners;
  final bool isAdmin;
  final Future<void> Function(int index)? onDelete;
  const BannerCarousel(
      {super.key, required this.banners, this.isAdmin = false, this.onDelete});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  late final PageController _controller;
  int _current = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.96);
    if (widget.banners.length > 1) _startAutoplay();
  }

  void _startAutoplay() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (!mounted) return;
      final next = (_current + 1) % widget.banners.length;
      if (_controller.hasClients) {
        _controller.animateToPage(next,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.banners;
    if (banners.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: GestureDetector(
            onPanDown: (_) => _timer?.cancel(),
            onPanCancel: () {
              if (widget.banners.length > 1) _startAutoplay();
            },
            onPanEnd: (_) {
              if (widget.banners.length > 1) _startAutoplay();
            },
            child: PageView.builder(
              controller: _controller,
              itemCount: banners.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, index) {
                final banner = banners[index];
                final data = banner.data() as Map<String, dynamic>;
                final image = data['imageData'] ?? '';
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if ((data['images'] is List) ||
                            (data['imageUrls'] is List))
                          MarketplaceImageCarousel(
                            images: (data['images'] is List)
                                ? List<String>.from((data['images'] as List)
                                    .map((e) => e?.toString() ?? ''))
                                : List<String>.from((data['imageUrls'] as List)
                                    .map((e) => e?.toString() ?? '')),
                            height: 200,
                            fit: BoxFit.cover,
                          )
                        else if (image.toString().startsWith('http'))
                          CachedNetworkImage(
                              imageUrl: image.toString(), fit: BoxFit.cover)
                        else if ((image ?? '').toString().isNotEmpty)
                          Image.memory(base64Decode(image.toString()),
                              fit: BoxFit.cover)
                        else
                          Container(color: Colors.grey[200]),

                        if (widget.isAdmin)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(12)),
                              child: IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.white),
                                onPressed: () async {
                                  if (widget.onDelete != null) {
                                    await widget.onDelete!(_current);
                                  }
                                },
                              ),
                            ),
                          ),

                        // Text overlay
                        if ((data['title'] ?? '').toString().isNotEmpty ||
                            (data['description'] ?? '').toString().isNotEmpty)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.6)
                                  ],
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if ((data['title'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Text((data['title'] ?? '').toString(),
                                        style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold)),
                                  if ((data['description'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                          (data['description'] ?? '')
                                              .toString(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13)),
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
            ),
          ),
        ),
        if (banners.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(banners.length, (i) {
                final active = i == _current;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(active ? 0.85 : 0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _MarketplaceImageCarouselState extends State<MarketplaceImageCarousel> {
  late final PageController _controller;
  int _current = 0;
  Timer? _autoplayTimer;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    if (widget.images.length > 1) _startAutoplay();
  }

  void _startAutoplay() {
    _autoplayTimer?.cancel();
    _autoplayTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (_isPaused) return;
      final next = (_current + 1) % widget.images.length;
      if (mounted) {
        _controller.animateToPage(next,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut);
      }
    });
  }

  @override
  void dispose() {
    _autoplayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Widget _buildImage(String image) {
    if (image.isEmpty) {
      return Container(
          color: Colors.grey[200], height: widget.height, width: widget.width);
    }
    if (image.startsWith('http')) {
      return CachedNetworkImage(
          imageUrl: image,
          height: widget.height,
          width: widget.width,
          fit: widget.fit,
          placeholder: (c, s) => Container(
              color: Colors.grey[200],
              height: widget.height,
              width: widget.width),
          errorWidget: (c, s, e) => Container(
              color: Colors.grey[200],
              height: widget.height,
              width: widget.width));
    }
    try {
      final bytes = base64Decode(image);
      return Image.memory(bytes,
          height: widget.height, width: widget.width, fit: widget.fit);
    } catch (_) {
      return Container(
          color: Colors.grey[200], height: widget.height, width: widget.width);
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images.isEmpty ? [''] : widget.images;
    if (images.length == 1) return _buildImage(images.first);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPaused = true),
      onTapUp: (_) => setState(() => _isPaused = false),
      onTapCancel: () => setState(() => _isPaused = false),
      child: SizedBox(
        height: widget.height,
        width: widget.width,
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, index) => _buildImage(images[index]),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(images.length, (i) {
                  final active = i == _current;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(active ? 0.85 : 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// SEARCH BAR DELEGATE
// ==========================================

class _SearchBarDelegate extends SliverPersistentHeaderDelegate {
  final TextEditingController controller;
  final VoidCallback onChanged;

  _SearchBarDelegate({required this.controller, required this.onChanged});

  @override
  double get minExtent => 72;
  @override
  double get maxExtent => 72;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black12 : Colors.grey[50];
    final fieldColor = isDark ? Theme.of(context).cardColor : Colors.white;
    final hintColor = isDark ? Colors.white54 : Colors.grey;

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          hintText: 'Search marketplace...',
          hintStyle: TextStyle(color: hintColor),
          prefixIcon: const Icon(Icons.search, color: kPrimaryColor),
          filled: true,
          fillColor: fieldColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      true;
}

// ==========================================
// STAGGERED ITEM CARD WITH ANIMATION
// ==========================================

class _StaggeredItemCard extends StatefulWidget {
  final int index;
  final String itemId;
  final Map<String, dynamic> data;
  final String uniId;
  final String? userId;
  final String userRole;
  final VoidCallback onDelete;

  const _StaggeredItemCard({
    required this.index,
    required this.itemId,
    required this.data,
    required this.uniId,
    required this.userId,
    required this.userRole,
    required this.onDelete,
  });

  @override
  State<_StaggeredItemCard> createState() => _StaggeredItemCardState();
}

class _StaggeredItemCardState extends State<_StaggeredItemCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500 + (widget.index * 100)),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.data['uid'] == widget.userId;
    final isAdmin =
        widget.userRole == 'admin' || widget.userRole == 'super_admin';

    // Dynamic colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardTheme.color ?? Colors.white;
    final textColor = isDark ? Colors.white : kDarkTextColor;
    final secondaryText = isDark ? Colors.white54 : Colors.grey[600];

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: GestureDetector(
          onTap: () => Get.to(
            () => ItemDetailView(
              uniId: widget.uniId,
              itemId: widget.itemId,
              itemData: widget.data,
            ),
            transition: Transition.fadeIn,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Hero(
                      tag: 'item_${widget.itemId}',
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                        child: MarketplaceImageCarousel(
                          images: (widget.data['images'] is List)
                              ? List<String>.from(
                                  (widget.data['images'] as List)
                                      .map((e) => e?.toString() ?? ''))
                              : (widget.data['imageUrls'] is List)
                                  ? List<String>.from(
                                      (widget.data['imageUrls'] as List)
                                          .map((e) => e?.toString() ?? ''))
                                  : [
                                      widget.data['imageUrl'] ??
                                          widget.data['imageData'] ??
                                          ''
                                    ],
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: widget.data['condition'] == 'New'
                              ? Colors.green
                              : Colors.orange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.data['condition'] ?? 'Used',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (isOwner || isAdmin)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.delete,
                                size: 18, color: Colors.white),
                            padding: const EdgeInsets.all(8),
                            onPressed: widget.onDelete,
                          ),
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rs ${formatPrice(widget.data['price'])}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: kPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.data['title'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Text(
                          widget.data['category'] ?? 'Other',
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// MY ADS VIEW
// ==========================================

class MyAdsView extends StatelessWidget {
  final String? uniId;
  final String userId;

  const MyAdsView({super.key, this.uniId, required this.userId});

  @override
  Widget build(BuildContext context) {
    final service = MarketplaceService();
    // Dynamic colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardTheme.color ?? Colors.white;
    final textColor = isDark ? Colors.white : kDarkTextColor;
    final secondaryText = isDark ? Colors.white70 : kDarkTextColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Ads'),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: uniId != null
            ? service.getMyItemsStream(uniId!, userId)
            : service.getMyItemsAcrossUniversitiesStream(userId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.red[700]),
                ),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 100, color: Colors.grey[300]),
                  const SizedBox(height: 24),
                  Text(
                    'No ads yet',
                    style: TextStyle(
                        fontSize: 20,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start selling to see your ads here',
                    style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          final items = List<QueryDocumentSnapshot>.from(snapshot.data!.docs);
          items.sort((a, b) {
            final ta = (a.data() as Map<String, dynamic>)['createdAt'];
            final tb = (b.data() as Map<String, dynamic>)['createdAt'];
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return (tb as Timestamp).compareTo(ta as Timestamp);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final doc = items[index];
              final data = doc.data() as Map<String, dynamic>;

              return Card(
                color: cardColor,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 4,
                child: InkWell(
                  onTap: () {
                    final parentUni =
                        doc.reference.parent.parent?.id ?? uniId ?? '';
                    Get.to(() => ItemDetailView(
                          uniId: parentUni,
                          itemId: doc.id,
                          itemData: data,
                        ));
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                        ),
                        child: MarketplaceImageCarousel(
                          images: (data['images'] is List)
                              ? List<String>.from((data['images'] as List)
                                  .map((e) => e?.toString() ?? ''))
                              : (data['imageUrls'] is List)
                                  ? List<String>.from(
                                      (data['imageUrls'] as List)
                                          .map((e) => e?.toString() ?? ''))
                                  : [
                                      data['imageUrl'] ??
                                          data['imageData'] ??
                                          ''
                                    ],
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['title'] ?? '',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Rs ${formatPrice(data['price'])}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: kPrimaryColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                data['category'] ?? 'Other',
                                style: TextStyle(
                                    fontSize: 12, color: secondaryText),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: kPrimaryColor),
                            onPressed: () => Get.to(() => EditItemView(
                                  uniId: doc.reference.parent.parent?.id ??
                                      uniId ??
                                      '',
                                  itemId: doc.id,
                                  itemData: data,
                                )),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              final confirm = await Get.dialog<bool>(
                                AlertDialog(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20)),
                                  title: const Text('Delete Item'),
                                  content: const Text(
                                      'Are you sure you want to delete this item?'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Get.back(result: false),
                                        child: const Text('Cancel')),
                                    ElevatedButton(
                                      onPressed: () => Get.back(result: true),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12))),
                                      child: const Text('Delete',
                                          style:
                                              TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm != true) return;

                              try {
                                final parentUni =
                                    doc.reference.parent.parent?.id ??
                                        uniId ??
                                        '';
                                if (parentUni.isEmpty) {
                                  MySnackBar().mySnackBar(
                                      header: 'Error',
                                      content: 'University unknown',
                                      bgColor: Colors.red.shade100);
                                  return;
                                }
                                await service.deleteItem(parentUni, doc.id);
                                MySnackBar().mySnackBar(
                                    header: 'Success',
                                    content: 'Item deleted',
                                    bgColor: Colors.green.shade100);
                              } catch (e) {
                                MySnackBar().mySnackBar(
                                    header: 'Error',
                                    content: 'Failed to delete item',
                                    bgColor: Colors.red.shade100);
                              }
                            },
                          ),
                        ],
                      ),
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

// ==========================================
// SELL/ADD ITEM VIEW
// ==========================================

class SellItemView extends StatefulWidget {
  final String uniId;
  const SellItemView({super.key, required this.uniId});

  @override
  State<SellItemView> createState() => _SellItemViewState();
}

class _SellItemViewState extends State<SellItemView> {
  final MarketplaceService _service = MarketplaceService();
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _descController = TextEditingController();
  final _phoneController = TextEditingController();

  String selectedCategory = 'Books';
  String selectedCondition = 'Used';
  Uint8List? _imageData;
  bool isLoading = false;

  final List<String> categories = [
    'Books',
    'Gadgets',
    'Notes',
    'Dorm Essentials',
    'Clothing',
    'Stationery',
    'Other'
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() => _imageData = bytes);
    }
  }

  Future<void> _submitItem() async {
    if (!_formKey.currentState!.validate()) return;

    if (_imageData == null) {
      MySnackBar().mySnackBar(
        header: 'Error',
        content: 'Please select an image',
        bgColor: Colors.red.shade100,
      );
      return;
    }

    if (!PhoneValidator.isValidPhone(_phoneController.text)) {
      MySnackBar().mySnackBar(
        header: 'Error',
        content: 'Invalid phone format. Use +923115428907 or 03115428907',
        bgColor: Colors.red.shade100,
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userName = userDoc.data()?['name'] ?? 'User';

      final result = await _service.addItem(
        uniId: widget.uniId,
        uid: user.uid,
        username: userName,
        title: _titleController.text.trim(),
        price: double.parse(_priceController.text),
        description: _descController.text.trim(),
        category: selectedCategory,
        condition: selectedCondition,
        phone: PhoneValidator.formatPhone(_phoneController.text),
        imageData: _imageData!,
      );

      setState(() => isLoading = false);

      if (result.isNotEmpty && !result.toLowerCase().contains('error')) {
        Get.off(() => MyAdsView(uniId: widget.uniId, userId: user.uid));
        MySnackBar().mySnackBar(
          header: 'Success',
          content: 'Item posted successfully!',
          bgColor: Colors.green.shade100,
        );
      } else {
        MySnackBar().mySnackBar(
          header: 'Error',
          content: result,
          bgColor: Colors.red.shade100,
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      MySnackBar().mySnackBar(
        header: 'Error',
        content: e.toString(),
        bgColor: Colors.red.shade100,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Replaced custom BlueButton with standard ElevatedButton for consistency
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sell Item'),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Posting your item...',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: kPrimaryColor, width: 2),
                        ),
                        child: _imageData == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate,
                                      size: 72, color: Colors.grey[400]),
                                  const SizedBox(height: 12),
                                  Text('Tap to add image',
                                      style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey[600])),
                                ],
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Image.memory(_imageData!,
                                    fit: BoxFit.cover),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildTextField(
                      controller: _titleController,
                      label: 'Title',
                      hint: 'e.g., iPhone 12 Pro',
                      icon: Icons.title,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _priceController,
                      label: 'Price (Rs)',
                      hint: 'e.g., 5000',
                      icon: Icons.currency_rupee,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v!.isEmpty) return 'Required';
                        if (double.tryParse(v) == null) return 'Invalid price';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Builder(builder: (context) {
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      final textColor = getAppTextColor(context);
                      return DropdownButtonFormField<String>(
                        value: selectedCategory,
                        style: TextStyle(color: textColor),
                        dropdownColor: isDark ? kDarkBackgroundColor : kWhiteColor,
                        decoration: InputDecoration(
                          labelText: 'Category',
                          labelStyle: TextStyle(color: textColor),
                          prefixIcon: Icon(Icons.category, color: kPrimaryColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                          filled: true,
                          fillColor: isDark ? kDarkBackgroundColor.withOpacity(0.12) : kWhiteColor,
                        ),
                        items: categories
                            .map((c) => DropdownMenuItem(value: c, child: Text(c, style: TextStyle(color: textColor))))
                            .toList(),
                        onChanged: (v) => setState(() => selectedCategory = v!),
                      );
                    }),
                    const SizedBox(height: 16),
                    const Text('Condition',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildChoiceChip('New', 'New'),
                        const SizedBox(width: 12),
                        _buildChoiceChip('Used', 'Used'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _descController,
                      label: 'Description',
                      hint: 'Describe your item...',
                      icon: Icons.description,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _phoneController,
                      label: 'Phone Number',
                      hint: '+923295008120 or 03295008120',
                      icon: Icons.phone,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _submitItem,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Post Item',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = getAppTextColor(context);
    final inputFillColor = isDark ? kDarkBackgroundColor.withOpacity(0.06) : kWhiteColor;

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: textColor),
        hintText: hint,
        hintStyle: TextStyle(color: textColor.withOpacity(0.6)),
        prefixIcon: Icon(icon, color: kPrimaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        filled: true,
        fillColor: inputFillColor,
      ),
      validator: validator ?? (v) => v!.isEmpty ? 'Required' : null,
    );
  }

  Widget _buildChoiceChip(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = getAppTextColor(context);
    final selected = selectedCondition == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          color: selected ? kPrimaryColor : textColor,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: selected,
      onSelected: (b) => setState(() => selectedCondition = value),
      selectedColor: kPrimaryColor.withOpacity(0.12),
      backgroundColor: isDark ? kDarkBackgroundColor.withOpacity(0.06) : kWhiteColor,
      checkmarkColor: kPrimaryColor,
    );
  }
}

// ==========================================
// ITEM DETAIL VIEW (WITH PARALLAX)
// ==========================================

class ItemDetailView extends StatelessWidget {
  final String uniId;
  final String itemId;
  final Map<String, dynamic> itemData;

  const ItemDetailView({
    super.key,
    required this.uniId,
    required this.itemId,
    required this.itemData,
  });

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isOwner = currentUser?.uid == itemData['uid'];
    
    // Dynamic theme colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardTheme.color ?? Colors.white;
    final textColor = isDark ? Colors.white : kDarkTextColor;
    final secondaryText = isDark ? Colors.white70 : kDarkTextColor;

    return Scaffold(
      backgroundColor: cardColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 350,
            pinned: true,
            backgroundColor: kPrimaryColor,
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'item_$itemId',
                child: MarketplaceImageCarousel(
                  images: (itemData['images'] is List)
                      ? List<String>.from((itemData['images'] as List)
                          .map((e) => e?.toString() ?? ''))
                      : (itemData['imageUrls'] is List)
                          ? List<String>.from((itemData['imageUrls'] as List)
                              .map((e) => e?.toString() ?? ''))
                          : [
                              itemData['imageUrl'] ??
                                  itemData['imageData'] ??
                                  ''
                            ],
                  height: 350,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            actions: [
              if (isOwner)
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white),
                  onPressed: () => Get.to(() => EditItemView(
                        uniId: uniId,
                        itemId: itemId,
                        itemData: itemData,
                      )),
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Rs ${formatPrice(itemData['price'])}',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: kPrimaryColor,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: itemData['condition'] == 'New'
                                ? Colors.green.withOpacity(0.2)
                                : Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            itemData['condition'] ?? 'Used',
                            style: TextStyle(
                              color: itemData['condition'] == 'New'
                                  ? Colors.green[700]
                                  : Colors.orange[700],
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      itemData['title'] ?? '',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.category,
                            size: 18, color: secondaryText),
                        const SizedBox(width: 6),
                        Text(
                          itemData['category'] ?? 'Other',
                          style: TextStyle(
                              color: secondaryText, fontSize: 14),
                        ),
                        const SizedBox(width: 20),
                        Icon(Icons.person,
                            size: 18, color: secondaryText),
                        const SizedBox(width: 6),
                        Text(
                          itemData['username'] ?? 'Unknown',
                          style: TextStyle(
                              color: secondaryText, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      itemData['description'] ?? '',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomSheet: !isOwner
          ? Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () async {
                    final phone = (itemData['phone'] ?? '').toString().trim();
                    if (phone.isEmpty) {
                      MySnackBar().mySnackBar(
                        header: 'Error',
                        content: 'Phone number not available',
                        bgColor: Colors.red.shade100,
                      );
                      return;
                    }

                    final waNumber = sanitizePhoneForWhatsApp(phone);
                    if (waNumber.isEmpty) {
                      MySnackBar().mySnackBar(
                        header: 'Error',
                        content: 'Invalid phone number',
                        bgColor: Colors.red.shade100,
                      );
                      return;
                    }

                    final waUri = Uri.parse('https://wa.me/$waNumber');
                    try {
                      await launchUrl(waUri);
                    } catch (e) {
                      final telUri = Uri.parse('tel:+$waNumber');
                      try {
                        await launchUrl(telUri);
                      } catch (e2) {
                        MySnackBar().mySnackBar(
                          header: 'Error',
                          content: 'Could not open contact method',
                          bgColor: Colors.red.shade100,
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('Contact Seller via WhatsApp',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ),
            )
          : null,
    );
  }
}

// ==========================================
// EDIT ITEM VIEW
// ==========================================

class EditItemView extends StatefulWidget {
  final String uniId;
  final String itemId;
  final Map<String, dynamic> itemData;

  const EditItemView({
    super.key,
    required this.uniId,
    required this.itemId,
    required this.itemData,
  });

  @override
  State<EditItemView> createState() => _EditItemViewState();
}

class _EditItemViewState extends State<EditItemView> {
  final MarketplaceService _service = MarketplaceService();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _priceController;
  late TextEditingController _descController;
  late TextEditingController _phoneController;
  late String selectedCategory;
  late String selectedCondition;

  bool isLoading = false;

  final List<String> categories = [
    'Books',
    'Gadgets',
    'Notes',
    'Dorm Essentials',
    'Clothing',
    'Stationery',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.itemData['title']);
    _priceController = TextEditingController(
        text: widget.itemData['price']?.toString() ?? '0');
    _descController =
        TextEditingController(text: widget.itemData['description']);
    _phoneController = TextEditingController(text: widget.itemData['phone']);
    selectedCategory = widget.itemData['category'] ?? 'Other';
    selectedCondition = widget.itemData['condition'] ?? 'Used';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _updateItem() async {
    if (!_formKey.currentState!.validate()) return;

    if (!PhoneValidator.isValidPhone(_phoneController.text)) {
      MySnackBar().mySnackBar(
        header: 'Error',
        content: 'Invalid phone format',
        bgColor: Colors.red.shade100,
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final result = await _service.updateItem(
        uniId: widget.uniId,
        itemId: widget.itemId,
        title: _titleController.text.trim(),
        price: double.parse(_priceController.text),
        description: _descController.text.trim(),
        category: selectedCategory,
        condition: selectedCondition,
        phone: PhoneValidator.formatPhone(_phoneController.text),
      );

      setState(() => isLoading = false);

      if (result == "Success") {
        Get.back();
        MySnackBar().mySnackBar(
          header: 'Success',
          content: 'Item updated successfully',
          bgColor: Colors.green.shade100,
        );
      } else {
        MySnackBar().mySnackBar(
          header: 'Error',
          content: result,
          bgColor: Colors.red.shade100,
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      MySnackBar().mySnackBar(
        header: 'Error',
        content: e.toString(),
        bgColor: Colors.red.shade100,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Item'),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Title',
                        prefixIcon:
                            const Icon(Icons.title, color: kPrimaryColor),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Price (Rs)',
                        prefixIcon: const Icon(Icons.currency_rupee,
                            color: kPrimaryColor),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      validator: (v) {
                        if (v!.isEmpty) return 'Required';
                        if (double.tryParse(v) == null) return 'Invalid price';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'Category',
                        prefixIcon: const Icon(Icons.category,
                            color: kPrimaryColor),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      items: categories
                          .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => selectedCategory = v!),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('New'),
                          selected: selectedCondition == 'New',
                          onSelected: (b) =>
                              setState(() => selectedCondition = 'New'),
                          selectedColor: kPrimaryColor.withOpacity(0.2),
                          checkmarkColor: kPrimaryColor,
                        ),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text('Used'),
                          selected: selectedCondition == 'Used',
                          onSelected: (b) =>
                              setState(() => selectedCondition = 'Used'),
                          selectedColor: kPrimaryColor.withOpacity(0.2),
                          checkmarkColor: kPrimaryColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Description',
                        prefixIcon: const Icon(Icons.description,
                            color: kPrimaryColor),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        hintText: '+923115428907',
                        prefixIcon:
                            const Icon(Icons.phone, color: kPrimaryColor),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _updateItem,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Update Item',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ==========================================
// ADD BANNER VIEW (Admin Only)
// ==========================================

class AddBannerView extends StatefulWidget {
  final String uniId;
  const AddBannerView({super.key, required this.uniId});

  @override
  State<AddBannerView> createState() => _AddBannerViewState();
}

class _AddBannerViewState extends State<AddBannerView> {
  final MarketplaceService _service = MarketplaceService();
  final _titleController = TextEditingController();
  Uint8List? _imageData;
  bool isLoading = false;

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() => _imageData = bytes);
    }
  }

  Future<void> _submitBanner() async {
    if (_imageData == null) {
      MySnackBar().mySnackBar(
        header: 'Error',
        content: 'Please select an image',
        bgColor: Colors.red.shade100,
      );
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      MySnackBar().mySnackBar(
        header: 'Error',
        content: 'Please enter a title',
        bgColor: Colors.red.shade100,
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final result = await _service.addBanner(
        uniId: widget.uniId,
        imageData: _imageData!,
        title: _titleController.text.trim(),
      );

      setState(() => isLoading = false);

      if (result == "Success") {
        Get.back();
        MySnackBar().mySnackBar(
          header: 'Success',
          content: 'Banner added successfully',
          bgColor: Colors.green.shade100,
        );
      } else {
        MySnackBar().mySnackBar(
          header: 'Error',
          content: result,
          bgColor: Colors.red.shade100,
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      MySnackBar().mySnackBar(
        header: 'Error',
        content: e.toString(),
        bgColor: Colors.red.shade100,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Banner'),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: kPrimaryColor, width: 2),
                      ),
                      child: _imageData == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate,
                                    size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 12),
                                Text(
                                  'Tap to add banner image',
                                  style: TextStyle(
                                      fontSize: 16, color: Colors.grey[600]),
                                ),
                              ],
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child:
                                  Image.memory(_imageData!, fit: BoxFit.cover),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Banner Title',
                      hintText: 'e.g., Winter Sale - 50% Off!',
                      prefixIcon:
                          const Icon(Icons.title, color: kPrimaryColor),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _submitBanner,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Add Banner',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }
}