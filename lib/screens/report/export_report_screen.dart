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

// ── Design tokens ─────────────────────────────────────────────────────────
const _blue   = Color(0xFF2196F3);
const _green  = Color(0xFF1B7F4A);
const _red    = Color(0xFFE53935);
const _orange = Color(0xFFF57C00);
const _teal   = Color(0xFF00897B);
const _purple = Color(0xFF7C3AED);
const _ink    = Color(0xFF111827);
const _inkLt  = Color(0xFF6B7280);
const _surf   = Color(0xFFF8FAFC);
const _bdr    = Color(0xFFE2E8F0);

class ExportReportScreen extends StatefulWidget {
  const ExportReportScreen({super.key});

  @override
  State<ExportReportScreen> createState() => _ExportReportScreenState();
}

class _ExportReportScreenState extends State<ExportReportScreen>
    with SingleTickerProviderStateMixin {

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate   = DateTime.now();

  String _filterStatus = 'Semua';
  String _reportType   = 'Transaksi';
  String _exportFormat = 'CSV';
  bool   _isExporting    = false;
  bool   _isLoadingCount = false;
  int    _estimatedCount = 0;

  final Map<String, bool> _selectedColumns = {
    'Tanggal':          true,
    'Jam':              true,
    'Produk':           true,
    'Kategori':         true,
    'No. Pelanggan':    true,
    'Nama Pelanggan':   true,
    'Nominal':          true,
    'Biaya Admin':      false,
    'Total':            true,
    'Metode Bayar':     true,
    'Status':           true,
    'Sisa Hutang':      false,
  };

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fade;
  final _dateFormat = DateFormat('dd MMM yyyy', 'id_ID');

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
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

      final snap = await FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: user.uid)
          .where('date',
              isGreaterThanOrEqualTo:
                  Timestamp.fromDate(_startOfDay(_startDate)))
          .where('date',
              isLessThanOrEqualTo:
                  Timestamp.fromDate(_endOfDay(_endDate)))
          .get();

      int count = snap.docs.length;
      if (_filterStatus == 'Lunas') {
        count = snap.docs
            .where((d) => (d.data())['isPaid'] == true)
            .length;
      } else if (_filterStatus == 'Belum Lunas') {
        count = snap.docs
            .where((d) => (d.data())['isPaid'] != true)
            .length;
      }

      if (mounted) setState(() => _estimatedCount = count);
    } catch (_) {
      if (mounted) setState(() => _estimatedCount = 0);
    } finally {
      if (mounted) setState(() => _isLoadingCount = false);
    }
  }

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

  // FIX: eol '\n' (LF) agar lebih kompatibel dengan parser Android
  Future<void> _writeCsv(String path, List<List<dynamic>> rows) async {
    final csv = const ListToCsvConverter().convert(rows, fieldDelimiter: ',', eol: '\n');
    final bom     = [0xEF, 0xBB, 0xBF];
    final content = utf8.encode(csv);
    await File(path).writeAsBytes([...bom, ...content], flush: true);
  }

  // FIX: Buka file dengan MIME type eksplisit agar Spreadsheet tidak error
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
                    icon: Icons.date_range_rounded, iconColor: _blue,
                    title: 'Rentang Tanggal',
                    child: _dateRangeSelector(),
                  ),
                  const SizedBox(height: 12),
                  _quickDatePresets(),
                  const SizedBox(height: 16),
                  _sectionCard(
                    icon: Icons.filter_list_rounded, iconColor: _teal,
                    title: 'Filter Status',
                    child: _statusFilter(),
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    icon: Icons.description_rounded, iconColor: _purple,
                    title: 'Jenis Laporan',
                    child: _reportTypeSelector(),
                  ),
                  const SizedBox(height: 16),
                  if (_reportType == 'Transaksi') ...[
                    _sectionCard(
                      icon: Icons.view_column_rounded, iconColor: _orange,
                      title: 'Kolom yang Diekspor',
                      subtitle:
                          '${_selectedColumns.values.where((v) => v).length} kolom dipilih',
                      child: _columnSelector(),
                    ),
                    const SizedBox(height: 16),
                  ],
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
      title: const Text('Ekspor Laporan',
          style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton.icon(
            onPressed: _resetAll,
            icon: const Icon(Icons.refresh_rounded, size: 16, color: _inkLt),
            label: const Text('Reset', style: TextStyle(color: _inkLt, fontSize: 13)),
            style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ),
        ),
      ],
    );
  }

  Widget _summaryCard() {
    final days = _endDate.difference(_startDate).inDays + 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_purple, _purple.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: _purple.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.assessment_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Ekspor Laporan',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
              Text('Tersimpan ke Downloads/STRUSA POS',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        const Divider(color: Colors.white24, height: 1),
        const SizedBox(height: 14),
        Row(children: [
          _statPill('${days}h', Icons.calendar_today_rounded),
          const SizedBox(width: 10),
          _statPill(_filterStatus, Icons.filter_alt_rounded),
          const SizedBox(width: 10),
          _statPill(
            _isLoadingCount ? '...' : '$_estimatedCount transaksi',
            Icons.receipt_long_rounded,
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
        border: highlight
            ? Border.all(color: Colors.white.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: 13),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w500)),
      ]),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _bdr)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: _ink)),
                if (subtitle != null)
                  Text(subtitle,
                      style: const TextStyle(fontSize: 11, color: _inkLt)),
              ]),
            ),
          ]),
        ),
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 20)),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: child),
      ]),
    );
  }

  Widget _dateRangeSelector() {
    return Row(children: [
      Expanded(child: _dateTile(
        label: 'Dari', date: _startDate,
        onTap: () async {
          final d = await showDatePicker(
            context: context, initialDate: _startDate,
            firstDate: DateTime(2020), lastDate: _endDate,
          );
          if (d != null) { setState(() => _startDate = d); _refreshCount(); }
        },
      )),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Container(width: 20, height: 1.5, color: _bdr),
      ),
      Expanded(child: _dateTile(
        label: 'Sampai', date: _endDate,
        onTap: () async {
          final d = await showDatePicker(
            context: context, initialDate: _endDate,
            firstDate: _startDate, lastDate: DateTime.now(),
          );
          if (d != null) { setState(() => _endDate = d); _refreshCount(); }
        },
      )),
    ]);
  }

  Widget _dateTile({
    required String label, required DateTime date, required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: _surf, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _bdr)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10, color: _inkLt, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.calendar_month_rounded, size: 14, color: _blue),
            const SizedBox(width: 6),
            Expanded(child: Text(_dateFormat.format(date),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _ink))),
          ]),
        ]),
      ),
    );
  }

  Widget _quickDatePresets() {
    final presets = [
      ('7 Hari', 7), ('30 Hari', 30), ('3 Bulan', 90), ('6 Bulan', 180), ('1 Tahun', 365)
    ];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: presets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final days  = presets[i].$2;
          final label = presets[i].$1;
          final isActive = _endDate.difference(_startDate).inDays == days - 1;
          return GestureDetector(
            onTap: () {
              setState(() {
                _endDate   = DateTime.now();
                _startDate = DateTime.now().subtract(Duration(days: days - 1));
              });
              _refreshCount();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isActive ? _blue : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isActive ? _blue : _bdr),
              ),
              alignment: Alignment.center,
              child: Text(label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: isActive ? Colors.white : _inkLt)),
            ),
          );
        },
      ),
    );
  }

  Widget _statusFilter() {
    final options = [
      ('Semua',       Icons.all_inclusive_rounded, _ink),
      ('Lunas',       Icons.check_circle_rounded,  _green),
      ('Belum Lunas', Icons.pending_rounded,       _orange),
    ];
    return Row(
      children: options.map((opt) {
        final isSelected = _filterStatus == opt.$1;
        final color = opt.$3;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: opt.$1 != 'Belum Lunas' ? 8 : 0),
            child: GestureDetector(
              onTap: () {
                setState(() => _filterStatus = opt.$1);
                _refreshCount();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.08) : _surf,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: isSelected ? color.withValues(alpha: 0.4) : _bdr),
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
      }).toList(),
    );
  }

  Widget _reportTypeSelector() {
    final types = [
      ('Transaksi', Icons.receipt_long_rounded, _blue,
          'Detail setiap transaksi dengan kolom yang bisa dipilih'),
      ('Ringkasan', Icons.bar_chart_rounded, _purple,
          'Rekapitulasi per kategori, total pendapatan & keuntungan'),
    ];
    return Column(
      children: types.map((t) {
        final isSelected = _reportType == t.$1;
        return GestureDetector(
          onTap: () => setState(() => _reportType = t.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected ? t.$3.withValues(alpha: 0.06) : _surf,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? t.$3.withValues(alpha: 0.4) : _bdr),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: t.$3.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(t.$2, color: t.$3, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.$1, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                    color: isSelected ? t.$3 : _ink)),
                Text(t.$4, style: const TextStyle(fontSize: 11, color: _inkLt)),
              ])),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: t.$3, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 13),
                ),
            ]),
          ),
        );
      }).toList(),
    );
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
              Icon(isOn ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  size: 15, color: isOn ? _blue : _inkLt),
              const SizedBox(width: 6),
              Text(e.key, style: TextStyle(fontSize: 12,
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
      ('CSV',  Icons.table_rows_outlined, _blue,
          '.csv — bisa dibuka langsung di Excel / Google Sheets'),
      ('XLSX', Icons.grid_on_rounded,     _green,
          '.xlsx — format Excel native, lebih kompatibel'),
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
                decoration: BoxDecoration(color: f.$3.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
                child: Icon(f.$2, color: f.$3, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(f.$1, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                    color: isSelected ? f.$3 : _ink)),
                Text(f.$4, style: const TextStyle(fontSize: 11, color: _inkLt)),
              ])),
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
        Expanded(child: Text(
          'File tersimpan di Downloads/STRUSA POS dan bisa dibuka dari File Manager. '
          'Laporan Ringkasan mencakup total per kategori dan estimasi keuntungan.',
          style: TextStyle(fontSize: 12, color: _teal, height: 1.5),
        )),
      ]),
    );
  }

  Widget _buildActionBar() {
    final selectedCount = _selectedColumns.values.where((v) => v).length;
    final canExport = _reportType == 'Ringkasan' || selectedCount > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12, offset: const Offset(0, -3))],
      ),
      child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
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
              _isExporting ? 'Mengekspor...'
                  : 'Ekspor${_estimatedCount > 0 ? " $_estimatedCount Transaksi" : ""}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _bdr,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 8),
      ])),
    );
  }

  Future<void> _showExportConfirmSheet() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExportReportConfirmSheet(
        startDate:     _startDate,
        endDate:       _endDate,
        filterStatus:  _filterStatus,
        reportType:    _reportType,
        exportFormat:  _exportFormat,
        columnCount:   _reportType == 'Ringkasan'
            ? 0
            : _selectedColumns.values.where((v) => v).length,
        estimatedRows: _estimatedCount,
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

  Future<void> _doExport() async {
    setState(() => _isExporting = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Pengguna tidak ditemukan');

      final allSnap = await FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: user.uid)
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay(_startDate)))
          .where('date',
              isLessThanOrEqualTo:   Timestamp.fromDate(_endOfDay(_endDate)))
          .orderBy('date', descending: false)
          .get();

      final docs = allSnap.docs.where((doc) {
        final d = doc.data();
        if (_filterStatus == 'Lunas')       return d['isPaid'] == true;
        if (_filterStatus == 'Belum Lunas') return d['isPaid'] != true;
        return true;
      }).toList();

      if (docs.isEmpty) {
        _showSnack('Tidak Ada Data', 'Tidak ada transaksi di periode ini', bg: _orange);
        return;
      }

      final dirPath = await _getExportDirectory();
      if (dirPath == null) {
        _showSnack('Gagal Ekspor', 'Tidak dapat mengakses penyimpanan', bg: _red);
        return;
      }

      final ts = DateFormat('ddMMyyyy_HHmm').format(DateTime.now());
      String path;

      if (_reportType == 'Ringkasan') {
        path = await _buildSummaryReport(docs, dirPath, ts);
      } else {
        path = await _buildDetailReport(docs, dirPath, ts);
      }

      _showSnack(
        'Ekspor Berhasil',
        '${docs.length} transaksi → Downloads/STRUSA POS',
        bg: _green,
      );
      await Future.delayed(const Duration(milliseconds: 500));
      // FIX: gunakan _openFile dengan MIME type eksplisit
      await _openFile(path);
    } catch (e, st) {
      debugPrint('Export report error: $e\n$st');
      _showSnack('Gagal Ekspor', e.toString(), bg: _red);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<String> _buildDetailReport(
      List<QueryDocumentSnapshot> docs, String dir, String ts) async {
    final headers = _selectedColumns.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    final dataRows = <Map<String, dynamic>>[];
    for (final doc in docs) {
      final d          = doc.data() as Map<String, dynamic>;
      final date       = (d['date'] as Timestamp).toDate();
      final isPaid     = d['isPaid'] ?? false;
      final isSebagian = d['isBayarSebagian'] ?? false;
      final status     = isSebagian && !isPaid
          ? 'Bayar Sebagian'
          : isPaid ? 'Lunas' : 'Belum Lunas';

      dataRows.add({
        'Tanggal':        DateFormat('dd/MM/yyyy').format(date),
        'Jam':            DateFormat('HH:mm').format(date),
        'Produk':         d['productName']    ?? '',
        'Kategori':       d['category']       ?? '',
        'No. Pelanggan':  d['customerNumber'] ?? '',
        'Nama Pelanggan': d['customerName']   ?? '',
        'Nominal':        (d['nominal']       ?? 0).toString(),
        'Biaya Admin':    (d['adminFee']      ?? 0).toString(),
        'Total':          (d['totalAmount']   ?? 0).toString(),
        'Metode Bayar':   d['paymentMethod']  ?? '',
        'Status':         status,
        'Sisa Hutang':    (d['remainingDebt'] ?? 0).toString(),
      });
    }

    if (_exportFormat == 'XLSX') {
      final excel = Excel.createExcel();
      final sheet = excel['Detail Transaksi'];
      excel.delete('Sheet1');
      sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
      for (final row in dataRows) {
        sheet.appendRow(headers
            .map((h) => TextCellValue(row[h]?.toString() ?? ''))
            .toList());
      }
      final path = '$dir/laporan_detail_$ts.xlsx';
      final bytes = excel.encode();
      if (bytes == null) throw Exception('Gagal encode XLSX');
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    } else {
      final rows = <List<dynamic>>[headers];
      for (final row in dataRows) {
        rows.add(headers.map((h) => row[h] ?? '').toList());
      }
      final path = '$dir/laporan_detail_$ts.csv';
      await _writeCsv(path, rows);
      return path;
    }
  }

  Future<String> _buildSummaryReport(
      List<QueryDocumentSnapshot> docs, String dir, String ts) async {
    final Map<String, Map<String, dynamic>> summary = {};
    double totalNominal = 0, totalAdmin = 0, totalRevenue = 0;
    int totalLunas = 0, totalBelumLunas = 0;

    for (final doc in docs) {
      final d       = doc.data() as Map<String, dynamic>;
      final cat     = d['category'] ?? 'Lainnya';
      final nominal = (d['nominal']     ?? 0).toDouble();
      final admin   = (d['adminFee']    ?? 0).toDouble();
      final total   = (d['totalAmount'] ?? 0).toDouble();
      final isPaid  = d['isPaid'] ?? false;

      summary.putIfAbsent(cat, () => {
        'kategori': cat, 'jumlah': 0, 'nominal': 0.0,
        'admin': 0.0, 'total': 0.0, 'lunas': 0, 'belum': 0,
      });
      summary[cat]!['jumlah']  = (summary[cat]!['jumlah']  as int)    + 1;
      summary[cat]!['nominal'] = (summary[cat]!['nominal'] as double) + nominal;
      summary[cat]!['admin']   = (summary[cat]!['admin']   as double) + admin;
      summary[cat]!['total']   = (summary[cat]!['total']   as double) + total;
      if (isPaid) {
        summary[cat]!['lunas'] = (summary[cat]!['lunas'] as int) + 1;
        totalLunas++;
      } else {
        summary[cat]!['belum'] = (summary[cat]!['belum'] as int) + 1;
        totalBelumLunas++;
      }
      totalNominal += nominal;
      totalAdmin   += admin;
      totalRevenue += total;
    }

    final headers = [
      'Kategori', 'Jumlah Transaksi', 'Total Nominal',
      'Total Biaya Admin', 'Total Pendapatan', 'Lunas', 'Belum Lunas',
    ];

    final rows = <List<dynamic>>[headers];
    for (final entry in summary.values) {
      rows.add([
        entry['kategori'],
        entry['jumlah'],
        entry['nominal'].toStringAsFixed(0),
        entry['admin'].toStringAsFixed(0),
        entry['total'].toStringAsFixed(0),
        entry['lunas'],
        entry['belum'],
      ]);
    }

    rows.add([]);
    rows.add([
      'TOTAL', docs.length,
      totalNominal.toStringAsFixed(0),
      totalAdmin.toStringAsFixed(0),
      totalRevenue.toStringAsFixed(0),
      totalLunas, totalBelumLunas,
    ]);
    rows.add([]);
    rows.add(['Periode',
        '${_dateFormat.format(_startDate)} s/d ${_dateFormat.format(_endDate)}']);
    rows.add(['Digenerate',
        DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())]);

    if (_exportFormat == 'XLSX') {
      final excel = Excel.createExcel();
      final sheet = excel['Ringkasan'];
      excel.delete('Sheet1');
      for (final row in rows) {
        sheet.appendRow(row.map((c) => TextCellValue(c.toString())).toList());
      }
      final path = '$dir/laporan_ringkasan_$ts.xlsx';
      final bytes = excel.encode();
      if (bytes == null) throw Exception('Gagal encode XLSX');
      await File(path).writeAsBytes(bytes, flush: true);
      return path;
    } else {
      final path = '$dir/laporan_ringkasan_$ts.csv';
      await _writeCsv(path, rows);
      return path;
    }
  }

  DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 0, 0, 0);
  DateTime _endOfDay(DateTime d)   => DateTime(d.year, d.month, d.day, 23, 59, 59);

  void _resetAll() {
    setState(() {
      _startDate    = DateTime.now().subtract(const Duration(days: 30));
      _endDate      = DateTime.now();
      _filterStatus = 'Semua';
      _reportType   = 'Transaksi';
      _exportFormat = 'CSV';
      _selectedColumns.updateAll((_, __) => true);
      _selectedColumns['Biaya Admin'] = false;
      _selectedColumns['Sisa Hutang'] = false;
    });
    _refreshCount();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// BOTTOM SHEET: Konfirmasi Ekspor Laporan
// ════════════════════════════════════════════════════════════════════════════

class _ExportReportConfirmSheet extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final String   filterStatus;
  final String   reportType;
  final String   exportFormat;
  final int      columnCount;
  final int      estimatedRows;

  const _ExportReportConfirmSheet({
    required this.startDate,
    required this.endDate,
    required this.filterStatus,
    required this.reportType,
    required this.exportFormat,
    required this.columnCount,
    required this.estimatedRows,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy', 'id_ID');
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: _bdr, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: _purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.assessment_rounded, color: _purple, size: 22),
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
          _statBox('Transaksi', estimatedRows > 0 ? '$estimatedRows' : '—',
              Icons.receipt_long_rounded, _purple),
          const SizedBox(width: 10),
          _statBox('Jenis', reportType, Icons.description_rounded, _blue),
          const SizedBox(width: 10),
          _statBox('Format', exportFormat, Icons.insert_drive_file_rounded,
              exportFormat == 'XLSX' ? _green : _blue),
        ]),
        const SizedBox(height: 14),
        _detailRow(Icons.date_range_rounded, 'Periode',
            '${df.format(startDate)} – ${df.format(endDate)}', _blue),
        _detailRow(Icons.filter_alt_rounded, 'Status', filterStatus, _teal),
        _detailRow(Icons.folder_rounded,     'Lokasi', 'Downloads/STRUSA POS', _purple),
        if (reportType == 'Transaksi' && columnCount > 0)
          _detailRow(Icons.view_column_rounded, 'Kolom', '$columnCount kolom', _orange),
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
              label: const Text('Ekspor Sekarang',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
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
          Text(label, style: const TextStyle(fontSize: 10, color: _inkLt),
              textAlign: TextAlign.center),
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