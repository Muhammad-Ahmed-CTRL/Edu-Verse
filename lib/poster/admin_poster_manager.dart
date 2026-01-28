import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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

class AdminPosterManager extends StatefulWidget {
  const AdminPosterManager({Key? key}) : super(key: key);

  @override
  State<AdminPosterManager> createState() => _AdminPosterManagerState();
}

class _AdminPosterManagerState extends State<AdminPosterManager> {
  List<PosterModel> posters = [];
  bool isLoading = true;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    loadPosters();
  }

  Future<void> loadPosters() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final postersJson = prefs.getString('marketplace_posters');
      if (postersJson != null) {
        final List<dynamic> decoded = json.decode(postersJson);
        setState(() {
          posters = decoded.map((e) => PosterModel.fromJson(e)).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading posters: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> savePosters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final postersJson = json.encode(posters.map((e) => e.toJson()).toList());
      await prefs.setString('marketplace_posters', postersJson);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Posters saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving posters: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> addPosterFromImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64Image = base64Encode(bytes);

        setState(() {
          posters.add(PosterModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            imageBase64: base64Image,
          ));
        });
        await savePosters();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding poster: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void updatePoster(String id, String field, dynamic value) {
    setState(() {
      final index = posters.indexWhere((p) => p.id == id);
      if (index != -1) {
        switch (field) {
          case 'title':
            posters[index].title = value;
            break;
          case 'description':
            posters[index].description = value;
            break;
          case 'link':
            posters[index].link = value;
            break;
          case 'active':
            posters[index].active = value;
            break;
        }
      }
    });
  }

  void deletePoster(String id) {
    setState(() {
      posters.removeWhere((p) => p.id == id);
    });
    savePosters();
  }

  void showPreview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PosterPreviewScreen(posters: posters),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace Poster Manager'),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility),
            onPressed: showPreview,
            tooltip: 'Preview',
          ),
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: savePosters,
            tooltip: 'Save All',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : posters.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: posters.length,
                  itemBuilder: (context, index) =>
                      _buildPosterCard(posters[index]),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addPosterFromImage,
        icon: const Icon(Icons.add),
        label: const Text('Add Poster'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No posters yet',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first poster to get started!',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildPosterCard(PosterModel poster) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image Preview
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    base64Decode(poster.imageBase64),
                    width: 150,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 16),
                // Form Fields
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        controller: TextEditingController(text: poster.title)
                          ..selection = TextSelection.collapsed(
                            offset: poster.title.length,
                          ),
                        onChanged: (value) =>
                            updatePoster(poster.id, 'title', value),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 2,
                        controller:
                            TextEditingController(text: poster.description)
                              ..selection = TextSelection.collapsed(
                                offset: poster.description.length,
                              ),
                        onChanged: (value) =>
                            updatePoster(poster.id, 'description', value),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Link URL (optional)',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.link),
              ),
              controller: TextEditingController(text: poster.link)
                ..selection = TextSelection.collapsed(
                  offset: poster.link.length,
                ),
              onChanged: (value) => updatePoster(poster.id, 'link', value),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: poster.active,
                      onChanged: (value) =>
                          updatePoster(poster.id, 'active', value ?? true),
                    ),
                    const Text('Active'),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => deletePoster(poster.id),
                  icon: const Icon(Icons.delete, size: 18),
                  label: const Text('Delete'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PosterPreviewScreen extends StatefulWidget {
  final List<PosterModel> posters;

  const PosterPreviewScreen({Key? key, required this.posters})
      : super(key: key);

  @override
  State<PosterPreviewScreen> createState() => _PosterPreviewScreenState();
}

class _PosterPreviewScreenState extends State<PosterPreviewScreen> {
  int currentSlide = 0;
  late List<PosterModel> activePosters;

  @override
  void initState() {
    super.initState();
    activePosters = widget.posters.where((p) => p.active).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview Mode'),
      ),
      body: activePosters.isEmpty
          ? const Center(child: Text('No active posters to preview'))
          : Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 800),
                padding: const EdgeInsets.all(16),
                child: _buildSlideshow(),
              ),
            ),
    );
  }

  Widget _buildSlideshow() {
    final poster = activePosters[currentSlide];

    return Card(
      elevation: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(4)),
                child: Image.memory(
                  base64Decode(poster.imageBase64),
                  height: 400,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              if (activePosters.length > 1) ...[
                Positioned(
                  left: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton(
                      icon: const Icon(Icons.chevron_left, size: 32),
                      onPressed: () => setState(() {
                        currentSlide = currentSlide > 0
                            ? currentSlide - 1
                            : activePosters.length - 1;
                      }),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton(
                      icon: const Icon(Icons.chevron_right, size: 32),
                      onPressed: () => setState(() {
                        currentSlide =
                            (currentSlide + 1) % activePosters.length;
                      }),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ),
                ),
              ],
              if (poster.title.isNotEmpty || poster.description.isNotEmpty)
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
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (poster.title.isNotEmpty)
                          Text(
                            poster.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        if (poster.description.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            poster.description,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (activePosters.length > 1)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  activePosters.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: index == currentSlide ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: index == currentSlide
                          ? Theme.of(context).primaryColor
                          : Colors.grey[300],
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
}
