import 'package:flutter/material.dart';

class AppColors {
  // Primary Pink Gradient Colors
  static const Color primaryPink = Color(0xFFE91E63);
  static const Color secondaryPink = Color(0xFFAD1457);
  static const Color lightPink = Color(0xFFF8BBD9);
  static const Color darkPink = Color(0xFF880E4F);
  
  // Gradient Definitions
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFE91E63), // Pink 500
      Color(0xFFAD1457), // Pink 700
      Color(0xFF880E4F), // Pink 900
    ],
    stops: [0.0, 0.6, 1.0],
  );
  
  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFFE91E63),
      Color(0xFFEC407A),
    ],
  );
  
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFF3E5F5), // Very light pink
      Color(0xFFFFFFFF), // White
      Color(0xFFF8BBD9), // Light pink
    ],
  );
  
  // Text Colors
  static const Color textDark = Color(0xFF212121);
  static const Color textLight = Color(0xFF757575);
  static const Color textWhite = Color(0xFFFFFFFF);
  
  // Additional Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFF44336);
  static const Color warning = Color(0xFFFF9800);

  static var backgroundGrey;

  static var darkBackground;
}
