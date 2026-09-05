import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'home_tab.dart';
import 'transaction_tab.dart';
import 'report_tab.dart';
import 'settings_tab.dart';
import '../transaction/new_transaction_screen.dart';
import '../import/import_transaction_screen.dart';
import '../export/export_transaction_screen.dart';
import '../report/export_report_screen.dart';
import '../../services/startup_cleanup.dart';
import '../../services/firestore_helper.dart';

const _kBluePrimary  = Color(0xFF2196F3);
const _kBlueDark     = Color(0xFF1565C0);
const _kBlueDarker   = Color(0xFF0D47A1);
const _kBlueMid      = Color(0xFF1976D2);
const _kBlueAccent   = Color(0xFF42A5F5);
const _kBlueLight    = Color(0xFFBBDEFB);

class MainScreenController extends GetxController {
  final currentIndex = 0.obs;
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  late final MainScreenController _ctrl;

  final GlobalKey<TransactionTabState> _transactionKey =
      GlobalKey<TransactionTabState>();

  DateTime? _lastBackPressed;
  OverlayEntry? _exitToastEntry;

  final List<IconData> _iconList = [
    Icons.home_rounded,
    Icons.receipt_long_rounded,
    Icons.bar_chart_rounded,
    Icons.settings_rounded,
  ];

  final List<String> _titleList = [
    'Beranda',
    'Transaksi',
    'Laporan',
    'Pengaturan',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (Get.isRegistered<MainScreenController>()) {
      _ctrl = Get.find<MainScreenController>();
    } else {
      _ctrl = Get.put(MainScreenController(), permanent: true);
    }

    StartupCleanup.run();
  }

  @override
  void dispose() {
    _removeExitToast();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      recordAppActive();
    } else if (state == AppLifecycleState.resumed) {
      onAppResume();
    }
  }

  // ── Back handler ──────────────────────────────────────────────────────────

  void _handleBack() {
    final isAtHome = _ctrl.currentIndex.value == 0;

    // Jika bukan di tab Home → pindah ke Home, selesai
    if (!isAtHome) {
      _ctrl.currentIndex.value = 0;
      return;
    }

    // Sudah di Home → cek double press
    final now = DateTime.now();
    final isSecondPress = _lastBackPressed != null &&
        now.difference(_lastBackPressed!) < const Duration(seconds: 2);

    if (isSecondPress) {
      // Klik kedua → keluar app langsung (bukan pop route)
      _removeExitToast();
      SystemNavigator.pop(); // ← FIX: langsung exit, bukan Navigator.pop
      return;
    }

    // Klik pertama → tampilkan toast
    _lastBackPressed = now;
    _showExitToast();
  }

  void _showExitToast() {
    _removeExitToast();
    final overlay = Overlay.of(context);
    _exitToastEntry = OverlayEntry(
      builder: (_) => _ExitToast(onDismissed: _removeExitToast),
    );
    overlay.insert(_exitToastEntry!);
  }

  void _removeExitToast() {
    _exitToastEntry?.remove();
    _exitToastEntry = null;
  }

  // ── Screen builder ────────────────────────────────────────────────────────

  Widget _buildScreen(int index) {
    switch (index) {
      case 0: return const HomeTab();
      case 1: return TransactionTab(key: _transactionKey);
      case 2: return const ReportTab();
      case 3: return const SettingsTab();
      default: return const HomeTab();
    }
  }

  // ── More bottom sheet ─────────────────────────────────────────────────────

  void _showMoreBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Kelola Transaksi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                      color: Color(0xFF111827))),
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Pilih aksi yang ingin dilakukan',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            const SizedBox(height: 20),
            _actionTile(
              context: context,
              icon: Icons.upload_file_rounded,
              iconBgColor: const Color(0xFFE3F2FD),
              iconColor: _kBluePrimary,
              title: 'Import Transaksi',
              subtitle: 'Unggah data dari file Excel atau CSV',
              onTap: () {
                Navigator.pop(context);
                Get.to(() => const ImportTransactionScreen());
              },
            ),
            const SizedBox(height: 12),
            _actionTile(
              context: context,
              icon: Icons.file_download_outlined,
              iconBgColor: const Color(0xFFE8F5E9),
              iconColor: const Color(0xFF4CAF50),
              title: 'Export Transaksi',
              subtitle: 'Unduh data transaksi ke file Excel',
              onTap: () {
                Navigator.pop(context);
                Get.to(() => const ExportTransactionScreen());
              },
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required BuildContext context,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.grey[50],
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w600, color: Color(0xFF111827))),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final index = _ctrl.currentIndex.value;
      return PopScope(
        // ── FIX: canPop tetap false, semua logika keluar di _handleBack ──────
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _handleBack(); // sinkron, tidak async
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(_titleList[index]),
            backgroundColor: _kBluePrimary,
            centerTitle: true,
            elevation: 0,
            automaticallyImplyLeading: false,
            actions: index == 1
                ? [
                    IconButton(
                      icon: const Icon(Icons.filter_list_rounded),
                      tooltip: 'Filter',
                      onPressed: () =>
                          _transactionKey.currentState?.showFilterBottomSheet(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert_rounded),
                      tooltip: 'Lainnya',
                      onPressed: () => _showMoreBottomSheet(context),
                    ),
                  ]
                : index == 2
                    ? [
                        IconButton(
                          icon: const Icon(Icons.file_download_outlined),
                          onPressed: () =>
                              Get.to(() => const ExportReportScreen()),
                        ),
                      ]
                    : null,
          ),
          body: _buildScreen(index),
          floatingActionButton: FloatingActionButton(
            backgroundColor: _kBluePrimary,
            child: const Icon(Icons.add, size: 32),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NewTransactionScreen()),
            ),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
          bottomNavigationBar: AnimatedBottomNavigationBar(
            icons: _iconList,
            activeIndex: index,
            gapLocation: GapLocation.center,
            notchSmoothness: NotchSmoothness.softEdge,
            leftCornerRadius: 20,
            rightCornerRadius: 20,
            activeColor: _kBluePrimary,
            inactiveColor: Colors.grey,
            onTap: (i) => _ctrl.currentIndex.value = i,
          ),
        ),
      );
    });
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// EXIT TOAST
// ══════════════════════════════════════════════════════════════════════════════

class _ExitToast extends StatefulWidget {
  final VoidCallback onDismissed;
  const _ExitToast({required this.onDismissed});

  @override
  State<_ExitToast> createState() => _ExitToastState();
}

class _ExitToastState extends State<_ExitToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _progressAnim;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));

    _fadeAnim = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );

    _scaleAnim = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );

    _progressAnim = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 1.0)),
    );

    _ctrl.forward();

    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) _dismiss();
    });
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.animateTo(0.0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInBack);
    widget.onDismissed();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Positioned(
      bottom: bottomPadding + 88,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Material(color: Colors.transparent, child: _buildCard()),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_kBlueDark, _kBlueDarker],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _kBlueAccent.withValues(alpha: 0.30),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _kBlueDarker.withValues(alpha: 0.55),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: -2,
          ),
          BoxShadow(
            color: _kBluePrimary.withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              children: [
                const _PulsingIcon(),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Keluar aplikasi?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Tekan tombol kembali sekali lagi',
                        style: TextStyle(
                          color: _kBlueLight.withValues(alpha: 0.75),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _CountdownRing(progressAnim: _progressAnim),
              ],
            ),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            child: AnimatedBuilder(
              animation: _progressAnim,
              builder: (_, __) => LinearProgressIndicator(
                value: _progressAnim.value,
                minHeight: 3,
                backgroundColor: _kBlueMid.withValues(alpha: 0.30),
                valueColor: const AlwaysStoppedAnimation<Color>(_kBlueAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pulsing icon ──────────────────────────────────────────────────────────────

class _PulsingIcon extends StatefulWidget {
  const _PulsingIcon();

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) =>
          Transform.scale(scale: _pulse.value, child: child),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: _kBluePrimary.withValues(alpha: 0.28),
          shape: BoxShape.circle,
          border: Border.all(
            color: _kBlueAccent.withValues(alpha: 0.55),
            width: 1.5,
          ),
        ),
        child: const Icon(
          Icons.exit_to_app_rounded,
          color: _kBlueLight,
          size: 22,
        ),
      ),
    );
  }
}

// ── Countdown ring ────────────────────────────────────────────────────────────

class _CountdownRing extends StatelessWidget {
  final Animation<double> progressAnim;
  const _CountdownRing({required this.progressAnim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progressAnim,
      builder: (_, __) {
        final seconds = (progressAnim.value * 2).ceil().clamp(0, 2);
        return SizedBox(
          width: 38,
          height: 38,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  value: progressAnim.value,
                  strokeWidth: 2.5,
                  backgroundColor: _kBlueMid.withValues(alpha: 0.30),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(_kBlueAccent),
                ),
              ),
              Text(
                '$seconds',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}