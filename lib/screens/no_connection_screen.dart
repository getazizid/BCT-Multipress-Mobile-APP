import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../config.dart';
import 'webview_screen.dart';

class NoConnectionScreen extends StatefulWidget {
  const NoConnectionScreen({super.key});

  @override
  State<NoConnectionScreen> createState() => _NoConnectionScreenState();
}

class _NoConnectionScreenState extends State<NoConnectionScreen> {
  bool _isChecking = false;

  Future<void> _retryConnection() async {
    setState(() {
      _isChecking = true;
    });

    // Small delay for natural UI response
    await Future.delayed(const Duration(milliseconds: 1200));

    final bool isConnected = await _checkInternetConnection();

    if (mounted) {
      setState(() {
        _isChecking = false;
      });

      if (isConnected) {
        // Navigate back to WebView
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const WebViewScreen()),
        );
      } else {
        // Show failure feedback
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Koneksi gagal. Cek kembali koneksi Anda."),
            backgroundColor: AppConfig.errorRed,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      
      final hasConnection = connectivityResult.contains(ConnectivityResult.mobile) ||
                            connectivityResult.contains(ConnectivityResult.wifi) ||
                            connectivityResult.contains(ConnectivityResult.ethernet) ||
                            connectivityResult.contains(ConnectivityResult.vpn);
                            
      if (!hasConnection) return false;

      // Web targets do not support InternetAddress.lookup, return true immediately if connected
      if (kIsWeb) return true;

      // Verify actual internet routing
      final result = await InternetAddress.lookup('google.com').timeout(
        const Duration(seconds: 4),
      );
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppConfig.errorGradient,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Animated or styled offline icon
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppConfig.errorRed.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.wifi_off_rounded,
                    size: 80,
                    color: AppConfig.errorRed.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 40),
                
                // Alert Teks
                const Text(
                  "Koneksi Terputus",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  "Cek koneksi internet Anda dan coba lagi untuk mengakses aplikasi.",
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withOpacity(0.6),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                
                // Retry Button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isChecking ? null : _retryConnection,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConfig.accentColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppConfig.accentColor.withOpacity(0.3),
                      elevation: 4,
                      shadowColor: AppConfig.accentColor.withOpacity(0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isChecking
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            "Coba Lagi",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
