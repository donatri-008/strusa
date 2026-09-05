import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'customer_service.dart';

class StartupCleanup {
  static const _prefKey = 'customer_cleanup_done_v2';

  /// Jalankan cleanup pelanggan duplikat, tapi hanya sekali per sesi install.
  ///
  /// ✅ FIX: Ditunda 5 detik agar tidak bersaing dengan query utama
  /// (loadCustomers, homeTab streams, dll) saat app baru buka.
  /// Ini mencegah overload koneksi Firestore di awal yang bisa
  /// menyebabkan Channel shutdownNow / offline mode.
  ///
  /// [force] = true → jalankan meski sudah pernah dilakukan (untuk debug).
  static Future<void> run({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done  = prefs.getBool(_prefKey) ?? false;

      if (done && !force) {
        debugPrint('[StartupCleanup] Sudah dijalankan sebelumnya, skip.');
        return;
      }

      // ✅ Tunda 5 detik — beri waktu koneksi Firestore stabil
      // dan query utama (customers, transactions) selesai dulu
      debugPrint('[StartupCleanup] Menunggu 5 detik sebelum cleanup...');
      await Future.delayed(const Duration(seconds: 5));

      debugPrint('[StartupCleanup] Mulai cleanup pelanggan duplikat...');
      final result = await CustomerService().cleanupDuplicates();

      await prefs.setBool(_prefKey, true);

      if (result.hasChanges) {
        debugPrint('[StartupCleanup] Selesai: ${result.summary}');
        for (final line in result.log) {
          debugPrint('  $line');
        }
      } else {
        debugPrint('[StartupCleanup] Selesai: data sudah bersih.');
      }
    } catch (e) {
      debugPrint('[StartupCleanup] Error: $e');
    }
  }

  /// Reset flag → cleanup akan dijalankan lagi di sesi berikutnya.
  /// Panggil ini setelah user logout.
  static Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (_) {}
  }
}