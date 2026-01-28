import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';

// --- Poster Model (Unchanged) ---
class PosterModel {
  String id;
  String imageBase64;
  String title;
  String description;
  String link;
  bool active;

  PosterModel({
    required this.id,
    required this.imageBase64,
    this.title = '',
    this.description = '',
    this.link = '',
    this.active = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'imageBase64': imageBase64,
        'title': title,
        'description': description,
        'link': link,
        'active': active,
      };

  factory PosterModel.fromJson(Map<String, dynamic> json) => PosterModel(
        id: json['id'],
        imageBase64: json['imageBase64'],
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        link: json['link'] ?? '',
        active: json['active'] ?? true,
      );
}

// --- Slideshow Widget ---
class MarketplacePosterSlideshow extends StatefulWidget {
  const MarketplacePosterSlideshow({Key? key}) : super(key: key);

  @override
  State<MarketplacePosterSlideshow> createState() =>
      _MarketplacePosterSlideshowState();
}

class _MarketplacePosterSlideshowState
    extends State<MarketplacePosterSlideshow> {
  List<PosterModel> posters = [];
  int currentSlide = 0;
  bool isAutoPlaying = true;
  Timer? _autoPlayTimer;
  late PageController _pageController;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    loadPosters();
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> loadPosters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final postersJson = prefs.getString('marketplace_posters');

      if (postersJson != null) {
        final List<dynamic> decoded = json.decode(postersJson);
        final allPosters = decoded.map((e) => PosterModel.fromJson(e)).toList();

        if (mounted) {
          setState(() {
            posters = allPosters.where((p) => p.active).toList();
            isLoading = false;
          });
        }

        // Only start autoplay if we have more than 1 poster
        if (posters.length > 1) {
          startAutoPlay();
        }
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading posters: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  void startAutoPlay() {
    _autoPlayTimer?.cancel();
    if (posters.length <= 1) return;

    debugPrint('Starting Autoplay');
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // If user has manually paused it (by touching), skip this tick
      if (!isAutoPlaying) return;

      final next = (currentSlide + 1) % posters.length;

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
        // Note: We do NOT set currentSlide here.
        // onPageChanged handles the state update to keep dots in sync.
      }
    });
  }

  void stopAutoPlay() {
    _autoPlayTimer?.cancel();
  }

  // Called when user swipes manually
  void onPageChanged(int index) {
    setState(() {
      currentSlide = index;
    });
  }

  // Helper to pause timer when user touches the screen
  void _onPanDown(DragDownDetails details) {
    setState(() => isAutoPlaying = false);
    stopAutoPlay();
  }

  // Helper to resume timer when user lifts finger
  void _onPanCancel() {
    setState(() => isAutoPlaying = true);
    startAutoPlay();
  }

  Future<void> handlePosterTap(PosterModel poster) async {
    if (poster.link.isNotEmpty) {
      final uri = Uri.parse(poster.link);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (posters.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16),
      constraints: const BoxConstraints(maxWidth: 1200),
      child: Column(
        children: [
          // 1. The Slideshow Area
          _buildSlideshow(),

          const SizedBox(height: 12),

          // 2. The Dots (Under the poster)
          if (posters.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                posters.length,
                (index) => GestureDetector(
                  onTap: () {
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                    );
                    // Reset autoplay timer on manual click
                    stopAutoPlay();
                    startAutoPlay();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width:
                        index == currentSlide ? 24 : 8, // Made active dot wider
                    height: 8,
                    decoration: BoxDecoration(
                      color: index == currentSlide
                          ? Colors.blueAccent
                          : Colors.grey.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSlideshow() {
    return Card(
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        height: 320,
        // NotificationListener detects user swipes to pause autoplay
        child: GestureDetector(
          onPanDown: _onPanDown,
          onPanCancel: _onPanCancel,
          onPanEnd: (_) => _onPanCancel(),
          child: PageView.builder(
            controller: _pageController,
            itemCount: posters.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, i) {
              final p = posters[i];
              return GestureDetector(
                onTap: () => handlePosterTap(p),
                child: Stack(
                  children: [
                    // Background Image
                    SizedBox.expand(
                      child: p.imageBase64.isNotEmpty
                          ? Image.memory(
                              base64Decode(p.imageBase64),
                              fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) =>
                                  const Center(child: Icon(Icons.broken_image)),
                            )
                          : Container(color: Colors.grey[300]),
                    ),

                    // Gradient Overlay
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 200,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.7),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Text Content
                    if (p.title.isNotEmpty || p.description.isNotEmpty)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (p.title.isNotEmpty)
                                Text(
                                  p.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    shadows: [
                                      Shadow(
                                        offset: Offset(0, 1),
                                        blurRadius: 3,
                                        color: Colors.black45,
                                      ),
                                    ],
                                  ),
                                ),
                              if (p.description.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  p.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    shadows: [
                                      Shadow(
                                        offset: Offset(0, 1),
                                        blurRadius: 3,
                                        color: Colors.black45,
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
              );
            },
          ),
        ),
      ),
    );
  }
}
