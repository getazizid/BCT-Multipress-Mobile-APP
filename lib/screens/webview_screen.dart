import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../config.dart';
import 'no_connection_screen.dart';
import 'splash_screen.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController? _controller;
  int _loadingProgress = 0;
  bool _isLoading = true;
  bool _canGoBack = false;
  
  // Connectivity monitoring
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _isCurrentlyConnected = true;

  // Deduplication control for downloads
  String _lastDownloadKey = '';
  int _lastDownloadTime = 0;

  bool _isDuplicateDownload(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (key.isNotEmpty && key == _lastDownloadKey && (now - _lastDownloadTime) < 3000) {
      debugPrint("Ignoring duplicate download for key: $key");
      return true;
    }
    _lastDownloadKey = key;
    _lastDownloadTime = now;
    return false;
  }

  @override
  void initState() {
    super.initState();
    
    // Initialize WebViewController ONLY if not running on Web (prevents assertion crash in Chrome)
    if (!kIsWeb) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..addJavaScriptChannel(
          'PrintChannel',
          onMessageReceived: (JavaScriptMessage message) {
            if (message.message == 'print') {
              _handlePrint();
            }
          },
        )
        ..addJavaScriptChannel(
          'DownloadChannel',
          onMessageReceived: (JavaScriptMessage message) {
            try {
              final Map<String, dynamic> data = jsonDecode(message.message);
              if (data['action'] == 'external_launch') {
                final String targetUrl = data['url'] ?? '';
                if (targetUrl.isNotEmpty) {
                  _launchExternalUrl(targetUrl);
                }
                return;
              }
              if (data['action'] == 'save_base64') {
                final String base64Data = data['data'] ?? '';
                final String filename = data['filename'] ?? '';
                if (base64Data.isNotEmpty) {
                  _handleSaveBase64Data(base64Data, suggestedFilename: filename);
                }
                return;
              }
              final String fileUrl = data['url'] ?? '';
              final String filename = data['filename'] ?? '';
              if (fileUrl.isNotEmpty) {
                _triggerFetchInWebView(fileUrl, suggestedFilename: filename);
              }
            } catch (e) {
              _handleDownload(message.message);
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              setState(() {
                _loadingProgress = progress;
                _isLoading = progress < 100;
              });
            },
            onPageStarted: (String url) {
              setState(() {
                _isLoading = true;
              });
            },
            onPageFinished: (String url) async {
              setState(() {
                _isLoading = false;
              });
              // Update back button state
              final canBack = await _controller?.canGoBack() ?? false;
              setState(() {
                _canGoBack = canBack;
              });
              
              // Override window.print & attach DownloadChannel link click interceptor + Responsive table styles
              try {
                await _controller?.runJavaScript('''
                  (function() {
                    window.print = function() {
                      if (window.PrintChannel) {
                        window.PrintChannel.postMessage('print');
                      }
                    };

                    var _bctLastDownloadKey = '';
                    var _bctLastDownloadTime = 0;

                    window.bctFetchAndDownload = function(fileUrl, filename) {
                      var now = Date.now();
                      var key = fileUrl + '_' + (filename || '');
                      if (key === _bctLastDownloadKey && (now - _bctLastDownloadTime) < 3000) {
                        console.log('Ignoring duplicate bctFetchAndDownload:', key);
                        return;
                      }
                      _bctLastDownloadKey = key;
                      _bctLastDownloadTime = now;

                      fetch(fileUrl, { credentials: 'include' })
                        .then(function(res) {
                          if (!res.ok) throw new Error('HTTP ' + res.status);
                          return res.blob();
                        })
                        .then(function(blob) {
                          var reader = new FileReader();
                          reader.onloadend = function() {
                            if (window.DownloadChannel) {
                              window.DownloadChannel.postMessage(JSON.stringify({
                                action: 'save_base64',
                                data: reader.result,
                                filename: filename || ''
                              }));
                            }
                          };
                          reader.readAsDataURL(blob);
                        })
                        .catch(function(err) {
                          console.error('Fetch download error:', err);
                        });
                    };

                    // Intercept download links or <a> elements with download attribute or external app links (WhatsApp, etc)
                    document.addEventListener('click', function(e) {
                      var target = e.target.closest('a, button');
                      if (!target) return;
                      
                      var href = target.getAttribute('href') || target.getAttribute('data-href');
                      if (!href) return;

                      var isWaLink = href.indexOf('whatsapp://') === 0 ||
                                     href.indexOf('wa.me/') !== -1 ||
                                     href.indexOf('api.whatsapp.com/') !== -1 ||
                                     href.indexOf('tel:') === 0 ||
                                     href.indexOf('mailto:') === 0;

                      if (isWaLink) {
                        if (window.DownloadChannel) {
                          e.preventDefault();
                          window.DownloadChannel.postMessage(JSON.stringify({
                            action: 'external_launch',
                            url: href
                          }));
                          return;
                        }
                      }

                      var hasDownload = target.hasAttribute('download') || target.id === 'previewDownloadBtn';
                      var isDownloadUrl = (
                        href.includes('/download-') ||
                        href.endsWith('.jpg') || href.endsWith('.jpeg') ||
                        href.endsWith('.png') || href.endsWith('.pdf') ||
                        href.endsWith('.xlsx') || href.endsWith('.csv')
                      );

                      if ((hasDownload || isDownloadUrl)) {
                        if (window.DownloadChannel) {
                          e.preventDefault();
                          var downloadAttr = target.getAttribute('download') || '';
                          window.bctFetchAndDownload(href, downloadAttr);
                        }
                      }
                    }, true);

                    // Inject responsive table horizontal scroll styles if not already present
                    if (!document.getElementById('bct-mobile-table-styles')) {
                      var style = document.createElement('style');
                      style.id = 'bct-mobile-table-styles';
                      style.innerHTML = `
                        @media (max-width: 768px) {
                          .overflow-x-auto {
                            overflow-x: auto !important;
                            -webkit-overflow-scrolling: touch !important;
                            touch-action: pan-x pan-y !important;
                            width: 100% !important;
                            max-width: 100% !important;
                          }
                          .overflow-x-auto > table,
                          table.responsive-table {
                            min-width: 680px !important;
                          }
                        }
                      `;
                      document.head.appendChild(style);
                    }
                  })();
                ''');
              } catch (e) {
                debugPrint("Error injecting scripts/styles into WebView: \$e");
              }
            },
            onWebResourceError: (WebResourceError error) {
              debugPrint("WebView Error: ${error.description}");
              if (error.errorType == WebResourceErrorType.hostLookup ||
                  error.errorType == WebResourceErrorType.connect ||
                  error.errorType == WebResourceErrorType.timeout) {
                _navigateToNoConnection();
              }
            },
            onNavigationRequest: (NavigationRequest request) {
              final urlLower = request.url.toLowerCase();

              // Intercept WhatsApp & external application schemes
              final isExternalApp = urlLower.startsWith('whatsapp://') ||
                  urlLower.contains('wa.me/') ||
                  urlLower.contains('api.whatsapp.com/') ||
                  urlLower.startsWith('tel:') ||
                  urlLower.startsWith('mailto:') ||
                  urlLower.startsWith('sms:') ||
                  urlLower.startsWith('intent:');

              if (isExternalApp) {
                _launchExternalUrl(request.url);
                return NavigationDecision.prevent;
              }

              final isDownloadUrl = urlLower.contains('/download-') ||
                  urlLower.endsWith('.pdf') ||
                  urlLower.endsWith('.jpg') ||
                  urlLower.endsWith('.jpeg') ||
                  urlLower.endsWith('.png') ||
                  urlLower.endsWith('.xlsx') ||
                  urlLower.endsWith('.csv') ||
                  urlLower.endsWith('.zip');

              if (isDownloadUrl && !urlLower.contains('inline=true')) {
                _handleDownload(request.url);
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse(AppConfig.targetUrl));

      if (Platform.isAndroid) {
        final platformController = _controller?.platform;
        if (platformController is AndroidWebViewController) {
          platformController.setOnShowFileSelector((params) async {
            return await _showFilePickerBottomSheet(context, params);
          });
        }
      }
    } else {
      _controller = null;
      _isLoading = false;
    }

    // Monitor internet connection changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.contains(ConnectivityResult.mobile) ||
                            results.contains(ConnectivityResult.wifi) ||
                            results.contains(ConnectivityResult.ethernet) ||
                            results.contains(ConnectivityResult.vpn);
      
      if (!hasConnection && _isCurrentlyConnected) {
        _isCurrentlyConnected = false;
        _showNoConnectionSnackbar();
      } else if (hasConnection && !_isCurrentlyConnected) {
        _isCurrentlyConnected = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Koneksi terhubung kembali"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        if (!kIsWeb) {
          _controller?.reload();
        }
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  void _showNoConnectionSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Koneksi internet terputus"),
        backgroundColor: AppConfig.errorRed,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Coba Lagi',
          textColor: Colors.white,
          onPressed: () {
            if (!kIsWeb) {
              _controller?.reload();
            }
          },
        ),
      ),
    );
  }

  void _navigateToNoConnection() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const NoConnectionScreen()),
      );
    }
  }

  Future<void> _launchWebsite() async {
    final Uri url = Uri.parse(AppConfig.targetUrl);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Tidak dapat membuka URL: $url")),
        );
      }
    }
  }

  Future<void> _launchExternalUrl(String urlString) async {
    try {
      final Uri uri = Uri.parse(urlString);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback for WhatsApp links (e.g. whatsapp:// or wa.me)
        if (urlString.contains('wa.me') || urlString.contains('whatsapp')) {
          Uri fallbackUri = uri;
          if (urlString.startsWith('whatsapp://')) {
            final pathAndQuery = urlString.replaceFirst('whatsapp://', '');
            fallbackUri = Uri.parse('https://wa.me/$pathAndQuery');
          }
          await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Tidak dapat membuka aplikasi untuk: $urlString")),
          );
        }
      }
    } catch (e) {
      debugPrint("Error launching external URL: $e");
      try {
        await launchUrl(Uri.parse(urlString), mode: LaunchMode.externalApplication);
      } catch (err) {
        debugPrint("Secondary launch error: $err");
      }
    }
  }

  // --- Download & Gallery Saving Logic ---

  Future<void> _triggerFetchInWebView(String fileUrl, {String? suggestedFilename}) async {
    try {
      if (_controller != null) {
        final safeUrl = jsonEncode(fileUrl);
        final safeName = jsonEncode(suggestedFilename ?? '');
        await _controller?.runJavaScript(
          'if (typeof window.bctFetchAndDownload === "function") { window.bctFetchAndDownload($safeUrl, $safeName); }'
        );
      } else {
        await _handleDownload(fileUrl, suggestedFilename: suggestedFilename);
      }
    } catch (e) {
      debugPrint("Error triggering JS fetch: $e");
      await _handleDownload(fileUrl, suggestedFilename: suggestedFilename);
    }
  }

  Future<void> _handleSaveBase64Data(String base64DataString, {String? suggestedFilename}) async {
    final String dedupeKey = suggestedFilename ?? (base64DataString.length > 30 ? base64DataString.substring(0, 30) : base64DataString);
    if (_isDuplicateDownload(dedupeKey)) return;

    try {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text("Mendownload file..."),
            ],
          ),
          duration: Duration(seconds: 3),
        ),
      );

      String base64Content = base64DataString;
      String contentType = '';
      if (base64DataString.contains(';base64,')) {
        final parts = base64DataString.split(';base64,');
        if (parts.length == 2) {
          contentType = parts[0].replaceFirst('data:', '');
          base64Content = parts[1];
        }
      }

      final Uint8List bytes = base64Decode(base64Content);

      if (bytes.isEmpty) {
        throw Exception("Ukuran berkas kosong (0 bytes)");
      }

      // Check for HTML text response
      if (bytes.length > 4) {
        final headerStr = String.fromCharCodes(bytes.sublist(0, math.min(bytes.length, 100))).toLowerCase();
        if (headerStr.contains('<!doctype') || headerStr.contains('<html') || headerStr.contains('forbidden')) {
          throw Exception("Gagal mengunduh: Sesi telah berakhir atau akses ditolak oleh server.");
        }
      }

      // Determine proper filename and extension
      String filename = suggestedFilename ?? '';
      if (filename.isEmpty || !filename.contains('.')) {
        if (contentType.contains('image/jpeg') || (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8)) {
          filename = 'nota_bct_${DateTime.now().millisecondsSinceEpoch}.jpg';
        } else if (contentType.contains('image/png') || (bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50)) {
          filename = 'nota_bct_${DateTime.now().millisecondsSinceEpoch}.png';
        } else if (contentType.contains('pdf') || (bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50)) {
          filename = 'dokumen_bct_${DateTime.now().millisecondsSinceEpoch}.pdf';
        } else {
          filename = 'file_bct_${DateTime.now().millisecondsSinceEpoch}.jpg';
        }
      }

      final bool isImage = filename.endsWith('.jpg') ||
          filename.endsWith('.jpeg') ||
          filename.endsWith('.png') ||
          contentType.contains('image/') ||
          (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xD8);

      // Save to local App Temp Directory
      final tempDir = await getTemporaryDirectory();
      final filePath = p.join(tempDir.path, filename);
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      String savedLocationInfo = 'Downloads';

      // Save to Public Downloads Directory if available
      try {
        Directory? downloadsDir;
        if (Platform.isAndroid) {
          downloadsDir = Directory('/storage/emulated/0/Download');
          if (!downloadsDir.existsSync()) {
            downloadsDir = await getDownloadsDirectory();
          }
        } else {
          downloadsDir = await getDownloadsDirectory();
        }

        if (downloadsDir != null && downloadsDir.existsSync()) {
          final downloadFilePath = p.join(downloadsDir.path, filename);
          await File(downloadFilePath).writeAsBytes(bytes);
        }
      } catch (e) {
        debugPrint("Public Download dir save error: $e");
      }

      // If file is Image (Nota JPG/PNG), save to phone Gallery
      if (isImage) {
        try {
          final hasAccess = await Gal.hasAccess(toAlbum: true);
          if (!hasAccess) {
            await Gal.requestAccess(toAlbum: true);
          }
          await Gal.putImage(file.path, album: 'BCT Nota');
          savedLocationInfo = 'Galeri & Downloads';
        } catch (e) {
          debugPrint("Gal putImage error: $e");
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Berhasil disimpan ke $savedLocationInfo: $filename"),
          backgroundColor: Colors.green[700],
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Buka / Bagikan',
            textColor: Colors.white,
            onPressed: () {
              Share.shareXFiles(
                [XFile(file.path)],
                text: 'File BCT Multipress: $filename',
              );
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint("Save base64 error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Terjadi kesalahan saat menyimpan file: $e"),
          backgroundColor: AppConfig.errorRed,
        ),
      );
    }
  }

  Future<void> _handleDownload(String fileUrl, {String? suggestedFilename}) async {
    if (_isDuplicateDownload(fileUrl)) return;

    try {
      Uri uri = Uri.parse(fileUrl);
      if (!uri.hasScheme) {
        final currentUrlStr = await _controller?.currentUrl() ?? AppConfig.targetUrl;
        final currentUri = Uri.parse(currentUrlStr);
        uri = currentUri.resolve(fileUrl);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text("Mendownload file..."),
            ],
          ),
          duration: Duration(seconds: 3),
        ),
      );

      // Get cookies from WebView to retain session authentication
      String cookieHeader = '';
      try {
        final cookies = await _controller?.runJavaScriptReturningResult('document.cookie') as String?;
        if (cookies != null && cookies.isNotEmpty) {
          String cleanCookie = cookies;
          if (cleanCookie.startsWith('"') && cleanCookie.endsWith('"')) {
            cleanCookie = jsonDecode(cleanCookie);
          }
          cookieHeader = cleanCookie;
        }
      } catch (e) {
        debugPrint("Error fetching cookies: $e");
      }

      final response = await http.get(
        uri,
        headers: {
          if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
          'User-Agent': 'Mozilla/5.0 (Linux; Android 10) Mobile BCT App',
        },
      );

      if (response.statusCode != 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal mendownload file (HTTP ${response.statusCode})"),
            backgroundColor: AppConfig.errorRed,
          ),
        );
        return;
      }

      final bytes = response.bodyBytes;
      final contentType = response.headers['content-type'] ?? '';

      // Determine proper filename
      String filename = suggestedFilename ?? '';
      if (filename.isEmpty) {
        final contentDisposition = response.headers['content-disposition'] ?? '';
        if (contentDisposition.contains('filename=')) {
          final match = RegExp(r'filename="?([^";]+)"?').firstMatch(contentDisposition);
          if (match != null) {
            filename = match.group(1) ?? '';
          }
        }
      }
      if (filename.isEmpty) {
        filename = p.basename(uri.path);
      }
      if (filename.isEmpty || !filename.contains('.')) {
        if (contentType.contains('image/jpeg') || uri.path.contains('invoice')) {
          filename = 'nota_bct_${DateTime.now().millisecondsSinceEpoch}.jpg';
        } else if (contentType.contains('image/png')) {
          filename = 'nota_bct_${DateTime.now().millisecondsSinceEpoch}.png';
        } else if (contentType.contains('pdf')) {
          filename = 'dokumen_bct_${DateTime.now().millisecondsSinceEpoch}.pdf';
        } else {
          filename = 'file_bct_${DateTime.now().millisecondsSinceEpoch}';
        }
      }

      final bool isImage = filename.endsWith('.jpg') ||
          filename.endsWith('.jpeg') ||
          filename.endsWith('.png') ||
          contentType.contains('image/');

      // Save to local App Temp Directory
      final tempDir = await getTemporaryDirectory();
      final filePath = p.join(tempDir.path, filename);
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      String savedLocationInfo = 'Downloads';

      // Save to Public Downloads Directory if available
      try {
        Directory? downloadsDir;
        if (Platform.isAndroid) {
          downloadsDir = Directory('/storage/emulated/0/Download');
          if (!downloadsDir.existsSync()) {
            downloadsDir = await getDownloadsDirectory();
          }
        } else {
          downloadsDir = await getDownloadsDirectory();
        }

        if (downloadsDir != null && downloadsDir.existsSync()) {
          final downloadFilePath = p.join(downloadsDir.path, filename);
          await File(downloadFilePath).writeAsBytes(bytes);
        }
      } catch (e) {
        debugPrint("Public Download dir save error: $e");
      }

      // If file is Image (Nota JPG/PNG), save to phone Gallery
      if (isImage) {
        try {
          final hasAccess = await Gal.hasAccess(toAlbum: true);
          if (!hasAccess) {
            await Gal.requestAccess(toAlbum: true);
          }
          await Gal.putImage(file.path, album: 'BCT Nota');
          savedLocationInfo = 'Galeri & Downloads';
        } catch (e) {
          debugPrint("Gal putImage error: $e");
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Berhasil disimpan ke $savedLocationInfo: $filename"),
          backgroundColor: Colors.green[700],
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Buka / Bagikan',
            textColor: Colors.white,
            onPressed: () {
              Share.shareXFiles(
                [XFile(file.path)],
                text: 'File BCT Multipress: $filename',
              );
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint("Download error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Terjadi kesalahan saat mendownload: $e"),
          backgroundColor: AppConfig.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Style status bar matching theme
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ));

    // If running on Web (Chrome debug), display a premium developer-friendly mock page
    if (kIsWeb) {
      return Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: AppConfig.splashGradient,
          ),
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 450),
                  padding: const EdgeInsets.all(32.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppConfig.primaryStart.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.chrome_reader_mode_rounded,
                          size: 60,
                          color: AppConfig.primaryStart,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "Mode Pratinjau Web",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "WebView native Android tidak didukung di browser Google Chrome.\n\nNamun, Anda dapat menguji fungsionalitas dan membuka website target di bawah ini:",
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF475569),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _launchWebsite,
                          icon: const Icon(Icons.open_in_new_rounded, color: Colors.white),
                          label: const Text(
                            "Buka Website Target",
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppConfig.accentColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => const SplashScreen()),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppConfig.primaryStart),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            "Muat Ulang Aplikasi",
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppConfig.primaryStart),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Android/iOS execution
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
          final canBack = await _controller.canGoBack();
          setState(() {
            _canGoBack = canBack;
          });
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              // WebView component
              WebViewWidget(controller: _controller!),
              
              // Custom top Linear Progress Bar for loading feedback
              if (_isLoading)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 3,
                  child: LinearProgressIndicator(
                    value: _loadingProgress / 100.0,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppConfig.accentColor),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --- WebView File Upload / Picker Methods ---

  Future<List<String>> _showFilePickerBottomSheet(BuildContext context, FileSelectorParams params) async {
    if (!mounted) return [];

    final bool allowMultiple = params.mode == FileSelectorMode.openMultiple;

    final result = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bc) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24.0),
              topRight: Radius.circular(24.0),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    "Pilih Sumber Bukti Pengeluaran",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppConfig.textDark,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE0E7FF),
                    child: Icon(Icons.camera_alt_rounded, color: AppConfig.primaryStart),
                  ),
                  title: const Text("Ambil Foto (Kamera)"),
                  subtitle: const Text("Gunakan kamera untuk memfoto bukti fisik"),
                  onTap: () async {
                    final paths = await _pickFromCamera();
                    if (bc.mounted) Navigator.of(bc).pop(paths);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFEF3C7),
                    child: Icon(Icons.photo_library_rounded, color: Colors.orange),
                  ),
                  title: const Text("Pilih dari Galeri"),
                  subtitle: const Text("Pilih gambar dari album foto HP"),
                  onTap: () async {
                    final paths = await _pickFromGallery(allowMultiple);
                    if (bc.mounted) Navigator.of(bc).pop(paths);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFDCFCE7),
                    child: Icon(Icons.insert_drive_file_rounded, color: Colors.green),
                  ),
                  title: const Text("Pilih File / Dokumen"),
                  subtitle: const Text("Pilih PDF, gambar, atau file lain"),
                  onTap: () async {
                    final paths = await _pickFromFiles(allowMultiple);
                    if (bc.mounted) Navigator.of(bc).pop(paths);
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );

    return result ?? [];
  }

  Future<List<String>> _pickFromGallery(bool allowMultiple) async {
    try {
      final ImagePicker picker = ImagePicker();
      if (allowMultiple) {
        final List<XFile> images = await picker.pickMultiImage(
          imageQuality: 85,
        );
        return images.map((image) => Uri.file(image.path).toString()).toList();
      } else {
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
        );
        if (image != null) {
          return [Uri.file(image.path).toString()];
        }
      }
    } catch (e) {
      debugPrint("Gallery picker error: $e");
    }
    return [];
  }

  Future<List<String>> _pickFromCamera() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (photo != null) {
        return [Uri.file(photo.path).toString()];
      }
    } catch (e) {
      debugPrint("Camera picker error: $e");
    }
    return [];
  }

  Future<List<String>> _pickFromFiles(bool allowMultiple) async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: allowMultiple,
        type: FileType.any,
      );
      if (result != null) {
        return result.paths
            .where((path) => path != null)
            .map((path) => Uri.file(path!).toString())
            .toList();
      }
    } catch (e) {
      debugPrint("File picker error: $e");
    }
    return [];
  }

  Future<void> _handlePrint() async {
    try {
      final String rawHtml = await _controller!.runJavaScriptReturningResult(
        "document.documentElement.outerHTML"
      ) as String;

      String html = rawHtml;
      try {
        if (html.startsWith('"') && html.endsWith('"')) {
          html = jsonDecode(html);
        }
      } catch (e) {
        debugPrint("Failed to decode print HTML JSON: $e");
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => await Printing.convertHtml(
          format: format,
          html: html,
        ),
        name: 'BCT_Dokumen',
      );
    } catch (e) {
      debugPrint("Printing error: $e");
    }
  }
}
