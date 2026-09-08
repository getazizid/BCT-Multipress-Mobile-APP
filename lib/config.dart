import 'package:flutter/material.dart';

class AppConfig {
  // === CONFIGURABLE PARAMETERS ===
  
  // The mobile website URL to be loaded in the app
  // You can change this URL to point to your target website.
  static const String targetUrl = "https://bct.getaziz.id";
  
  // Name of the application
  static const String appName = "BCT Multipress";

  // Subtitle of the application (displayed on Splash screen)
  static const String appSubtitle = "Sistem Manajemen BCT Multipress";
  
  // Package name for Google Play Store matching build.gradle (if customized)
  static const String packageName = "com.bct.mobileapp";
  
  // Splash Screen Display Duration (in milliseconds)
  static const int splashDurationMs = 3000;
  
  // === DESIGN SYSTEM (PREMIUM AESTHETICS) ===
  
  // Splash and overall primary theme gradient colors (Matching uploaded image)
  static const Color primaryStart = Color(0xFF1E5FD2); // Lighter vibrant blue
  static const Color primaryEnd = Color(0xFF09142E); // Dark deep midnight blue
  
  // Accent color (used for buttons and highlights)
  static const Color accentColor = Color(0xFF1E5FD2); // Vibrant blue for the button
  
  // Secondary text and error colors
  static const Color textDark = Color(0xFF0F172A); // Dark slate grey for text
  static const Color textLight = Colors.white; // White for text
  static const Color errorRed = Color(0xFFEF4444); // Error red
  
  // Background gradient for splash screen
  static const Gradient splashGradient = LinearGradient(
    colors: [primaryStart, primaryEnd],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
  
  // Background gradient for error/no-connection page
  static const Gradient errorGradient = LinearGradient(
    colors: [primaryStart, primaryEnd],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
