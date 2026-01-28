import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../shared.dart';
import '../poster/marketplace_poster_slideshow.dart';
import '../announcements/student_announcement_view.dart';
import '../notifications.dart';

// --- IMPORT GLOBAL THEME ---
import '../theme_colors.dart';

/// Modern Home/Dashboard Module - Redesigned for Eduverse
class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class ModuleItem {
  final String title;
  final String description;
  final IconData icon;
  final List<Color> gradientColors;
  final String? route;
  final bool isActive;

  ModuleItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.gradientColors,
    this.route,
    this.isActive = true,
  });
}

class _HomeDashboardState extends State<HomeDashboard> {
  String userName = 'User';
  String userRole = 'student';
  String? userUniId;
  int _unreadCount = 0;
  final NotificationService _notificationService = NotificationService();

  // PageView controller for header carousel
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _startAutoSlide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoSlide() {
    _timer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_pageController.hasClients) {
        int nextPage = (_currentPage + 1) % 3;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _loadUserName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>?;
          if (!mounted) return;
          setState(() {
            userName = data?['name'] ?? 'User';
            userRole = data?['role'] ?? 'student';
            userUniId = data?['uniId']?.toString();
          });
          // load unread notifications count
          _loadUnreadCount();
        }
      }
    } catch (e) {
      debugPrint('Error loading user name: $e');
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && userUniId != null) {
        final count = await _notificationService.getUnreadCount(user.uid, userUniId!);
        if (mounted) setState(() => _unreadCount = count);
      }
    } catch (e) {
      debugPrint('Error loading unread count: $e');
    }
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              FirebaseAuth.instance.signOut();
              Navigator.pop(context);
              Get.offAllNamed('/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic Theme Variables
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = getAppBackgroundColor(context);
    final textColor = getAppTextColor(context);
    final appBarBg = isDark ? kDarkBackgroundColor : Colors.white;
    final appBarFg = isDark ? Colors.white : AppColors.darkGrey;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Custom App Bar
            SliverAppBar(
              expandedHeight: 0,
              floating: true,
              pinned: true,
              elevation: 0,
              backgroundColor: appBarBg,
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.mainColor, AppColors.lightMainColor],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        const Icon(Icons.school, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Eduverse',
                    style: TextStyle(
                      color: appBarFg,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
              
              actions: [
                if (userRole == 'admin' || userRole == 'super_admin')
                  IconButton(
                    icon: const Icon(Icons.admin_panel_settings,
                        color: AppColors.mainColor),
                    onPressed: () => Get.toNamed('/admin'),
                  ),
                // Notifications icon with badge
                IconButton(
                  icon: Stack(
                    children: [
                      Icon(Icons.notifications, size: 24, color: appBarFg),
                      if (_unreadCount > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                            child: Text(
                              _unreadCount > 99 ? '99+' : '$_unreadCount',
                              style: const TextStyle(color: Colors.white, fontSize: 10),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onPressed: () {
                    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                    Get.toNamed('/notifications', arguments: {'userId': uid, 'universityId': userUniId ?? ''})?.then((_) => _loadUnreadCount());
                  },
                ),
                IconButton(
                  icon: Icon(Icons.person, color: appBarFg),
                  onPressed: () => Get.toNamed('/profile'),
                ),
                  
                // IconButton(
                //   icon: const Icon(Icons.logout, color: AppColors.darkGrey),
                //   onPressed: _logout,
                // ),
              ],
            ),

            // Header Carousel with Greeting
            SliverToBoxAdapter(
              child: _buildHeaderCarousel(),
            ),

            // Marketplace poster slideshow (banners)
            SliverToBoxAdapter(
              child: MarketplacePosterSlideshow(),
            ),

            // Modules Grid
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 4,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.mainColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Your Modules',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildModulesGrid(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCarousel() {
    final slides = [
      _buildSlide(
        title: 'Welcome to Eduverse',
        subtitle: 'Your all-in-one university companion',
        icon: Icons.waving_hand,
        colors: [AppColors.mainColor, AppColors.lightMainColor],
      ),
      _buildSlide(
        title: 'Stay Updated',
        subtitle: 'Check latest university news & events',
        icon: Icons.newspaper,
        colors: [Color(0xFF9B59B6), Color(0xFFBB8FCE)],
      ),
      _buildSlide(
        title: 'Exam Season',
        subtitle: 'View your schedules & prepare smart',
        icon: Icons.calendar_today,
        colors: [Color(0xFFE74C3C), Color(0xFFEC7063)],
      ),
    ];

    return Column(
      children: [
        SizedBox(
          height: 190,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemCount: slides.length,
            itemBuilder: (context, index) => slides[index],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            slides.length,
            (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _currentPage == index ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: _currentPage == index
                    ? AppColors.mainColor
                    : AppColors.slateGrey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSlide({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> colors,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colors[0].withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
          ),
          // Content - make adaptive to avoid vertical overflow on small screens
          Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hello, $userName! 👋',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.95),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<ModuleItem> get _modules => [
        ModuleItem(
          title: 'Timetable',
          description: 'View your class schedule',
          icon: Icons.schedule,
          gradientColors: [Color(0xFF3498DB), Color(0xFF5FA2DD)],
          route: '/timetable',
        ),
        ModuleItem(
          title: 'Lost & Found',
          description: 'Browse lost items',
          icon: Icons.search,
          gradientColors: [Color(0xFFE67E22), Color(0xFFF39C12)],
          route: '/lost-and-found',
        ),
        ModuleItem(
          title: 'AI Study Planner',
          description: 'Smart study assistant',
          icon: Icons.auto_awesome,
          gradientColors: [Color(0xFF9B59B6), Color(0xFFBB8FCE)],
          route: '/ai-study-planner',
        ),
        ModuleItem(
          title: 'Placement',
          description: 'Placement & Internships',
          icon: Icons.work_outline,
          gradientColors: [Color(0xFF5E2686), Color(0xFF7D3FA0)],
          route: '/student-placement',
        ),
        ModuleItem(
          title: 'Faculty Connect',
          description: 'Connect with your university faculty',
          icon: Icons.school,
          gradientColors: [Color(0xFF16A085), Color(0xFF1ABC9C)],
          route: '/faculty-connect',
        ),
        ModuleItem(
          title: 'Complaint System',
          description: 'Report issues',
          icon: Icons.report_problem,
          gradientColors: [Color(0xFFF39C12), Color(0xFFF1C40F)],
          route: '/complaints',
        ),
        ModuleItem(
          title: 'Marketplace',
          description: 'Buy & sell items',
          icon: Icons.shopping_bag,
          gradientColors: [Color(0xFF27AE60), Color(0xFF2ECC71)],
          route: '/marketplace',
        ),
        ModuleItem(
          title: 'Announcements',
          description: 'Campus announcements & events',
          icon: Icons.announcement,
          gradientColors: [Color(0xFF2980B9), Color(0xFF3498DB)],
          route: '/student_announcements_view',
        ),
      ];

  Widget _buildModulesGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.95,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _modules.length,
      itemBuilder: (context, index) {
        return _buildModuleCard(_modules[index]);
      },
    );
  }

  Widget _buildModuleCard(ModuleItem module) {
    // Theme Colors for Card
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // ✅ FIX: Transparent Light Card in Dark Mode (like your other screens)
    final cardColor = isDark ? Colors.white.withOpacity(0.1) : Colors.white;
    final titleColor = isDark ? Colors.white : AppColors.darkGrey;
    final descColor = isDark ? Colors.white70 : AppColors.smallText;

    return GestureDetector(
      onTap: () {
        try {
          if (module.route != null) {
            // Special-case Complaints: route admin users to admin view
            if (module.route == '/complaints') {
              final role = userRole;
              final isAdmin = role == 'admin' || role == 'super_admin';
              if (isAdmin) {
                Get.toNamed('/complaints/admin');
              } else {
                Get.toNamed('/complaints');
              }
              return;
            }

            debugPrint('Module tap: navigating to ${module.route}');

            // Safe-path for announcements route to avoid name lookup issues
            if (module.route == '/student_announcements_view' || module.route == '/announcements') {
              Get.to(() => const StudentAnnouncementFeed());
              return;
            }

            Get.toNamed(module.route!);
          } else {
            Get.snackbar(
              'Coming Soon',
              '${module.title} is under development',
              backgroundColor: isDark ? kDarkBackgroundColor : Colors.white,
              colorText: isDark ? Colors.white : AppColors.darkGrey,
              borderRadius: 12,
              margin: const EdgeInsets.all(16),
              snackPosition: SnackPosition.BOTTOM,
              icon: Icon(module.icon, color: module.gradientColors[0]),
              duration: const Duration(seconds: 2),
            );
          }
        } catch (e, s) {
          debugPrint('Navigation error: $e');
          debugPrint('$s');
          Get.snackbar('Navigation error', e.toString(), backgroundColor: Colors.white);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.transparent : module.gradientColors[0].withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Gradient background (subtle)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 80,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      module.gradientColors[0].withOpacity(0.1),
                      module.gradientColors[1].withOpacity(0.05),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon container
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: module.gradientColors,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: module.gradientColors[0].withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      module.icon,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Title
                  Text(
                    module.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Description (larger and allow extra line)
                  Text(
                    module.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: descColor,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            // Coming soon badge (optional)
            if (module.route == null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.lightYellow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Soon',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGrey,
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