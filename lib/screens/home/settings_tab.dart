import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../settings/outlet_management_screen.dart';
import '../settings/printer_settings_screen.dart';
import '../settings/profile_screen.dart';
import '../settings/backup_screen.dart';
import '../settings/cash_flow_screen.dart';
import '../settings/customer_management_screen.dart';
import '../auth/login_screen.dart';
import '../import/import_transaction_screen.dart';
import '../export/export_transaction_screen.dart';
import '../import/import_product_screen.dart';
import '../export/export_product_screen.dart';
import '../report/export_report_screen.dart';
import '../../services/startup_cleanup.dart';
import '../../services/firestore_helper.dart';

// ── Design Tokens ──────────────────────────────────────────────────────────────
const _blue     = Color(0xFF2196F3);
const _blueDark = Color(0xFF1976D2);
const _green    = Color(0xFF1B7F4A);
const _red      = Color(0xFFE53935);
const _purple   = Color(0xFF7C3AED);
const _orange   = Color(0xFFF57C00);
const _ink      = Color(0xFF0F172A);
const _inkMid   = Color(0xFF475569);
const _inkLt    = Color(0xFF94A3B8);
const _bdr      = Color(0xFFE2E8F0);
const _surf     = Color(0xFFF8FAFC);
const _bg       = Color(0xFFF1F5F9);

// ── Key SharedPreferences per user ────────────────────────────────────────────
String _avatarKey(String uid) => 'avatar_path_$uid';

// ── Group model ────────────────────────────────────────────────────────────────
class _SettingsGroup {
  final String label;
  final IconData labelIcon;
  final Color accentColor;
  final List<_SettingsItem> items;

  const _SettingsGroup({
    required this.label,
    required this.labelIcon,
    required this.accentColor,
    required this.items,
  });
}

class _SettingsItem {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;
  final Widget? trailing;

  const _SettingsItem({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
    this.trailing,
  });
}

// ── Sheet Option model ─────────────────────────────────────────────────────────
class _SheetOption {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ══════════════════════════════════════════════════════════════════════════════
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> with RouteAware {
  File? _avatarFile;
  String _version = ''; // ← TAMBAH

  @override
  void initState() {
    super.initState();
    _loadAvatar();
    _loadVersion(); // ← TAMBAH
  }

  // ── Load versi dari pubspec.yaml secara otomatis ───────────────────────────
  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = 'v${info.version}');
  }

  Future<void> _loadAvatar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final path  = prefs.getString(_avatarKey(user.uid));
    if (!mounted) return;
    setState(() {
      _avatarFile = (path != null && File(path).existsSync())
          ? File(path)
          : null;
    });
  }

  Future<void> _goToProfile() async {
    await Get.to(() => const ProfileScreen());
    await _loadAvatar();
  }

  // ── LOGOUT ────────────────────────────────────────────────────────────────
  Future<void> _doLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
      resetWarmUpFlag();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', false);
      await prefs.remove('userEmail');

      await StartupCleanup.reset();
      Get.offAll(() => const LoginScreen());
    } catch (e) {
      debugPrint('[Logout] Error: $e');
      Get.offAll(() => const LoginScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        final user = authSnapshot.data;

        if (authSnapshot.connectionState == ConnectionState.waiting ||
            user == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return Container(
          color: _bg,
          child: ListView(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 20,
              bottom: MediaQuery.of(context).padding.bottom + 24,
            ),
            children: [
              _ProfileCard(
                user: user,
                avatarFile: _avatarFile,
                onTap: _goToProfile,
              ),
              const SizedBox(height: 28),
              ..._buildAllGroups(context),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildAllGroups(BuildContext context) {
    final groups = _getGroups(context);
    final widgets = <Widget>[];
    for (final group in groups) {
      widgets.add(_GroupHeader(group: group));
      widgets.add(const SizedBox(height: 10));
      widgets.add(_GroupCard(group: group));
      widgets.add(const SizedBox(height: 24));
    }
    return widgets;
  }

  List<_SettingsGroup> _getGroups(BuildContext context) {
    return [
      // ── AKUN ──────────────────────────────────────────────────────────────
      _SettingsGroup(
        label: 'Akun & Outlet',
        labelIcon: Icons.manage_accounts_outlined,
        accentColor: _blue,
        items: [
          _SettingsItem(
            icon: Icons.person_outline_rounded,
            iconColor: _blue,
            title: 'Profil Pengguna',
            subtitle: 'Nama, foto, dan informasi akun',
            onTap: _goToProfile,
          ),
          _SettingsItem(
            icon: Icons.store_outlined,
            iconColor: const Color(0xFF0288D1),
            title: 'Manajemen Outlet',
            subtitle: 'Tambah, edit, dan kelola outlet',
            onTap: () => Get.to(() => const OutletManagementScreen()),
          ),
          _SettingsItem(
            icon: Icons.people_alt_outlined,
            iconColor: const Color(0xFF0288D1),
            title: 'Data Pelanggan',
            subtitle: 'Lihat, tambah, edit, dan hapus pelanggan',
            onTap: () => Get.to(() => const CustomerManagementScreen()),
          ),
        ],
      ),

      // ── KEUANGAN ──────────────────────────────────────────────────────────
      _SettingsGroup(
        label: 'Keuangan',
        labelIcon: Icons.account_balance_outlined,
        accentColor: _green,
        items: [
          _SettingsItem(
            icon: Icons.account_balance_wallet_outlined,
            iconColor: _green,
            title: 'Arus Kas',
            subtitle: 'Pantau pergerakan pendapatan harian',
            onTap: () => Get.to(() => const CashFlowScreen()),
          ),
        ],
      ),

      // ── IMPORT & EKSPOR ───────────────────────────────────────────────────
      _SettingsGroup(
        label: 'Import & Ekspor',
        labelIcon: Icons.swap_vert_rounded,
        accentColor: _orange,
        items: [
          _SettingsItem(
            icon: Icons.file_upload_outlined,
            iconColor: _blue,
            title: 'Import Data',
            subtitle: 'Produk atau transaksi dari file CSV/Excel',
            onTap: () => _showImportSheet(context),
          ),
          _SettingsItem(
            icon: Icons.file_download_outlined,
            iconColor: _green,
            title: 'Ekspor Data',
            subtitle: 'Produk, transaksi, atau laporan ke file',
            onTap: () => _showExportSheet(context),
          ),
        ],
      ),

      // ── PERANGKAT ─────────────────────────────────────────────────────────
      _SettingsGroup(
        label: 'Perangkat & Backup',
        labelIcon: Icons.devices_outlined,
        accentColor: _purple,
        items: [
          _SettingsItem(
            icon: Icons.print_outlined,
            iconColor: _purple,
            title: 'Pengaturan Printer',
            subtitle: 'Kelola koneksi printer bluetooth',
            onTap: () => Get.to(() => const PrinterSettingsScreen()),
          ),
          _SettingsItem(
            icon: Icons.backup_outlined,
            iconColor: const Color(0xFF5B21B6),
            title: 'Backup & Sinkronisasi',
            subtitle: 'Kelola cadangan dan sinkronisasi data',
            onTap: () => Get.to(() => const BackupScreen()),
          ),
        ],
      ),

      // ── LAINNYA ───────────────────────────────────────────────────────────
      _SettingsGroup(
        label: 'Lainnya',
        labelIcon: Icons.more_horiz_rounded,
        accentColor: _inkMid,
        items: [
          _SettingsItem(
            icon: Icons.info_outline_rounded,
            iconColor: _inkMid,
            title: 'Tentang Aplikasi',
            subtitle: 'Versi, lisensi, dan informasi developer',
            onTap: () => _showAboutSheet(context),
            // ── UBAH: dari hardcode 'v1.0.3' → pakai _version ─────────────
            trailing: _version.isEmpty
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _version, // ← otomatis dari pubspec.yaml
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _blue),
                    ),
                  ),
          ),
          _SettingsItem(
            icon: Icons.logout_rounded,
            title: 'Keluar',
            subtitle: 'Keluar dari sesi akun ini',
            onTap: () => _showLogoutSheet(context),
            isDestructive: true,
          ),
        ],
      ),
    ];
  }

  // ── SHEET: IMPORT ──────────────────────────────────────────────────────────
  void _showImportSheet(BuildContext context) {
    _showOptionSheet(
      context: context,
      icon: Icons.file_upload_outlined,
      iconColor: _blue,
      title: 'Import Data',
      subtitle: 'Pilih jenis data yang ingin diimport',
      options: [
        _SheetOption(
          icon: Icons.inventory_2_outlined,
          iconColor: _green,
          title: 'Import Produk',
          subtitle: 'Tambah produk massal dari file CSV/Excel',
          onTap: () {
            Navigator.pop(context);
            Get.to(() => const ImportProductScreen());
          },
        ),
        _SheetOption(
          icon: Icons.receipt_long_outlined,
          iconColor: _blue,
          title: 'Import Transaksi',
          subtitle: 'Impor riwayat transaksi dari file CSV/Excel',
          onTap: () {
            Navigator.pop(context);
            Get.to(() => const ImportTransactionScreen());
          },
        ),
      ],
    );
  }

  // ── SHEET: EKSPOR ──────────────────────────────────────────────────────────
  void _showExportSheet(BuildContext context) {
    _showOptionSheet(
      context: context,
      icon: Icons.file_download_outlined,
      iconColor: _green,
      title: 'Ekspor Data',
      subtitle: 'Pilih jenis data yang ingin diekspor',
      options: [
        _SheetOption(
          icon: Icons.inventory_2_outlined,
          iconColor: _green,
          title: 'Ekspor Produk',
          subtitle: 'Unduh daftar produk ke file CSV/Excel',
          onTap: () {
            Navigator.pop(context);
            Get.to(() => const ExportProductScreen());
          },
        ),
        _SheetOption(
          icon: Icons.receipt_long_outlined,
          iconColor: _blue,
          title: 'Ekspor Transaksi',
          subtitle: 'Unduh riwayat transaksi ke file CSV/Excel',
          onTap: () {
            Navigator.pop(context);
            Get.to(() => const ExportTransactionScreen());
          },
        ),
        _SheetOption(
          icon: Icons.assessment_outlined,
          iconColor: _purple,
          title: 'Ekspor Laporan',
          subtitle: 'Laporan detail atau ringkasan per periode',
          onTap: () {
            Navigator.pop(context);
            Get.to(() => const ExportReportScreen());
          },
        ),
      ],
    );
  }

  // ── SHEET: TENTANG ─────────────────────────────────────────────────────────
  void _showAboutSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            const SizedBox(height: 28),
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_blue, _blueDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: Image.asset('assets/logo.png',
                    width: 72, height: 72, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Strusa',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _ink)),
            const SizedBox(height: 6),
            // ── UBAH: dari hardcode 'Versi 1.0.3' → pakai _version ─────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _blue.withValues(alpha: 0.2)),
              ),
              child: Text(
                _version.isEmpty ? 'Memuat...' : 'Versi ${_version.replaceFirst('v', '')}',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _blue),
              ),
            ),
            const SizedBox(height: 4),
            const Text('Aplikasi Kasir dan POS Modern',
                style: TextStyle(fontSize: 13, color: _inkLt)),
            const SizedBox(height: 24),
            _aboutRow(
                Icons.business_rounded, 'Developer', 'Strusa Dev Team'),
            const SizedBox(height: 8),
            _aboutRow(Icons.copyright_rounded, 'Hak Cipta',
                '© 2026 Strusa POS'),
            const SizedBox(height: 8),
            _aboutRow(Icons.gavel_rounded, 'Lisensi', 'Proprietary'),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Tutup',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── SHEET: LOGOUT ──────────────────────────────────────────────────────────
  void _showLogoutSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            const SizedBox(height: 28),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout_rounded, color: _red, size: 28),
            ),
            const SizedBox(height: 16),
            const Text('Keluar dari Akun?',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _ink)),
            const SizedBox(height: 8),
            const Text(
              'Anda akan keluar dari sesi ini.\nPastikan data sudah tersimpan sebelum melanjutkan.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _inkLt, height: 1.5),
            ),
            const SizedBox(height: 28),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _inkMid,
                      side: const BorderSide(color: _bdr),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Batal',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _doLogout();
                    },
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Keluar',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ── GENERIC OPTION SHEET ───────────────────────────────────────────────────
  void _showOptionSheet({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required List<_SheetOption> options,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: _sheetHandle()),
            const SizedBox(height: 20),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: _ink)),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: _inkLt)),
                  ]),
            ]),
            const SizedBox(height: 20),
            ...options.map((opt) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: opt.onTap,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: opt.iconColor.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: opt.iconColor.withValues(alpha: 0.18)),
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: opt.iconColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(opt.icon,
                                color: opt.iconColor, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(opt.title,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: _ink)),
                                  const SizedBox(height: 2),
                                  Text(opt.subtitle,
                                      style: const TextStyle(
                                          fontSize: 12, color: _inkLt)),
                                ]),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: opt.iconColor.withValues(alpha: 0.6)),
                        ]),
                      ),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ── HELPERS ────────────────────────────────────────────────────────────────
  Widget _sheetHandle() => Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
            color: _bdr, borderRadius: BorderRadius.circular(2)),
      );

  Widget _aboutRow(IconData icon, String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _surf,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _bdr),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: _blue),
          const SizedBox(width: 10),
          Text('$label  ',
              style: const TextStyle(fontSize: 12, color: _inkLt)),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _ink)),
          ),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// PROFILE CARD
// ══════════════════════════════════════════════════════════════════════════════
class _ProfileCard extends StatelessWidget {
  final User? user;
  final File? avatarFile;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.user,
    required this.avatarFile,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E88E5), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipOval(
              child: avatarFile != null
                  ? Image.file(avatarFile!,
                      width: 58, height: 58, fit: BoxFit.cover)
                  : const Icon(Icons.person_rounded,
                      size: 30, color: Color(0xFF1976D2)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.displayName ?? 'Pengguna',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3),
                ),
                const SizedBox(height: 3),
                Text(
                  user?.email ?? '–',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                              color: Color(0xFF69F0AE),
                              shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        const Text('Aktif',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ]),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.edit_outlined,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GROUP HEADER
// ══════════════════════════════════════════════════════════════════════════════
class _GroupHeader extends StatelessWidget {
  final _SettingsGroup group;
  const _GroupHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: group.accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(group.labelIcon, size: 14, color: group.accentColor),
      ),
      const SizedBox(width: 8),
      Text(
        group.label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: group.accentColor,
          letterSpacing: 0.8,
        ),
      ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// GROUP CARD
// ══════════════════════════════════════════════════════════════════════════════
class _GroupCard extends StatelessWidget {
  final _SettingsGroup group;
  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: List.generate(group.items.length, (i) {
          final item = group.items[i];
          final isLast = i == group.items.length - 1;
          return _SettingsTile(item: item, isLast: isLast);
        }),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// SETTINGS TILE
// ══════════════════════════════════════════════════════════════════════════════
class _SettingsTile extends StatelessWidget {
  final _SettingsItem item;
  final bool isLast;
  const _SettingsTile({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final color = item.isDestructive ? _red : (item.iconColor ?? _blue);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(isLast ? 16 : 0),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, color: color, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: item.isDestructive ? _red : _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        style: const TextStyle(fontSize: 12, color: _inkLt),
                      ),
                    ],
                  ),
                ),
                if (item.trailing != null) ...[
                  item.trailing!,
                  const SizedBox(width: 6),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: item.isDestructive
                      ? _red.withValues(alpha: 0.5)
                      : _inkLt,
                ),
              ]),
            ),
          ),
        ),
        if (!isLast)
          const Divider(height: 1, indent: 70, endIndent: 16, color: _bdr),
      ],
    );
  }
}