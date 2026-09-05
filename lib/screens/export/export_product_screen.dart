import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:io';
import '../../services/permission_helper.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
const _blue   = Color(0xFF2196F3);
const _green  = Color(0xFF1B7F4A);

const _red    = Color(0xFFE53935);
const _orange = Color(0xFFF57C00);
const _teal   = Color(0xFF00897B);
const _ink    = Color(0xFF111827);
const _inkLt  = Color(0xFF6B7280);
const _surf   = Color(0xFFF8FAFC);
const _bdr    = Color(0xFFE2E8F0);

// ─────────────────────────────────────────────────────────────────────────────

class ExportProductScreen extends StatefulWidget {
  const ExportProductScreen({super.key});

  @override
  State<ExportProductScreen> createState() => _ExportProductScreenState();
}

class _ExportProductScreenState extends State<ExportProductScreen>
    with SingleTickerProviderStateMixin {
  String _filterCategory = 'Semua';
  String _filterStatus   = 'Semua';
  String _exportFormat   = 'CSV';
  bool   _isExporting    = false;
  bool   _isLoadingCount = false;
  int    _estimatedCount = 0;

  final List<String> _categories = [
    'Semua', 'Pulsa', 'Paket Data', 'Token Listrik',
    'Tagihan', 'E-Wallet', 'Jasa Transfer', 'Lainnya',
  ];

  final Map<String, bool> _selectedColumns = {
    'Nama Produk':  true,
    'Kategori':     true,
    'Harga Jual':   true,
    'Harga Beli':   true,
    'Biaya Admin':  true,
    'Deskripsi':    false,
    'Status Aktif': true,
  };

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _fade     = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _refreshCount();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshCount() async {
    setState(() => _isLoadingCount = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      Query q = FirebaseFirestore.instance
          .collection('products')
          .where('userId', isEqualTo: user.uid);

      if (_filterStatus == 'Aktif') {
        q = q.where('isActive', isEqualTo: true);
      } else if (_filterStatus == 'Tidak Aktif') {
        q = q.where('isActive', isEqualTo: false);
      }

      if (_filterCategory != 'Semua') {
        q = q.where('category', isEqualTo: _filterCategory);
      }

      final snap = await q.count().get();
      if (mounted) setState(() => _estimatedCount = snap.count ?? 0);
    } catch (_) {
      if (mounted) setState(() => _estimatedCount = 0);
    } finally {
      if (mounted) setState(() => _isLoadingCount = false);
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // DIRECTORY
  // ════════════════════════════════════════════════════════════════════════

  Future<String?> _getExportDirectory() async {
    if (Platform.isAndroid) {
      // ── Gunakan PermissionHelper yang aman, tidak trigger Activity restart
      await PermissionHelper.requestStoragePermission();

      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (await downloadsDir.exists()) {
        final appDir = Directory('${downloadsDir.path}/STRUSA POS');
        if (!await appDir.exists()) {
          await appDir.create(recursive: true);
        }
        return appDir.path;
      }

      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final appDir = Directory('${extDir.path}/STRUSA POS');
        if (!await appDir.exists()) {
          await appDir.create(recursive: true);
        }
        return appDir.path;
      }

      _showSnack('Perhatian',
          'File disimpan di folder internal. Gunakan tombol Buka untuk mengakses.',
          bg: _orange);
      final docDir = await getApplicationDocumentsDirectory();
      return docDir.path;
    }

    final docDir = await getApplicationDocumentsDirectory();
    return docDir.path;
  }

  // ════════════════════════════════════════════════════════════════════════
  // FIX: eol '\n' (LF) agar lebih kompatibel dengan parser Android
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _writeCsv(String path, List<List<dynamic>> rows) async {
    final csv = const ListToCsvConverter().convert(rows, fieldDelimiter: ',', eol: '\n');
    final bom     = [0xEF, 0xBB, 0xBF];
    final content = utf8.encode(csv);
    await File(path).writeAsBytes([...bom, ...content], flush: true);
  }

  // ════════════════════════════════════════════════════════════════════════
  // FIX: Buka file dengan MIME type eksplisit agar Spreadsheet tidak error
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _openFile(String path) async {
    final isXlsx = path.endsWith('.xlsx');
    await OpenFilex.open(
      path,
      type: isXlsx
          ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          : 'text/csv; charset=UTF-8',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surf,
      appBar: _buildAppBar(),
      body: FadeTransition(
        opacity: _fade,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _summaryCard(),
                  const SizedBox(height: 16),
                  _sectionCard(
                    icon: Icons.filter_list_rounded, iconColor: _teal,
                    title: 'Filter Kategori',
                    child: _categoryFilter(),
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    icon: Icons.toggle_on_rounded, iconColor: _green,
                    title: 'Filter Status Produk',
                    child: _statusFilter(),
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    icon: Icons.view_column_rounded, iconColor: _orange,
                    title: 'Kolom yang Diekspor',
                    subtitle: '${_selectedColumns.values.where((v) => v).length} kolom dipilih',
                    child: _columnSelector(),
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    icon: Icons.insert_drive_file_rounded, iconColor: _green,
                    title: 'Format File',
                    child: _formatSelector(),
                  ),
                  const SizedBox(height: 16),
                  _infoBanner(),
                ],
              ),
            ),
            _buildActionBar(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: _bdr,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _ink),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text('Ekspor Produk',
          style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton.icon(
            onPressed: _resetAll,
            icon: const Icon(Icons.refresh_rounded, size: 16, color: _inkLt),
            label: const Text('Reset', style: TextStyle(color: _inkLt, fontSize: 13)),
            style: TextButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_green, _green.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: _green.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.download_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ekspor Data Produk',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
              Text('Tersimpan ke Downloads/STRUSA POS',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        const Divider(color: Colors.white24, height: 1),
        const SizedBox(height: 14),
        Row(children: [
          _statPill(_filterCategory, Icons.category_rounded),
          const SizedBox(width: 10),
          _statPill(_filterStatus, Icons.toggle_on_rounded),
          const SizedBox(width: 10),
          _statPill(
            _isLoadingCount ? '...' : '$_estimatedCount produk',
            Icons.inventory_2_rounded,
            highlight: true,
          ),
        ]),
      ]),
    );
  }

  Widget _statPill(String label, IconData icon, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? Colors.white.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: highlight ? Border.all(color: Colors.white.withValues(alpha: 0.5)) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: 13),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(
            color: Colors.white, fontSize: 12,
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w500)),
      ]),
    );
  }

  Widget _sectionCard({
    required IconData icon, required Color iconColor,
    required String title, String? subtitle, required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _bdr),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _ink)),
                if (subtitle != null)
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: _inkLt)),
              ]),
            ),
          ]),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 20)),
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: child),
      ]),
    );
  }

  Widget _categoryFilter() {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: _categories.map((cat) {
        final isSelected = _filterCategory == cat;
        return GestureDetector(
          onTap: () { setState(() => _filterCategory = cat); _refreshCount(); },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected ? _teal.withValues(alpha: 0.08) : _surf,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isSelected ? _teal.withValues(alpha: 0.4) : _bdr),
            ),
            child: Text(cat, style: TextStyle(
                fontSize: 12,
                color: isSelected ? _teal : _inkLt,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
          ),
        );
      }).toList(),
    );
  }

  Widget _statusFilter() {
    final options = [
      ('Aktif',       Icons.check_circle_rounded,    _green),
      ('Semua',       Icons.all_inclusive_rounded,    _ink),
      ('Tidak Aktif', Icons.cancel_rounded,           _red),
    ];
    return Row(children: options.map((opt) {
      final isSelected = _filterStatus == opt.$1;
      final color = opt.$3;
      return Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: opt.$1 != 'Tidak Aktif' ? 8 : 0),
          child: GestureDetector(
            onTap: () { setState(() => _filterStatus = opt.$1); _refreshCount(); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.08) : _surf,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isSelected ? color.withValues(alpha: 0.4) : _bdr),
              ),
              child: Column(children: [
                Icon(opt.$2, color: isSelected ? color : _inkLt, size: 18),
                const SizedBox(height: 4),
                Text(opt.$1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                        color: isSelected ? color : _inkLt)),
              ]),
            ),
          ),
        ),
      );
    }).toList());
  }

  Widget _columnSelector() {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: _selectedColumns.entries.map((e) {
        final isOn = e.value;
        return GestureDetector(
          onTap: () => setState(() => _selectedColumns[e.key] = !isOn),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isOn ? _blue.withValues(alpha: 0.08) : _surf,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isOn ? _blue.withValues(alpha: 0.4) : _bdr),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                isOn ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                size: 15, color: isOn ? _blue : _inkLt,
              ),
              const SizedBox(width: 6),
              Text(e.key, style: TextStyle(
                  fontSize: 12,
                  color: isOn ? _blue : _inkLt,
                  fontWeight: isOn ? FontWeight.w600 : FontWeight.normal)),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _formatSelector() {
    final formats = [
      ('CSV',  Icons.table_rows_outlined, _blue,  '.csv — bisa dibuka langsung di Excel / Google Sheets'),
      ('XLSX', Icons.grid_on_rounded,     _green, '.xlsx — format Excel native, lebih kompatibel'),
    ];
    return Column(
      children: formats.map((f) {
        final isSelected = _exportFormat == f.$1;
        return GestureDetector(
          onTap: () => setState(() => _exportFormat = f.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected ? f.$3.withValues(alpha: 0.06) : _surf,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? f.$3.withValues(alpha: 0.4) : _bdr),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: f.$3.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(f.$2, color: f.$3, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.$1, style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13,
                      color: isSelected ? f.$3 : _ink)),
                  Text(f.$4, style: const TextStyle(fontSize: 11, color: _inkLt)),
                ]),
              ),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: f.$3, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 13),
                ),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _teal.withValues(alpha: 0.2)),
      ),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lightbulb_outline_rounded, color: _teal, size: 16),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'File ekspor disimpan di Downloads/STRUSA POS dan bisa dibuka '
            'langsung dari File Manager. Bisa digunakan sebagai template import massal.',
            style: TextStyle(fontSize: 12, color: _teal, height: 1.5),
          ),
        ),
      ]),
    );
  }

  Widget _buildActionBar() {
    final selectedCount = _selectedColumns.values.where((v) => v).length;
    final canExport = selectedCount > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -3)),
        ],
      ),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!canExport)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.info_outline_rounded, size: 13, color: _red),
                const SizedBox(width: 5),
                Text('Pilih minimal 1 kolom untuk ekspor',
                    style: TextStyle(fontSize: 11.5, color: Colors.red[400])),
              ]),
            ),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton.icon(
              onPressed: (_isExporting || !canExport) ? null : _showExportConfirmSheet,
              icon: _isExporting
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.file_download_rounded, size: 20),
              label: Text(
                _isExporting
                    ? 'Mengekspor...'
                    : 'Ekspor${_estimatedCount > 0 ? " $_estimatedCount Produk" : ""}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green, foregroundColor: Colors.white,
                disabledBackgroundColor: _bdr,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _showExportConfirmSheet() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExportProductConfirmSheet(
        filterCategory: _filterCategory,
        filterStatus:   _filterStatus,
        exportFormat:   _exportFormat,
        columnCount:    _selectedColumns.values.where((v) => v).length,
        estimatedRows:  _estimatedCount,
      ),
    );
    if (confirmed == true) await _doExport();
  }

  void _showSnack(String title, String msg, {Color bg = _teal}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.transparent, elevation: 0,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          Text(msg,   style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      ),
      duration: const Duration(seconds: 4),
    ));
  }

  // ════════════════════════════════════════════════════════════════════════
  // EXPORT LOGIC
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _doExport() async {
    setState(() => _isExporting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Pengguna tidak ditemukan');

      Query q = FirebaseFirestore.instance
          .collection('products')
          .where('userId', isEqualTo: user.uid)
          .orderBy('name');

      if (_filterStatus == 'Aktif') {
        q = q.where('isActive', isEqualTo: true);
      } else if (_filterStatus == 'Tidak Aktif') {
        q = q.where('isActive', isEqualTo: false);
      }

      if (_filterCategory != 'Semua') {
        q = q.where('category', isEqualTo: _filterCategory);
      }

      final snapshot = await q.get();

      if (snapshot.docs.isEmpty) {
        _showSnack('Tidak Ada Data', 'Tidak ada produk sesuai filter ini', bg: _orange);
        return;
      }

      final headers = _selectedColumns.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      final dataRows = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final d = doc.data() as Map<String, dynamic>;
        dataRows.add({
          'Nama Produk':  d['name']        ?? '',
          'Kategori':     d['category']    ?? '',
          'Harga Jual':   (d['sellingPrice'] ?? d['price'] ?? 0).toString(),
          'Harga Beli':   (d['costPrice']  ?? 0).toString(),
          'Biaya Admin':  (d['adminFee']   ?? 0).toString(),
          'Deskripsi':    d['description'] ?? '',
          'Status Aktif': (d['isActive'] ?? true) ? 'Aktif' : 'Tidak Aktif',
        });
      }

      final dirPath = await _getExportDirectory();
      if (dirPath == null) {
        _showSnack('Gagal Ekspor', 'Tidak dapat mengakses penyimpanan', bg: _red);
        return;
      }

      final ts   = DateFormat('ddMMyyyy_HHmm').format(DateTime.now());
      String path;

      if (_exportFormat == 'XLSX') {
        final excel = Excel.createExcel();
        final sheet = excel['Produk'];
        excel.delete('Sheet1');
        sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
        for (final row in dataRows) {
          sheet.appendRow(
            headers.map((h) => TextCellValue(row[h]?.toString() ?? '')).toList(),
          );
        }
        path = '$dirPath/produk_$ts.xlsx';
        final bytes = excel.encode();
        if (bytes == null) throw Exception('Gagal encode XLSX');
        await File(path).writeAsBytes(bytes, flush: true);
      } else {
        final rows = <List<dynamic>>[headers];
        for (final row in dataRows) {
          rows.add(headers.map((h) => row[h] ?? '').toList());
        }
        path = '$dirPath/produk_$ts.csv';
        await _writeCsv(path, rows);
      }

      _showSnack(
        'Ekspor Berhasil',
        '${snapshot.docs.length} produk → Downloads/STRUSA POS',
        bg: _green,
      );

      await Future.delayed(const Duration(milliseconds: 500));
      // FIX: gunakan _openFile dengan MIME type eksplisit
      await _openFile(path);
    } catch (e, st) {
      debugPrint('Export product error: $e\n$st');
      _showSnack('Gagal Ekspor', e.toString(), bg: _red);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _resetAll() {
    setState(() {
      _filterCategory = 'Semua';
      _filterStatus   = 'Aktif';
      _exportFormat   = 'CSV';
      _selectedColumns.updateAll((_, __) => true);
      _selectedColumns['Deskripsi'] = false;
    });
    _refreshCount();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// BOTTOM SHEET: Konfirmasi Ekspor Produk
// ════════════════════════════════════════════════════════════════════════════

class _ExportProductConfirmSheet extends StatelessWidget {
  final String filterCategory;
  final String filterStatus;
  final String exportFormat;
  final int    columnCount;
  final int    estimatedRows;

  const _ExportProductConfirmSheet({
    required this.filterCategory,
    required this.filterStatus,
    required this.exportFormat,
    required this.columnCount,
    required this.estimatedRows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: _bdr, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.file_download_rounded, color: _green, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Konfirmasi Ekspor',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
            Text('Periksa pengaturan sebelum melanjutkan',
                style: TextStyle(fontSize: 12, color: _inkLt)),
          ])),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          _statBox('Produk', estimatedRows > 0 ? '$estimatedRows' : '—', Icons.inventory_2_rounded, _green),
          const SizedBox(width: 10),
          _statBox('Kolom', '$columnCount', Icons.view_column_rounded, _teal),
          const SizedBox(width: 10),
          _statBox('Format', exportFormat, Icons.insert_drive_file_rounded,
              exportFormat == 'XLSX' ? _green : _blue),
        ]),
        const SizedBox(height: 14),
        _detailRow(Icons.category_rounded,   'Kategori', filterCategory, _teal),
        _detailRow(Icons.toggle_on_rounded,  'Status',   filterStatus,   _green),
        _detailRow(Icons.folder_rounded,     'Lokasi',   'Downloads/STRUSA POS', _blue),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: SizedBox(height: 48,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                  foregroundColor: _inkLt,
                  side: const BorderSide(color: _bdr),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          )),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: SizedBox(height: 48,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.file_download_rounded, size: 18),
              label: const Text('Ekspor Sekarang', style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _green, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0),
            ),
          )),
        ]),
      ]),
    );
  }

  Widget _statBox(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(height: 5),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: _inkLt), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontSize: 12, color: _inkLt)),
        Expanded(child: Text(value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}