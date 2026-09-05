import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  /// Minta izin storage dengan cara yang aman di semua versi Android.
  /// Android 13+ tidak perlu Permission.storage — langsung akses Downloads.
  /// Android 10-12 perlu request, tapi kita cek dulu sebelum request
  /// agar tidak trigger Activity restart yang tidak perlu.
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Android 13+ (API 33+) — tidak perlu izin storage untuk Downloads
    // Langsung return true, akses Downloads sudah diizinkan by default
    if (await _isAndroid13OrAbove()) return true;

    // Android 10-12 — cek status dulu sebelum request
    final status = await Permission.storage.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;

    // Baru request jika memang belum granted
    final result = await Permission.storage.request();
    return result.isGranted;
  }

  static Future<bool> _isAndroid13OrAbove() async {
    try {
      // SDK 33 = Android 13
      final info = await Process.run('getprop', ['ro.build.version.sdk']);
      final sdk  = int.tryParse(info.stdout.toString().trim()) ?? 0;
      return sdk >= 33;
    } catch (_) {
      return false;
    }
  }
}