import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'register_screen.dart';
import '../home/main_screen.dart';
import '../../services/firestore_helper.dart';
import '../../utils/app_notification.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey            = GlobalKey<FormState>();
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading       = false;
  bool _obscurePassword = true;
  bool _rememberMe      = false;

  late AnimationController _animationController;

  // ── Keys SharedPreferences ────────────────────────────────────────────────
  static const _kRememberMe = 'remember_me';
  static const _kSavedEmail = 'saved_email';
  static const _kSavedPass  = 'saved_password';
  static const _kIsLoggedIn = 'isLoggedIn';
  static const _kUserEmail  = 'userEmail';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _animationController.forward();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ── Load kredensial tersimpan ─────────────────────────────────────────────
  Future<void> _loadSavedCredentials() async {
    final prefs      = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString(_kSavedEmail) ?? '';
    final savedPass  = prefs.getString(_kSavedPass)  ?? '';
    final remember   = prefs.getBool(_kRememberMe)   ?? false;

    if (!mounted) return;

    if (remember && savedEmail.isNotEmpty && savedPass.isNotEmpty) {
      setState(() {
        _rememberMe              = true;
        _emailController.text    = savedEmail;
        _passwordController.text = savedPass;
      });
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final email    = _emailController.text.trim();
    final password = _passwordController.text; // jangan trim password

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final prefs = await SharedPreferences.getInstance();

      // Simpan flag sesi
      await prefs.setBool(_kIsLoggedIn, true);
      await prefs.setString(_kUserEmail, email);

      // ── Simpan kredensial sesuai pilihan "Ingat Saya" ─────────────────────
      // Jika "Ingat Saya" aktif → simpan untuk auto re-login saat token expired.
      // Jika tidak aktif → hapus kredensial lama agar tidak auto re-login.
      await prefs.setBool(_kRememberMe, _rememberMe);
      if (_rememberMe) {
        await prefs.setString(_kSavedEmail, email);
        await prefs.setString(_kSavedPass, password);
        debugPrint('[Login] Kredensial tersimpan untuk auto re-login');
      } else {
        await prefs.remove(_kSavedEmail);
        await prefs.remove(_kSavedPass);
        debugPrint('[Login] Kredensial tidak disimpan (Ingat Saya = off)');
      }

      onAppResume();
      AppNotification.loginSuccess(
        FirebaseAuth.instance.currentUser?.displayName ?? email,
      );
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) Get.offAll(() => const MainScreen());
    } on FirebaseAuthException catch (e) {
      AppNotification.loginFailed(e.code); 
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2196F3),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 40),

              // ── Logo & Judul ──────────────────────────────────────────────
              FadeTransition(
                opacity: _animationController,
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/logo.png',
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'STRUSA POS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sistem Transaksi PPOB',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 50),

              // ── Form Card ─────────────────────────────────────────────────
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2196F3),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Masuk ke akun Anda',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // Email
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          hintText: 'Masukkan email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Email harus diisi';
                          }
                          if (!v.contains('@')) {
                            return 'Format email tidak valid';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Password
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          hintText: 'Masukkan password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Password harus diisi';
                          }
                          if (v.length < 6) {
                            return 'Password minimal 6 karakter';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Remember Me
                      GestureDetector(
                        onTap: () =>
                            setState(() => _rememberMe = !_rememberMe),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: _rememberMe
                                    ? const Color(0xFF2196F3)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _rememberMe
                                      ? const Color(0xFF2196F3)
                                      : Colors.grey.withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                              ),
                              child: _rememberMe
                                  ? const Icon(Icons.check_rounded,
                                      size: 14, color: Colors.white)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Ingat Saya',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF374151),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            AnimatedOpacity(
                              opacity: _rememberMe ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2196F3)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFF2196F3)
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: const Text(
                                  'Aktif',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF2196F3),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Tombol Login
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Login',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Daftar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Belum punya akun? ',
                            style: TextStyle(color: Colors.grey),
                          ),
                          TextButton(
                            onPressed: () =>
                                Get.to(() => const RegisterScreen()),
                            child: const Text(
                              'Daftar',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2196F3),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}