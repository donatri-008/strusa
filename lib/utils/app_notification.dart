import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppNotification — sistem notifikasi terpusat siap produksi
// ─────────────────────────────────────────────────────────────────────────────

enum _NotifType { success, error, warning, info, partial }

class AppNotification {
  // ── Private core ─────────────────────────────────────────────────────────

  static void _show({
    required _NotifType type,
    required String title,
    required String message,
    Duration duration = const Duration(seconds: 3),
    IconData? customIcon,
    VoidCallback? action,
    String? actionLabel,
  }) {
    // Tutup snackbar aktif agar tidak overlap / queue menumpuk
    if (Get.isSnackbarOpen) Get.closeCurrentSnackbar();

    final config = _typeConfig(type);

    Get.showSnackbar(GetSnackBar(
      duration: duration,
      isDismissible: true,
      dismissDirection: DismissDirection.horizontal,
      forwardAnimationCurve: Curves.easeOutCubic,
      reverseAnimationCurve: Curves.easeInCubic,
      animationDuration: const Duration(milliseconds: 320),
      snackPosition: SnackPosition.TOP,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      borderRadius: 16,
      backgroundColor: Colors.transparent,
      padding: EdgeInsets.zero,
      messageText: _NotifCard(
        type: type,
        config: config,
        title: title,
        message: message,
        icon: customIcon ?? config.icon,
        action: action,
        actionLabel: actionLabel,
      ),
      titleText: const SizedBox.shrink(),
    ));
  }

  // ── Public API ────────────────────────────────────────────────────────────

  static void success(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 3),
    VoidCallback? action,
    String? actionLabel,
    IconData? customIcon,
  }) =>
      _show(
        type: _NotifType.success,
        title: title,
        message: message,
        duration: duration,
        customIcon: customIcon,
        action: action,
        actionLabel: actionLabel,
      );

  static void error(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 5),
    VoidCallback? action,
    String? actionLabel,
    IconData? customIcon,
  }) =>
      _show(
        type: _NotifType.error,
        title: title,
        message: message,
        duration: duration,
        customIcon: customIcon,
        action: action,
        actionLabel: actionLabel,
      );

  static void warning(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 4),
    VoidCallback? action,
    String? actionLabel,
    IconData? customIcon,
  }) =>
      _show(
        type: _NotifType.warning,
        title: title,
        message: message,
        duration: duration,
        customIcon: customIcon,
        action: action,
        actionLabel: actionLabel,
      );

  static void info(
    String title,
    String message, {
    Duration duration = const Duration(seconds: 3),
    VoidCallback? action,
    String? actionLabel,
    IconData? customIcon,
  }) =>
      _show(
        type: _NotifType.info,
        title: title,
        message: message,
        duration: duration,
        customIcon: customIcon,
        action: action,
        actionLabel: actionLabel,
      );

  // ── Auth ──────────────────────────────────────────────────────────────────

  /// Login gagal — terjemahkan FirebaseAuthException.code ke pesan ramah.
  static void loginFailed(String code) {
    final String message;
    switch (code) {
      case 'user-not-found':
        message = 'Email tidak terdaftar. Silakan daftar terlebih dahulu.';
      case 'wrong-password':
        message = 'Password salah. Periksa kembali password Anda.';
      case 'invalid-email':
        message = 'Format email tidak valid.';
      case 'invalid-credential':
        message = 'Email atau password salah. Silakan coba lagi.';
      case 'too-many-requests':
        message = 'Terlalu banyak percobaan gagal. Coba lagi beberapa saat.';
      case 'user-disabled':
        message = 'Akun ini telah dinonaktifkan. Hubungi admin.';
      case 'network-request-failed':
        message = 'Koneksi internet bermasalah. Periksa jaringan Anda.';
      default:
        message = 'Login gagal. Silakan coba lagi.';
    }
    _show(
      type: _NotifType.error,
      title: 'Login Gagal',
      message: message,
      duration: const Duration(seconds: 5),
      customIcon: Icons.lock_outline_rounded,
    );
  }

  /// Registrasi gagal — terjemahkan FirebaseAuthException.code ke pesan ramah.
  static void registerFailed(String code) {
    final String message;
    switch (code) {
      case 'weak-password':
        message = 'Password terlalu lemah. Gunakan minimal 6 karakter.';
      case 'email-already-in-use':
        message = 'Email sudah terdaftar. Silakan login atau gunakan email lain.';
      case 'invalid-email':
        message = 'Format email tidak valid.';
      case 'operation-not-allowed':
        message = 'Registrasi email/password tidak diizinkan.';
      case 'network-request-failed':
        message = 'Koneksi internet bermasalah. Periksa jaringan Anda.';
      default:
        message = 'Registrasi gagal. Silakan coba lagi.';
    }
    _show(
      type: _NotifType.error,
      title: 'Registrasi Gagal',
      message: message,
      duration: const Duration(seconds: 5),
      customIcon: Icons.person_off_rounded,
    );
  }

  static void registerSuccess(String name) => success(
        'Selamat Datang, $name!',
        'Akun berhasil dibuat. Selamat menggunakan Strusa.',
        duration: const Duration(seconds: 3),
        customIcon: Icons.how_to_reg_rounded,
      );

  static void loginSuccess(String name) => success(
        'Selamat Datang, $name!',
        'Login berhasil. Selamat bekerja.',
        duration: const Duration(seconds: 2),
        customIcon: Icons.verified_user_rounded,
      );

  static void logoutSuccess() => info(
        'Keluar',
        'Anda telah berhasil keluar dari akun.',
        duration: const Duration(seconds: 2),
        customIcon: Icons.logout_rounded,
      );

  static void sessionExpired({VoidCallback? onLogin}) => warning(
        'Sesi Berakhir',
        'Sesi login Anda telah berakhir. Silakan login kembali.',
        duration: const Duration(seconds: 5),
        customIcon: Icons.timer_off_rounded,
        action: onLogin,
        actionLabel: onLogin != null ? 'Login' : null,
      );

  // ── Transaksi & Data ──────────────────────────────────────────────────────

  static void saved(String message) => success(
        'Tersimpan',
        message,
        duration: const Duration(seconds: 2),
      );

  static void updated(String message) => success(
        'Diperbarui',
        message,
        duration: const Duration(seconds: 2),
        customIcon: Icons.edit_rounded,
      );

  static void deleted(String message) => success(
        'Dihapus',
        message,
        duration: const Duration(seconds: 3),
        customIcon: Icons.delete_rounded,
      );

  static void paid(String message) => success(
        'Lunas!',
        message,
        duration: const Duration(seconds: 3),
        customIcon: Icons.check_circle_rounded,
      );

  static void partialPaid(String message) => _show(
        type: _NotifType.partial,
        title: 'Pembayaran Dicatat',
        message: message,
        duration: const Duration(seconds: 3),
        customIcon: Icons.payments_rounded,
      );

  static void kembalian(String message) => success(
        'Semua Lunas!',
        message,
        duration: const Duration(seconds: 4),
        customIcon: Icons.savings_rounded,
      );

  /// Gagal simpan data — dengan tombol retry opsional.
  static void saveFailed({VoidCallback? onRetry}) => error(
        'Gagal Menyimpan',
        'Data tidak berhasil disimpan. Silakan coba lagi.',
        duration: const Duration(seconds: 5),
        customIcon: Icons.save_outlined,
        action: onRetry,
        actionLabel: onRetry != null ? 'Coba Lagi' : null,
      );

  /// Gagal memuat data — dengan tombol retry opsional.
  static void loadFailed({VoidCallback? onRetry}) => error(
        'Gagal Memuat Data',
        'Terjadi kesalahan saat mengambil data. Silakan coba lagi.',
        duration: const Duration(seconds: 5),
        customIcon: Icons.cloud_download_outlined,
        action: onRetry,
        actionLabel: onRetry != null ? 'Coba Lagi' : null,
      );

  /// Koneksi ke server terputus — dengan tombol retry opsional.
  static void networkError({VoidCallback? onRetry}) => error(
        'Koneksi Bermasalah',
        'Koneksi ke server terputus. Periksa internet dan coba lagi.',
        duration: const Duration(seconds: 5),
        customIcon: Icons.cloud_off_rounded,
        action: onRetry,
        actionLabel: onRetry != null ? 'Coba Lagi' : null,
      );

  static void networkRestored() => success(
        'Koneksi Tersambung',
        'Internet tersambung kembali. Semua fitur aktif.',
        duration: const Duration(seconds: 3),
        customIcon: Icons.wifi_rounded,
      );

  // ── Printer ───────────────────────────────────────────────────────────────

  static void printSuccess() => success(
        'Struk Berhasil Dicetak',
        'Printer selesai memproses struk.',
        duration: const Duration(seconds: 2),
        customIcon: Icons.print_rounded,
      );

  /// Tampilkan dialog loading mencetak dengan animasi Lottie.
  /// Auto-dismiss setelah [timeout] jika [hidePrintLoading] tidak dipanggil.
  static void showPrintLoading({
    Duration timeout = const Duration(seconds: 30),
  }) {
    Get.dialog(
      const _PrintLoadingDialog(),
      barrierDismissible: false,
      barrierColor: Colors.black54,
    );
    // Guard: auto-dismiss + tampilkan error timeout jika printer hang
    Future.delayed(timeout, () {
      if (Get.isDialogOpen ?? false) {
        Get.back();
        printError('timeout');
      }
    });
  }

  static void hidePrintLoading() {
    if (Get.isDialogOpen ?? false) Get.back();
  }

  /// Terjemahkan raw BT/printer exception ke pesan ramah pengguna.
  static void printError(
    String rawError, {
    VoidCallback? onRetry,
    VoidCallback? onChangePrinter,
  }) {
    assert(
      !(onRetry != null && onChangePrinter != null),
      'AppNotification.printError: hanya boleh pass salah satu antara '
      'onRetry atau onChangePrinter, bukan keduanya.',
    );

    final String title;
    final String message;

    if (rawError.contains('Printer tidak merespons') ||
        rawError.contains('Printer menolak koneksi')) {
      title = 'Gagal Terhubung ke Printer';
      message =
          'Printer menolak koneksi. Pastikan printer menyala dan tidak terhubung ke perangkat lain.';
    } else if (rawError.contains('tidak ditemukan') ||
        rawError.contains('not found')) {
      title = 'Printer Tidak Ditemukan';
      message =
          'Printer tidak terdeteksi. Pastikan Bluetooth aktif dan printer sudah di-pair.';
    } else if (rawError.contains('belum diatur') ||
        rawError.contains('belum diset')) {
      title = 'Printer Belum Dikonfigurasi';
      message = 'Silakan pilih printer terlebih dahulu di pengaturan.';
    } else if (rawError.contains('timeout') ||
        rawError.contains('TimeoutException')) {
      title = 'Koneksi Timeout';
      message =
          'Printer tidak merespons dalam waktu yang ditentukan. Pastikan printer menyala dan dalam jangkauan Bluetooth.';
    } else if (rawError.contains('tidak mendukung') ||
        rawError.contains('writeChar == null')) {
      title = 'Printer Tidak Kompatibel';
      message =
          'Printer ini tidak mendukung perintah cetak. Gunakan printer thermal ESC/POS.';
    } else {
      title = 'Gagal Mencetak';
      message = 'Terjadi kesalahan saat mencetak. Silakan coba lagi.';
    }

    _show(
      type: _NotifType.error,
      title: title,
      message: message,
      duration: const Duration(seconds: 5),
      customIcon: Icons.print_disabled_rounded,
      action: onRetry ?? onChangePrinter,
      actionLabel: onRetry != null
          ? 'Coba Lagi'
          : onChangePrinter != null
              ? 'Ganti Printer'
              : null,
    );
  }

  static void shareError() => error(
        'Gagal Membagikan',
        'Tidak dapat membagikan struk. Silakan coba lagi.',
        duration: const Duration(seconds: 4),
        customIcon: Icons.share_rounded,
      );

  static void bluetoothOff({VoidCallback? onEnable}) => warning(
        'Bluetooth Mati',
        'Aktifkan Bluetooth untuk mencetak struk via printer thermal.',
        duration: const Duration(seconds: 4),
        customIcon: Icons.bluetooth_disabled_rounded,
        action: onEnable,
        actionLabel: onEnable != null ? 'Nyalakan' : null,
      );

  // ── Outlet & Pengaturan ───────────────────────────────────────────────────

  static void outletSaved(String name) => success(
        'Outlet Tersimpan',
        'Outlet "$name" berhasil disimpan.',
        duration: const Duration(seconds: 2),
        customIcon: Icons.store_rounded,
      );

  static void outletDeleted(String name) => success(
        'Outlet Dihapus',
        'Outlet "$name" berhasil dihapus.',
        duration: const Duration(seconds: 3),
        customIcon: Icons.store_mall_directory_outlined,
      );

  static void outletSwitched(String name) => info(
        'Outlet Aktif',
        'Beralih ke outlet "$name".',
        duration: const Duration(seconds: 2),
        customIcon: Icons.swap_horiz_rounded,
      );

  // ── Pelanggan ─────────────────────────────────────────────────────────────

  static void customerSaved(String name) => success(
        'Pelanggan Disimpan',
        'Data pelanggan "$name" berhasil disimpan.',
        duration: const Duration(seconds: 2),
        customIcon: Icons.person_add_rounded,
      );

  static void customerDeleted(String name) => success(
        'Pelanggan Dihapus',
        'Data pelanggan "$name" berhasil dihapus.',
        duration: const Duration(seconds: 3),
        customIcon: Icons.person_remove_rounded,
      );

  static void debtRecorded(String name, String amount) => _show(
        type: _NotifType.partial,
        title: 'Hutang Dicatat',
        message: 'Hutang $amount untuk "$name" berhasil dicatat.',
        duration: const Duration(seconds: 3),
        customIcon: Icons.receipt_long_rounded,
      );

  static void debtPaid(String name) => success(
        'Hutang Lunas',
        'Semua hutang "$name" telah lunas.',
        duration: const Duration(seconds: 3),
        customIcon: Icons.check_circle_rounded,
      );

  // ── Produk ────────────────────────────────────────────────────────────────

  static void productSaved(String name) => success(
        'Produk Disimpan',
        'Produk "$name" berhasil disimpan.',
        duration: const Duration(seconds: 2),
        customIcon: Icons.inventory_2_rounded,
      );

  static void productDeleted(String name) => success(
        'Produk Dihapus',
        'Produk "$name" berhasil dihapus.',
        duration: const Duration(seconds: 3),
        customIcon: Icons.remove_shopping_cart_rounded,
      );

  static void stockLow(String name) => warning(
        'Stok Menipis',
        'Stok produk "$name" hampir habis. Segera restock.',
        duration: const Duration(seconds: 5),
        customIcon: Icons.inventory_rounded,
      );

  static void stockEmpty(String name) => error(
        'Stok Habis',
        'Produk "$name" sudah habis dan tidak bisa dijual.',
        duration: const Duration(seconds: 5),
        customIcon: Icons.remove_shopping_cart_rounded,
      );

  // ── Validasi form ─────────────────────────────────────────────────────────

  static void formIncomplete() => warning(
        'Form Belum Lengkap',
        'Harap isi semua field yang wajib diisi.',
        duration: const Duration(seconds: 3),
        customIcon: Icons.edit_note_rounded,
      );

  static void invalidInput(String fieldName) => warning(
        'Input Tidak Valid',
        'Periksa kembali field "$fieldName".',
        duration: const Duration(seconds: 3),
        customIcon: Icons.warning_amber_rounded,
      );

  // ── Umum ──────────────────────────────────────────────────────────────────

  /// Error tak terduga — tampilkan pesan teknis singkat.
  static void unexpectedError([String? detail]) => error(
        'Terjadi Kesalahan',
        detail != null
            ? 'Terjadi kesalahan: $detail'
            : 'Terjadi kesalahan yang tidak diketahui. Silakan coba lagi.',
        duration: const Duration(seconds: 5),
        customIcon: Icons.bug_report_rounded,
      );

  static void permissionDenied(String feature) => warning(
        'Izin Diperlukan',
        'Izin "$feature" dibutuhkan untuk menggunakan fitur ini.',
        duration: const Duration(seconds: 4),
        customIcon: Icons.lock_rounded,
      );

  static void comingSoon() => info(
        'Segera Hadir',
        'Fitur ini masih dalam pengembangan. Pantau terus pembaruan.',
        duration: const Duration(seconds: 3),
        customIcon: Icons.rocket_launch_rounded,
      );
}

// ── Dialog loading cetak dengan animasi Lottie ────────────────────────────────

class _PrintLoadingDialog extends StatelessWidget {
  const _PrintLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 48),
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 32,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: Lottie.asset(
                'assets/lottie/printing.json',
                fit: BoxFit.contain,
                repeat: true,
                errorBuilder: (_, __, ___) => const _FallbackPrintIcon(),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Mencetak Struk...',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Jangan tutup aplikasi',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: const LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: Color(0xFFE5E7EB),
                valueColor: AlwaysStoppedAnimation(Color(0xFF2196F3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FallbackPrintIcon extends StatelessWidget {
  const _FallbackPrintIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Icon(Icons.print_rounded, size: 52, color: Color(0xFF2196F3)),
    );
  }
}

// ── Private helpers ────────────────────────────────────────────────────────────

_NotifConfig _typeConfig(_NotifType type) {
  switch (type) {
    case _NotifType.success:
      return _NotifConfig(
        bg: const Color(0xFF1B3A2D),
        accent: const Color(0xFF4CAF50),
        iconBg: const Color(0xFF2E7D32),
        icon: Icons.check_circle_rounded,
      );
    case _NotifType.error:
      return _NotifConfig(
        bg: const Color(0xFF3B1A1A),
        accent: const Color(0xFFEF5350),
        iconBg: const Color(0xFFC62828),
        icon: Icons.error_rounded,
      );
    case _NotifType.warning:
      return _NotifConfig(
        bg: const Color(0xFF2D1F0A),
        accent: const Color(0xFFFF9800),
        iconBg: const Color(0xFFE65100),
        icon: Icons.warning_rounded,
      );
    case _NotifType.info:
      return _NotifConfig(
        bg: const Color(0xFF0D2137),
        accent: const Color(0xFF42A5F5),
        iconBg: const Color(0xFF1565C0),
        icon: Icons.info_rounded,
      );
    case _NotifType.partial:
      return _NotifConfig(
        bg: const Color(0xFF0D1B2E),
        accent: const Color(0xFF90CAF9),
        iconBg: const Color(0xFF0D47A1),
        icon: Icons.payments_rounded,
      );
  }
}

class _NotifConfig {
  final Color bg, accent, iconBg;
  final IconData icon;
  const _NotifConfig({
    required this.bg,
    required this.accent,
    required this.iconBg,
    required this.icon,
  });
}

class _NotifCard extends StatelessWidget {
  final _NotifType type;
  final _NotifConfig config;
  final String title, message;
  final IconData icon;
  final VoidCallback? action;
  final String? actionLabel;

  const _NotifCard({
    required this.type,
    required this.config,
    required this.title,
    required this.message,
    required this.icon,
    this.action,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: config.bg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Accent left bar
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 4, color: config.accent),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon badge
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: config.iconBg,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: config.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  // Text + action
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.80),
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                        if (action != null && actionLabel != null) ...[
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () async {
                              Get.closeCurrentSnackbar();
                              // Tunggu animasi close selesai sebelum callback
                              await Future.delayed(
                                  const Duration(milliseconds: 200));
                              action!();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: config.accent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: config.accent.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Text(
                                actionLabel!,
                                style: TextStyle(
                                  color: config.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Dismiss
                  GestureDetector(
                    onTap: () => Get.closeCurrentSnackbar(),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white.withValues(alpha: 0.45),
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}