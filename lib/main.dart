import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'config.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock app orientation to Portrait for consistent mobile website layout
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: AppConfig.primaryStart,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppConfig.primaryStart,
          primary: AppConfig.primaryStart,
          secondary: AppConfig.accentColor,
        ),
        // Premium fonts configurations
        fontFamily: 'Outfit',
      ),
      home: const SplashScreen(),
    );
  }
}
