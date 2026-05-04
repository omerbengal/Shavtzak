import 'package:flutter/material.dart';

/// App theme configuration with RTL and Hebrew support
class AppTheme {
  // Primary colors
  static const Color primary = Color(0xFF2196F3); // Blue
  static const Color primaryDark = Color(0xFF1976D2);
  static const Color primaryLight = Color(0xFFBBDEFB);

  // Accent colors
  static const Color accent = Color(0xFFFF9800); // Orange
  static const Color accentDark = Color(0xFFF57C00);
  static const Color accentLight = Color(0xFFFFE0B2);

  // Semantic colors
  static const Color success = Color(0xFF4CAF50); // Green
  static const Color warning = Color(0xFFFFC107); // Amber
  static const Color error = Color(0xFFF44336); // Red
  static const Color info = Color(0xFF2196F3); // Blue

  // Neutral colors
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE0E0E0);

  // Text colors
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textDisabled = Color(0xFFBDBDBD);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const List<String> hebrewFontFallback = [
    'Noto Sans Hebrew',
    'Arial',
    'sans-serif',
  ];

  /// Light theme with RTL support
  static ThemeData get lightTheme {
    return ThemeData(
      // Font family for Hebrew support
      fontFamily: 'Rubik',
      fontFamilyFallback: hebrewFontFallback,

      // Color scheme
      colorScheme: ColorScheme.light(
        primary: primary,
        primaryContainer: primaryLight,
        secondary: accent,
        secondaryContainer: accentLight,
        surface: surface,
        error: error,
        onPrimary: textOnPrimary,
        onSecondary: textOnPrimary,
        onSurface: textPrimary,
        onError: textOnPrimary,
      ),

      // Scaffold
      scaffoldBackgroundColor: background,

      // AppBar theme
      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: textOnPrimary,
        elevation: 2,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textOnPrimary,
        ),
        iconTheme: IconThemeData(color: textOnPrimary),
      ),

      // Card theme
      cardTheme: CardThemeData(
        elevation: 2,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: textOnPrimary,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Rubik',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Text button theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: const TextStyle(
            fontFamily: 'Rubik',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Outlined button theme
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Rubik',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: error, width: 2),
        ),
        labelStyle: const TextStyle(
          fontFamily: 'Rubik',
          color: textSecondary,
          fontSize: 16,
        ),
        hintStyle: const TextStyle(
          fontFamily: 'Rubik',
          color: textDisabled,
          fontSize: 16,
        ),
      ),

      // Chip theme
      chipTheme: ChipThemeData(
        backgroundColor: primaryLight,
        deleteIconColor: textSecondary,
        labelStyle: const TextStyle(
          fontFamily: 'Rubik',
          color: textPrimary,
          fontSize: 14,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // Divider theme
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),

      // List tile theme
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minLeadingWidth: 40,
      ),

      // Dialog theme
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'Rubik',
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Rubik',
          color: textSecondary,
          fontSize: 16,
        ),
      ),

      // Floating action button theme
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: textOnPrimary,
        elevation: 4,
      ),

      // Icon theme
      iconTheme: const IconThemeData(
        color: textSecondary,
        size: 24,
      ),

      // Text theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        displayMedium: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        displaySmall: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: textPrimary,
        ),
        headlineLarge: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        headlineSmall: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        titleSmall: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 16,
          color: textPrimary,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 14,
          color: textPrimary,
        ),
        bodySmall: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 12,
          color: textSecondary,
        ),
        labelLarge: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        labelMedium: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textSecondary,
        ),
        labelSmall: TextStyle(
          fontFamily: 'Rubik',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textDisabled,
        ),
      ),

      // Material 3
      useMaterial3: true,
    );
  }

  /// Get color for event status
  static Color getStatusColor(String status) {
    switch (status) {
      case 'confirmed':
        return success;
      case 'draft':
        return warning;
      case 'cancelled':
        return error;
      case 'completed':
        return textSecondary;
      default:
        return textSecondary;
    }
  }

  /// Get color for assignment status
  static Color getAssignmentStatusColor(String status) {
    switch (status) {
      case 'confirmed':
        return success;
      case 'pending':
        return warning;
      case 'declined':
        return error;
      default:
        return textSecondary;
    }
  }

  /// Get color for role (can be extended with golden ratio algorithm later)
  static Color getRoleColor(String roleKey, {int index = 0}) {
    // For now, use simple color rotation
    final colors = [
      const Color(0xFF2196F3), // Blue
      const Color(0xFF4CAF50), // Green
      const Color(0xFFFF9800), // Orange
      const Color(0xFF9C27B0), // Purple
      const Color(0xFFF44336), // Red
      const Color(0xFF00BCD4), // Cyan
      const Color(0xFFFFEB3B), // Yellow
      const Color(0xFF795548), // Brown
      const Color(0xFFE91E63), // Pink
      const Color(0xFF3F51B5), // Indigo
      const Color(0xFF8BC34A), // Light Green
      const Color(0xFFFF5722), // Deep Orange
      const Color(0xFF673AB7), // Deep Purple
      const Color(0xFF009688), // Teal
      const Color(0xFFCDDC39), // Lime
      const Color(0xFF607D8B), // Blue Grey
    ];

    return colors[index % colors.length];
  }
}
