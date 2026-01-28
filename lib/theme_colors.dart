import 'package:flutter/material.dart';

// ============================================================================
// 🎨 GLOBAL COLOR PALETTE (The "Ingredients")
// ============================================================================

// Brand Colors
const Color kPrimaryColor = Color(0xFF6C63FF);      // Purple
const Color kSecondaryColor = Color(0xFF4A90E2);    // Blue

// Backgrounds
const Color kBackgroundColor = Color(0xFFF5F7FA);   // Light Mode BG
const Color kDarkBackgroundColor = Color(0xFF2D2557); // Dark Mode BG

// Text & Surfaces
const Color kWhiteColor = Colors.white;
const Color kDarkTextColor = Color(0xFF2D3142);     // Dark Text (for Light Mode)
const Color kLightTextColor = Colors.white;         // Light Text (for Dark Mode)

// ============================================================================
// 🧠 SMART HELPERS (Use these in your Widgets!)
// ============================================================================

/// Returns the correct background color based on the current Theme Mode
Color getAppBackgroundColor(BuildContext context) {
  // If the app is in Dark Mode, return the Dark BG. Otherwise, return Light BG.
  return Theme.of(context).brightness == Brightness.dark 
      ? kDarkBackgroundColor 
      : kBackgroundColor;
}

/// Returns the correct text color based on the current Theme Mode
Color getAppTextColor(BuildContext context) {
  // If in Dark Mode, text should be White. Otherwise, Dark Grey.
  return Theme.of(context).brightness == Brightness.dark 
      ? kLightTextColor 
      : kDarkTextColor;
}

/// Returns the correct Card/Surface color
Color getAppCardColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark 
      ? kDarkBackgroundColor.withOpacity(0.8) 
      : kWhiteColor;
}