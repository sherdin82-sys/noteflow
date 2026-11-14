import 'package:flutter/material.dart';

class AppColors {
  // Brand & Accents
  static const Color primary = Color(0xFF2563EB); // Vibrant cobalt/indigo
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color accent = Color(0xFF10B981); // Emerald accent for actions/success

  // Dark Theme Palette (Obsidian & Slate)
  static const Color darkBackground = Color(0xFF0F172A); // Deep slate
  static const Color darkSurface = Color(0xFF1E293B); // Elevated surface
  static const Color darkSurfaceVariant = Color(0xFF334155);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkBorderSubtle = Color(0x33475569);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextTertiary = Color(0xFF64748B);

  // Light Theme Palette (Porcelain & Snow)
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF1F5F9);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightBorderSubtle = Color(0x66CBD5E1);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF64748B);
  static const Color lightTextTertiary = Color(0xFF94A3B8);

  // Note Card Pastel Color Tints (Subtle, elegant)
  static const List<Color> lightNoteColors = [
    Color(0xFFFFFFFF), // Default pure white
    Color(0xFFF0FDF4), // Emerald green tint
    Color(0xFFEFF6FF), // Soft blue tint
    Color(0xFFFAF5FF), // Lavender purple tint
    Color(0xFFFFFBEB), // Amber warm tint
    Color(0xFFFFF1F2), // Rose soft tint
  ];

  static const List<Color> darkNoteColors = [
    Color(0xFF1E293B), // Default slate
    Color(0xFF142E25), // Subtle emerald dark
    Color(0xFF172554), // Subtle blue dark
    Color(0xFF2E1065), // Subtle purple dark
    Color(0xFF451A03), // Subtle amber dark
    Color(0xFF4C0519), // Subtle rose dark
  ];

  // Functional Status Colors
  static const Color pinColor = Color(0xFFF59E0B); // Warm amber pin
  static const Color archiveColor = Color(0xFF8B5CF6);
  static const Color danger = Color(0xFFEF4444);
}
