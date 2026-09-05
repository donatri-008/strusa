import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Idle detection
// ─────────────────────────────────────────────────────────────────────────────

const _kLastActiveKey = 'app_last_active_ts';

Future<void> recordAppActive() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastActiveKey, DateTime.now().millisecondsSinceEpoch);
  } catch (_) {}
}

Future<bool> isAppIdleFor({
  Duration threshold = const Duration(minutes: 30),
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final last  = prefs.getInt(_kLastActiveKey);
    if (last == null) return true;
    return DateTime.now().millisecondsSinceEpoch - last >
        threshold.inMilliseconds;
  } catch (_) {
    return true;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Token refresh — HANYA refresh token, TIDAK menyentuh Firestore channel
// ─────────────────────────────────────────────────────────────────────────────

Future<void> refreshAuthToken() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await user.getIdToken(true).timeout(const Duration(seconds: 10));
    debugPrint('[FirestoreHelper] Token berhasil di-refresh');
  } catch (e) {
    debugPrint('[FirestoreHelper] Token refresh gagal (lanjut): $e');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// onAppResume — TIDAK ada warmup Firestore sama sekali
// warmUpFirestore() DIHAPUS karena menyebabkan Channel shutdownNow
// yang membuat Firestore masuk offline mode
// ─────────────────────────────────────────────────────────────────────────────

Future<void> onAppResume() async {
  try {
    final isIdle = await isAppIdleFor();
    debugPrint('[FirestoreHelper] onAppResume — isIdle: $isIdle');

    // Hanya refresh token Auth, TIDAK menyentuh Firestore
    if (isIdle) await refreshAuthToken();

    await recordAppActive();
    debugPrint('[FirestoreHelper] onAppResume selesai');
  } catch (e) {
    debugPrint('[FirestoreHelper] onAppResume error: $e');
  }
}

// Stub agar kode lama yang masih memanggil warmUpFirestore() tidak error
Future<void> warmUpFirestore() async => onAppResume();

// Stub agar kode lama yang memanggil resetWarmUpFlag() tidak error
void resetWarmUpFlag() {}

// ─────────────────────────────────────────────────────────────────────────────
// Wrapper retry untuk operasi penting
// ─────────────────────────────────────────────────────────────────────────────

Future<T> firestoreCall<T>(
  Future<T> Function() call, {
  int maxRetry     = 3,
  bool refreshFirst = false,
}) async {
  if (refreshFirst) await refreshAuthToken();

  int attempt = 0;
  while (true) {
    try {
      return await call().timeout(const Duration(seconds: 25));
    } catch (e) {
      attempt++;
      if (attempt >= maxRetry) rethrow;
      debugPrint('[FirestoreHelper] Attempt $attempt gagal: $e — retry...');
      await refreshAuthToken();
      await Future.delayed(Duration(seconds: attempt * 2));
    }
  }
}