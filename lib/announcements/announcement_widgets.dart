import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:convert';
import 'announcement_model.dart'; // Ensure this matches your file name

// ============================================================================
// THEME CONSTANTS
// ============================================================================
class AppTheme {
  static const Color kPrimaryColor = Color(0xFF6C63FF);
  static const Color kSecondaryColor = Color(0xFF4A90E2);
  static const Color kBackgroundColor = Color(0xFFF5F7FA);
  static const Color kDarkTextColor = Color(0xFF2D3142);
  static const Color kWhiteColor = Color(0xFFFFFFFF);

  static LinearGradient get primaryGradient => const LinearGradient(
    colors: [kPrimaryColor, Color(0xFF9C94FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// ============================================================================
// ANNOUNCEMENT CARD
// ============================================================================
class AnnouncementCard extends StatelessWidget {
  final Announcement announcement;
  final VoidCallback onTap;
  final bool isAdmin;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const AnnouncementCard({
    super.key,
    required this.announcement,
    required this.onTap,
    this.isAdmin = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.kWhiteColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.kDarkTextColor.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image or Gradient Header (base64 only)
            if (announcement.imageBase64 != null && announcement.imageBase64!.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Image.memory(
                  // ignore: argument_type_not_assignable
                  base64Decode(announcement.imageBase64!),
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              )
            else
              _buildGradientPlaceholder(),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (announcement.isNew)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'NEW', 
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
                      ),
                    ),
                  
                  Text(
                    announcement.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.kDarkTextColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "${announcement.createdAt.day}/${announcement.createdAt.month}/${announcement.createdAt.year}",
                    style: TextStyle(fontSize: 12, color: AppTheme.kDarkTextColor.withOpacity(0.6)),
                  ),
                  
                  // Admin Actions
                  if (isAdmin) ...[
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue), 
                          onPressed: onEdit
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red), 
                          onPressed: onDelete
                        ),
                      ],
                    )
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientPlaceholder() {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Center(
        child: Icon(Icons.campaign, size: 40, color: Colors.white.withOpacity(0.8)),
      ),
    );
  }
}

// ============================================================================
// MASONRY GRID RENDERER (FIXED)
// ============================================================================

class SliverMasonryGrid extends SliverMultiBoxAdaptorWidget {
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  const SliverMasonryGrid.count({
    super.key,
    required this.crossAxisCount,
    required this.mainAxisSpacing,
    required this.crossAxisSpacing,
    required super.delegate,
  });

  @override
  SliverMultiBoxAdaptorElement createElement() => SliverMultiBoxAdaptorElement(this);

  @override
  RenderSliverMasonryGrid createRenderObject(BuildContext context) {
    final element = context as SliverMultiBoxAdaptorElement;
    return RenderSliverMasonryGrid(
      childManager: element,
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSliverMasonryGrid renderObject) {
    renderObject
      ..crossAxisCount = crossAxisCount
      ..mainAxisSpacing = mainAxisSpacing
      ..crossAxisSpacing = crossAxisSpacing;
  }
}

class RenderSliverMasonryGrid extends RenderSliverMultiBoxAdaptor {
  RenderSliverMasonryGrid({
    required super.childManager,
    required int crossAxisCount,
    required double mainAxisSpacing,
    required double crossAxisSpacing,
  })  : _crossAxisCount = crossAxisCount,
        _mainAxisSpacing = mainAxisSpacing,
        _crossAxisSpacing = crossAxisSpacing;

  int _crossAxisCount;
  double _mainAxisSpacing;
  double _crossAxisSpacing;

  int get crossAxisCount => _crossAxisCount;
  set crossAxisCount(int value) {
    if (_crossAxisCount != value) {
      _crossAxisCount = value;
      markNeedsLayout();
    }
  }

  double get mainAxisSpacing => _mainAxisSpacing;
  set mainAxisSpacing(double value) {
    if (_mainAxisSpacing != value) {
      _mainAxisSpacing = value;
      markNeedsLayout();
    }
  }

  double get crossAxisSpacing => _crossAxisSpacing;
  set crossAxisSpacing(double value) {
    if (_crossAxisSpacing != value) {
      _crossAxisSpacing = value;
      markNeedsLayout();
    }
  }

  // --- FIXED: Use SliverGridParentData to store X/Y positions ---
  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SliverGridParentData) {
      child.parentData = SliverGridParentData();
    }
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    final childConstraints = constraints.asBoxConstraints();
    
    final totalCrossAxisSpacing = crossAxisSpacing * (crossAxisCount - 1);
    final childWidth = (childConstraints.maxWidth - totalCrossAxisSpacing) / crossAxisCount;
    
    final columnHeights = List<double>.filled(crossAxisCount, 0);
    
    RenderBox? child = firstChild;
    
    while (child != null) {
      child.layout(
        BoxConstraints(minWidth: childWidth, maxWidth: childWidth),
        parentUsesSize: true,
      );
      
      final shortestColumn = columnHeights.indexOf(columnHeights.reduce((a, b) => a < b ? a : b));
      
      // --- FIXED: Cast to SliverGridParentData to access layoutOffset/crossAxisOffset ---
      final childParentData = child.parentData as SliverGridParentData;
      
      // Calculate Cross Axis (X) and Main Axis (Y)
      childParentData.crossAxisOffset = shortestColumn * (childWidth + crossAxisSpacing);
      childParentData.layoutOffset = columnHeights[shortestColumn];
      
      columnHeights[shortestColumn] += child.size.height + mainAxisSpacing;
      child = childAfter(child);
    }
    
    final maxHeight = columnHeights.reduce((a, b) => a > b ? a : b);
    
    geometry = SliverGeometry(
      scrollExtent: maxHeight,
      paintExtent: maxHeight.clamp(0, constraints.remainingPaintExtent),
      maxPaintExtent: maxHeight,
    );
  }

  // --- FIXED: Override paint to draw children at calculated offsets ---
  @override
  void paint(PaintingContext context, Offset offset) {
    if (firstChild == null) return;
    
    // Custom painting loop for grid items
    RenderBox? child = firstChild;
    while (child != null) {
      final SliverGridParentData childParentData = child.parentData! as SliverGridParentData;
      // Combine the Sliver's offset with the child's calculated position
      context.paintChild(child, offset + Offset(childParentData.crossAxisOffset!, childParentData.layoutOffset!));
      child = childAfter(child);
    }
  }
}