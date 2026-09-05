import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:open_settings_plus/open_settings_plus.dart';
import 'package:open_settings_plus/core/open_settings_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/splash_screen.dart';
import 'utils/app_notification.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  OverlayEntry? _overlayEntry;
  bool _wasOffline = false;
  bool _isFirstCheck = true;
  bool _isChecking = false;
  int _failCount = 0; // harus gagal 2x berturut-turut baru dianggap offline
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkConnection());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkConnection());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _removeOverlay();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    // Cegah race condition
    if (_isChecking) return;
    _isChecking = true;

    bool isOffline;
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      isOffline = result.isEmpty || result.first.rawAddress.isEmpty;
    } catch (_) {
      isOffline = true;
    }

    if (!mounted) {
      _isChecking = false;
      return;
    }

    // Hitung gagal berturut-turut
    if (isOffline) {
      _failCount++;
    } else {
      _failCount = 0;
    }

    // Baru dianggap offline jika gagal 2x berturut-turut
    // Ini mencegah false positive akibat DNS hiccup sesaat
    final confirmedOffline = _failCount >= 2;

    // Saat pertama buka app — set state awal tanpa tampilkan notifikasi apapun
    if (_isFirstCheck) {
      _isFirstCheck = false;
      _wasOffline = confirmedOffline;
      if (confirmedOffline) _showNoInternetOverlay();
      _isChecking = false;
      return;
    }

    if (confirmedOffline && !_wasOffline) {
      _wasOffline = true;
      _showNoInternetOverlay();
    } else if (!confirmedOffline && _wasOffline) {
      _wasOffline = false;
      _failCount = 0;
      _removeOverlay();
      AppNotification.networkRestored(); // ← pakai AppNotification
    }

    _isChecking = false;
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showNoInternetOverlay() {
    if (_overlayEntry != null) return;
    final overlay = _navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => _NoInternetOverlay(
        onOpenSettings: _openConnectionSettings,
        onRetry: () async {
          // Reset semua state agar bisa cek ulang dari awal
          _failCount = 0;
          _wasOffline = false;
          _removeOverlay();
          _isChecking = false;
          await _checkConnection();
        },
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  Future<void> _openConnectionSettings() async {
    try {
      if (Platform.isAndroid) {
        final settings = OpenSettingsPlus.shared as OpenSettingsPlusAndroid;
        final success = await settings.dataRoaming();
        if (!success) {
          final successWifi = await settings.wifi();
          if (!successWifi) {
            await settings.call();
          }
        }
      } else if (Platform.isIOS) {
        final settings = OpenSettingsPlus.shared as OpenSettingsPlusIOS;
        await settings.wifi();
      }
    } catch (_) {
      try {
        if (Platform.isAndroid) {
          await (OpenSettingsPlus.shared as OpenSettingsPlusAndroid).call();
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Strusa',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      locale: const Locale('id', 'ID'),
      supportedLocales: const [
        Locale('id', 'ID'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      theme: ThemeData(
        primarySwatch: Colors.blue,
        primaryColor: const Color(0xFF2196F3),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        fontFamily: 'Outfit',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2196F3),
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            fontFamily: 'Outfit',
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2196F3),
            foregroundColor: Colors.white,
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'Outfit',
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2196F3), width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: Colors.white,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget Overlay No Internet
// ─────────────────────────────────────────────────────────────────────────────
class _NoInternetOverlay extends StatefulWidget {
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  const _NoInternetOverlay({
    required this.onOpenSettings,
    required this.onRetry,
  });

  @override
  State<_NoInternetOverlay> createState() => _NoInternetOverlayState();
}

class _NoInternetOverlayState extends State<_NoInternetOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Container(
            color: Colors.black.withValues(alpha: 0.62),
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 34, 24, 26),
                decoration: BoxDecoration(
                  color: const Color(0xFF12122A),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.07),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 60,
                      spreadRadius: 10,
                    ),
                    BoxShadow(
                      color: const Color(0xFFFF5252).withValues(alpha: 0.06),
                      blurRadius: 40,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFF5252).withValues(alpha: 0.08),
                        border: Border.all(
                          color: const Color(0xFFFF5252).withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.wifi_off_rounded,
                        color: Color(0xFFFF5252),
                        size: 42,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Tidak Ada Koneksi Internet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Outfit',
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Aktifkan Wi-Fi atau data seluler\nuntuk melanjutkan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.48),
                        fontSize: 13,
                        fontFamily: 'Outfit',
                        height: 1.65,
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: widget.onOpenSettings,
                        icon: const Icon(Icons.settings_rounded, size: 18),
                        label: const Text(
                          'Buka Pengaturan Koneksi',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2196F3),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: widget.onRetry,
                        icon: Icon(
                          Icons.refresh_rounded,
                          size: 18,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                        label: Text(
                          'Coba Lagi',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.13),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
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
}