import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import './auth/login_screen.dart';
import './home/main_screen.dart';
import '../services/firestore_helper.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _slideAnim;

  StreamSubscription<User?>? _authSub;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _fadeAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _scaleAnim = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );
    _slideAnim = Tween<double>(begin: 24.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.8, curve: Curves.easeOut),
      ),
    );
    _controller.forward();
    _startAuthCheck();
  }

  Future<void> _startAuthCheck() async {
    final minSplashDone = Future.delayed(const Duration(milliseconds: 2000));

    // ── Langkah 1: Cek SharedPreferences dulu (instan) ──────────────────────
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('userEmail') ?? '';
    final wasLogged = prefs.getBool('isLoggedIn') ?? false;

    debugPrint('[AUTH] SharedPrefs: isLoggedIn=$wasLogged, email=$savedEmail');

    // ── Langkah 2: Cek currentUser (jika Firebase sudah restore) ─────────────
    final quickUser = FirebaseAuth.instance.currentUser;
    debugPrint('[AUTH] currentUser: ${quickUser?.email ?? "null"}');

    if (quickUser != null) {
      await minSplashDone;
      _navigateTo(quickUser, prefs);
      return;
    }

    // ── Langkah 3: Lokal bilang sudah login tapi Firebase belum restore ───────
    if (wasLogged && savedEmail.isNotEmpty) {
      debugPrint('[AUTH] Lokal=login, tunggu Firebase restore...');

      int eventCount = 0;
      final completer = Completer<User?>();

      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        eventCount++;
        debugPrint('[AUTH] Event #$eventCount: ${user?.email ?? "null"}');

        if (!completer.isCompleted) {
          if (user != null) {
            completer.complete(user);
          } else if (eventCount >= 2) {
            completer.complete(null);
          }
        }
      });

      User? firebaseUser;
      try {
        firebaseUser =
            await completer.future.timeout(const Duration(seconds: 6));
      } catch (_) {
        firebaseUser = null;
      }

      debugPrint(
          '[AUTH] Hasil setelah tunggu: ${firebaseUser?.email ?? "null"}');

      await minSplashDone;

      if (firebaseUser != null) {
        _navigateTo(firebaseUser, prefs);
      } else {
        debugPrint('[AUTH] Firebase gagal restore, coba auto re-login...');
        await _tryAutoReLogin(prefs, minSplashDone);
      }
      return;
    }

    // ── Langkah 4: Lokal bilang belum login ───────────────────────────────────
    debugPrint('[AUTH] Lokal=tidak login → LoginScreen');
    await minSplashDone;
    _navigateTo(null, prefs);
  }

  Future<void> _tryAutoReLogin(
      SharedPreferences prefs, Future minSplashDone) async {
    final savedEmail = prefs.getString('saved_email') ?? '';
    final savedPass = prefs.getString('saved_password') ?? '';
    final rememberMe = prefs.getBool('remember_me') ?? false;

    debugPrint('[AUTH] rememberMe=$rememberMe, email=$savedEmail');

    if (rememberMe && savedEmail.isNotEmpty && savedPass.isNotEmpty) {
      try {
        debugPrint('[AUTH] Mencoba auto re-login...');
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: savedEmail,
          password: savedPass,
        );
        debugPrint('[AUTH] Auto re-login berhasil: ${cred.user?.email}');
        await minSplashDone;
        _navigateTo(cred.user, prefs);
        return;
      } catch (e) {
        debugPrint('[AUTH] Auto re-login gagal: $e');
      }
    }

    debugPrint('[AUTH] Tidak bisa auto re-login → LoginScreen');
    await prefs.setBool('isLoggedIn', false);
    await minSplashDone;
    _navigateTo(null, prefs);
  }

  void _navigateTo(User? user, SharedPreferences prefs) {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    prefs.setBool('isLoggedIn', user != null);
    if (user?.email != null) {
      prefs.setString('userEmail', user!.email!);
    }

    // ── KUNCI: Mulai warm-up Firestore segera setelah auth diketahui ──────────
    // Ini memberi head-start ~500ms sebelum MainScreen muncul.
    // onAppResume() async dan tidak memblokir navigasi.
    if (user != null) {
      onAppResume();
    }

    debugPrint(
        '[AUTH] → ${user != null ? "MainScreen (${user.email})" : "LoginScreen"}');

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) =>
            user != null ? const MainScreen() : const LoginScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1565C0), Color(0xFF2196F3), Color(0xFF42A5F5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3),
              AnimatedBuilder(
                animation: _controller,
                builder: (_, child) => FadeTransition(
                  opacity: _fadeAnim,
                  child: ScaleTransition(scale: _scaleAnim, child: child),
                ),
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              AnimatedBuilder(
                animation: _controller,
                builder: (_, child) => FadeTransition(
                  opacity: _fadeAnim,
                  child: Transform.translate(
                    offset: Offset(0, _slideAnim.value),
                    child: child,
                  ),
                ),
                child: const Column(children: [
                  Text(
                    'Strusa POS',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Sistem Transaksi PPOB',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                      fontWeight: FontWeight.w400,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ]),
              ),
              const Spacer(flex: 3),
              AnimatedBuilder(
                animation: _controller,
                builder: (_, child) => FadeTransition(
                  opacity: _fadeAnim,
                  child: child,
                ),
                child: Column(children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withValues(alpha: 0.7)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Memuat...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                      fontFamily: 'Outfit',
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
