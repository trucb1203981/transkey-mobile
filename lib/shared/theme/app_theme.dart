import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  // Brand
  static const primary = Color(0xFF6C63FF);
  static const primaryDark = Color(0xFF5A52E0);

  // Backgrounds
  static const bgDark = Color(0xFF0E0E11);
  static const bgLight = Color(0xFFF5F2EE);
  static const surface = Color(0xFF16161A);
  static const surfaceLight = Color(0xFFFFFFFF);

  // Text
  static const textPrimary = Color(0xFFE8E8F0);
  static const textPrimaryLight = Color(0xFF1A1A2E);
  static const textSecondary = Color(0xFF8888A0);
  static const textSecondaryLight = Color(0xFF6B7280);

  // Status
  static const green = Color(0xFF43E97B);
  static const red = Color(0xFFFF6B6B);
  static const amber = Color(0xFFF59E0B);

  // Border
  static const border = Color(0xFF2A2A35);
  static const borderLight = Color(0xFFE5E1DB);

  // Overlay
  static const overlay = Color(0x80000000);
}

class AppSpacing {
  const AppSpacing._();

  static const double cardRadius = 16;
  static const double buttonRadius = 12;
  static const double sheetRadius = 24;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppTheme {
  const AppTheme._();

  static ThemeData dark() {
    return _buildTheme(brightness: Brightness.dark);
  }

  static ThemeData light() {
    return _buildTheme(brightness: Brightness.light);
  }

  static ThemeData _buildTheme({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primary,
      onSecondary: Colors.white,
      error: AppColors.red,
      onError: Colors.white,
      surface: isDark ? AppColors.surface : AppColors.surfaceLight,
      onSurface: isDark ? AppColors.textPrimary : AppColors.textPrimaryLight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
      cardTheme: CardThemeData(
        color: isDark ? AppColors.surface : AppColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          side: BorderSide(
            color: isDark ? AppColors.border : AppColors.borderLight,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.bgDark : AppColors.bgLight,
        foregroundColor: isDark ? AppColors.textPrimary : AppColors.textPrimaryLight,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          side: const BorderSide(color: AppColors.primary),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.surface : const Color(0xFFF0EDE8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: const BorderSide(color: AppColors.red, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: TextStyle(
          color: isDark ? AppColors.textSecondary : AppColors.textSecondaryLight,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.surface : AppColors.surfaceLight,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.sheetRadius),
          ),
        ),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: isDark ? AppColors.textPrimary : AppColors.textPrimaryLight,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.textPrimary : AppColors.textPrimaryLight,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.textPrimary : AppColors.textPrimaryLight,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: isDark ? AppColors.textPrimary : AppColors.textPrimaryLight,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: isDark ? AppColors.textPrimary : AppColors.textPrimaryLight,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.textSecondary : AppColors.textSecondaryLight,
        ),
      ),
      iconTheme: IconThemeData(
        color: isDark ? AppColors.textPrimary : AppColors.textPrimaryLight,
        size: 24,
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.border : AppColors.borderLight,
        thickness: 1,
      ),
    );
  }
}
