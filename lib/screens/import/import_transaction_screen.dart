import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:lottie/lottie.dart';
import 'dart:io';
import '../../services/import_service.dart';
import 'package:permission_handler/permission_handler.dart';

// ─────────────────────────────────────────────
const _requiredFields = ['date', 'productName', 'customerNumber', 'nominal'];

const _supportedDateFormats = [
  'dd/MM/yyyy', 'dd-MM-yyyy', 'yyyy-MM-dd', 'yyyy/MM/dd',
  'MM/dd/yyyy', 'dd MMM yyyy', 'dd MMMM yyyy', 'd/M/yyyy', 'd-M-yyyy',
];

enum _FileType { csv, xlsx, unknown }

// ── Design tokens ──────────────────────────────────────────────────────────
const _blue    = Color(0xFF2196F3);
const _green   = Color(0xFF1B7F4A);
const _red     = Color(0xFFE53935);
const _orange  = Color(0xFFF57C00);
const _teal    = Color(0xFF00897B);
const _ink     = Color(0xFF111827);
const _inkLt   = Color(0xFF6B7280);
const _surf    = Color(0xFFF8FAFC);
const _bdr     = Color(0xFFE2E8F0);

// ─────────────────────────────────────────────────────────────────────────────

class ImportTransactionScreen extends StatefulWidget {
  const ImportTransactionScreen({super.key});
  @override
  State<ImportTransactionScreen> createState() => _ImportTransactionScreenState();
}

class _ImportTransactionScreenState extends State<ImportTransactionScreen>
    with SingleTickerProviderStateMixin {
  final ImportService _importService = ImportService();

  File?     _selectedFile;
  _FileType _fileType    = _FileType.unknown;
  bool      _isAnalyzing = false;
  bool      _isImporting = false;

  Map<String, dynamic>? _analysisResult;
  Map<String, int?>     _mapping      = {};
  List<List<dynamic>>   _editableData = [];
  String?               _detectedDateFormat;

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fade;

  // ── Field defs ──────────────────────────────────────────────────────────
  static const _fieldDefs = [
    {'key': 'date',           'label': 'Tanggal',           'required': true},
    {'key': 'productName',    'label': 'Produk',             'required': true},
    {'key': 'category',       'label': 'Kategori',           'required': false},
    {'key': 'customerNumber', 'label': 'No. Pelanggan',      'required': true},
    {'key': 'customerName',   'label': 'Nama Pelanggan',     'required': false},
    {'key': 'nominal',        'label': 'Nominal',            'required': true},
    {'key': 'adminFee',       'label': 'Biaya Admin',        'required': false},
    {'key': 'isPaid',         'label': 'Status Lunas',       'required': false},
    {'key': 'totalAmount',    'label': 'Harga Jual (Total)', 'required': false},
  ];

  static const _fieldSynonyms = <String, List<String>>{
    'date':           ['tanggal','date','tgl','waktu','time','created_at','transaction_date','trans_date'],
    'productName':    ['produk','product','item','nama produk','product_name','barang','layanan'],
    'category':       ['kategori','category','cat','jenis','type','tipe'],
    'customerNumber': ['nomor','number','no','no.','pelanggan','customer_number','hp','telepon','phone','no_hp','no_pelanggan','msisdn'],
    'customerName':   ['nama','name','customer_name','nama_pelanggan','pelanggan'],
    'nominal':        ['nominal','amount','harga','price','nilai','pembayaran','jumlah'],
    'adminFee':       ['admin','fee','biaya','biaya_admin','admin_fee','charge'],
    'isPaid':         ['status','lunas','paid','is_paid','bayar','payment_status'],
    'totalAmount':    ['harga jual','harga_jual','selling_price','sell_price','jual','hj','total','total_amount','grand_total'],
  };

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fade     = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _requestPermissions();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    try {
      if (await Permission.storage.isDenied) await Permission.storage.request();
      if (await Permission.photos.isDenied)  await Permission.photos.request();
    } catch (e) { debugPrint('Permission error: $e'); }
  }

  // ════════════════════════════════════════════════════════════════════════
  // AUTO-DETECT
  // ════════════════════════════════════════════════════════════════════════

  double _similarity(String a, String b) {
    a = a.toLowerCase().trim(); b = b.toLowerCase().trim();
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final ba = _bigrams(a), bb = _bigrams(b);
    if (ba.isEmpty && bb.isEmpty) return 1.0;
    if (ba.isEmpty || bb.isEmpty) return 0.0;
    return (2 * ba.intersection(bb).length) / (ba.length + bb.length);
  }

  Set<String> _bigrams(String s) {
    final r = <String>{};
    for (int i = 0; i < s.length - 1; i++) { r.add(s.substring(i, i + 2)); }
    return r;
  }

  Map<String, int?> _autoDetectMapping(List headers) {
    final mapping = <String, int?>{};
    final hs = headers.map((h) => h.toString()).toList();
    for (final fd in _fieldDefs) {
      final key      = fd['key'] as String;
      final synonyms = _fieldSynonyms[key] ?? [];
      int?   bestIdx;
      double best = 0.3;
      for (int i = 0; i < hs.length; i++) {
        if (synonyms.any((s) => s == hs[i].toLowerCase())) { bestIdx = i; best = 1.0; break; }
        for (final s in synonyms) {
          final sc = _similarity(hs[i], s);
          if (sc > best) { best = sc; bestIdx = i; }
        }
      }
      mapping[key] = bestIdx;
    }
    return mapping;
  }

  String? _detectDateFormat(List<List<dynamic>> data, int? colIdx) {
    if (colIdx == null || data.isEmpty) return null;
    final samples = data.take(10)
        .where((r) => r.length > colIdx)
        .map((r) => r[colIdx].toString().trim())
        .where((s) => s.isNotEmpty).toList();
    if (samples.isEmpty) return null;
    for (final fmt in _supportedDateFormats) {
      if (samples.every((s) => _tryParseDate(s, fmt))) return fmt;
    }
    return null;
  }

  bool _tryParseDate(String v, String fmt) {
    try { _parseWithFormat(v, fmt); return true; } catch (_) { return false; }
  }

  DateTime _parseWithFormat(String value, String format) {
    final v = value.trim();
    List<String> p;
    switch (format) {
      case 'yyyy-MM-dd': p = v.split('-'); if (p.length != 3) throw Exception(); return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      case 'yyyy/MM/dd': p = v.split('/'); if (p.length != 3) throw Exception(); return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      case 'dd/MM/yyyy': case 'd/M/yyyy': p = v.split('/'); if (p.length != 3) throw Exception(); return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      case 'dd-MM-yyyy': case 'd-M-yyyy': p = v.split('-'); if (p.length != 3) throw Exception(); return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      case 'MM/dd/yyyy': p = v.split('/'); if (p.length != 3) throw Exception(); return DateTime(int.parse(p[2]), int.parse(p[0]), int.parse(p[1]));
      case 'dd MMM yyyy':  return _parseTextMonth(v, short: true);
      case 'dd MMMM yyyy': return _parseTextMonth(v, short: false);
    }
    throw Exception('Unknown: $format');
  }

  static const _shortMonths   = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
  static const _longMonths    = ['january','february','march','april','may','june','july','august','september','october','november','december'];
  static const _shortMonthsId = ['jan','feb','mar','apr','mei','jun','jul','agu','sep','okt','nov','des'];
  static const _longMonthsId  = ['januari','februari','maret','april','mei','juni','juli','agustus','september','oktober','november','desember'];

  DateTime _parseTextMonth(String value, {required bool short}) {
    final parts = value.split(RegExp(r'\s+'));
    if (parts.length != 3) throw Exception();
    final day = int.parse(parts[0]), year = int.parse(parts[2]);
    final ms = parts[1].toLowerCase();
    int month = (short ? _shortMonths : _longMonths).indexOf(ms) + 1;
    if (month == 0) month = (short ? _shortMonthsId : _longMonthsId).indexOf(ms) + 1;
    if (month <= 0) throw Exception();
    return DateTime(year, month, day);
  }

  // ════════════════════════════════════════════════════════════════════════
  // VALIDASI
  // ════════════════════════════════════════════════════════════════════════

  bool get _isMappingValid => _requiredFields.every((f) => _mapping[f] != null);
  List<String> get _missingRequiredFields => _requiredFields.where((f) => _mapping[f] == null).toList();
  String _fieldLabel(String key) => _fieldDefs
      .firstWhere((d) => d['key'] == key, orElse: () => {'label': key})['label'].toString();

  // ════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surf,
      appBar: _buildAppBar(),
      body: _selectedFile == null
          ? _buildFileSelection()
          : _isAnalyzing
              ? _buildAnalyzing()
              : _analysisResult != null
                  ? _buildMappingPreview()
                  : _buildFileSelection(),
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
      title: const Text('Import Data', style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton.icon(
            onPressed: _showHelp,
            icon: const Icon(Icons.help_outline_rounded, size: 17, color: _blue),
            label: const Text('Panduan', style: TextStyle(color: _blue, fontSize: 13)),
            style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ),
        ),
      ],
    );
  }

  // ── File Selection ───────────────────────────────────────────────────────

  Widget _buildFileSelection() {
    return FadeTransition(
      opacity: _fade,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 130, height: 130,
                decoration: BoxDecoration(color: _blue.withValues(alpha: 0.06), shape: BoxShape.circle),
                child: Lottie.asset('assets/lottie/uploading.json', fit: BoxFit.contain),
              ),
              const SizedBox(height: 28),
              const Text('Import Data Transaksi',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _ink, letterSpacing: -0.3)),
              const SizedBox(height: 10),
              // ✅ FIX: Updated subtitle to clarify only .xlsx is supported
              const Text('Pilih file CSV atau Excel (.xlsx).\nFormat .xls lama tidak didukung.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _inkLt, fontSize: 14, height: 1.5)),
              const SizedBox(height: 36),

              _filePickerCard(
                onTap: () => _pickFile(preferXlsx: false),
                icon: Icons.table_rows_outlined, iconBg: _blue.withValues(alpha: 0.1), iconColor: _blue,
                title: 'File CSV', subtitle: 'Dipisahkan koma atau titik koma (.csv)',
                badgeColor: _blue, badgeText: 'CSV',
              ),
              const SizedBox(height: 12),
              _filePickerCard(
                onTap: () => _pickFile(preferXlsx: true),
                icon: Icons.grid_on_rounded, iconBg: _green.withValues(alpha: 0.1), iconColor: _green,
                // ✅ FIX: Removed .xls from subtitle — only .xlsx is supported by the excel package
                title: 'File Excel', subtitle: 'Hanya format .xlsx (Excel 2007+)',
                badgeColor: _green, badgeText: 'XLSX',
              ),
              const SizedBox(height: 24),

              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 32, height: 1, color: _bdr),
                const SizedBox(width: 10),
                const Text('Mendukung .csv dan .xlsx', style: TextStyle(fontSize: 12, color: _inkLt)),
                const SizedBox(width: 10),
                Container(width: 32, height: 1, color: _bdr),
              ]),

              // ✅ FIX: Added XLS warning hint
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _orange.withValues(alpha: 0.2)),
                ),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline_rounded, color: _orange, size: 15),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'File .xls (Excel 97-2003) tidak didukung. Buka di Excel/Google Sheets lalu simpan ulang sebagai .xlsx.',
                      style: TextStyle(fontSize: 11.5, color: _orange, height: 1.5),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filePickerCard({
    required VoidCallback onTap, required IconData icon, required Color iconBg,
    required Color iconColor, required String title, required String subtitle,
    required Color badgeColor, required String badgeText,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: _bdr)),
          child: Row(
            children: [
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: iconColor, size: 22)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: _inkLt)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(8)),
                child: Text(badgeText, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: _inkLt, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Analyzing ────────────────────────────────────────────────────────────

  Widget _buildAnalyzing() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 120, height: 120, child: Lottie.asset('assets/lottie/uploading.json')),
        const SizedBox(height: 24),
        const Text('Menganalisis file...', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 8),
        const Text('Mendeteksi pemetaan kolom & format tanggal', style: TextStyle(color: _inkLt, fontSize: 13)),
        const SizedBox(height: 28),
        const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: _blue)),
      ]),
    );
  }

  // ── Mapping Preview ──────────────────────────────────────────────────────

  Widget _buildMappingPreview() {
    if (_analysisResult == null) return const Center(child: Text('Error'));
    final headers   = _analysisResult!['headers'] as List;
    final totalRows = _analysisResult!['totalRows'] as int;
    final isXlsx    = _fileType == _FileType.xlsx;

    return Column(
      children: [
        Expanded(
          child: FadeTransition(
            opacity: _fade,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [

                // File info
                _infoCard(
                  icon: Icons.insert_drive_file_rounded, iconColor: isXlsx ? _green : _blue,
                  iconBg: (isXlsx ? _green : _blue).withValues(alpha: 0.08),
                  title: _selectedFile?.path.split('/').last ?? 'unknown',
                  subtitle: '$totalRows baris ditemukan',
                  badge: isXlsx ? 'Excel' : 'CSV', badgeColor: isXlsx ? _green : _blue,
                  trailing: const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 22),
                ),
                const SizedBox(height: 10),

                // Date format
                if (_detectedDateFormat != null)
                  _statusBanner(icon: Icons.calendar_month_rounded, color: _teal, text: 'Format tanggal: $_detectedDateFormat')
                else if (_mapping['date'] != null)
                  _statusBanner(icon: Icons.warning_amber_rounded, color: _orange, text: 'Format tanggal tidak dikenal — periksa kolom tanggal'),

                // Validasi
                if (!_isMappingValid)
                  _statusBanner(icon: Icons.error_outline_rounded, color: _red,
                      text: 'Kolom wajib belum dipetakan: ${_missingRequiredFields.map(_fieldLabel).join(', ')}')
                else
                  _statusBanner(icon: Icons.check_circle_outline_rounded, color: const Color(0xFF22C55E),
                      text: 'Semua kolom wajib sudah dipetakan'),

                const SizedBox(height: 16),

                _infoBanner(icon: Icons.info_outline_rounded, color: _blue,
                    text: 'Metode pembayaran tidak diimport. Isi manual di Detail Transaksi.'),
                const SizedBox(height: 20),

                _sectionHeader('Pemetaan Kolom', 'Kolom bertanda * wajib dipetakan'),
                const SizedBox(height: 12),
                ..._fieldDefs.map((fd) => _buildMappingDropdown(
                      label: fd['label'] as String, fieldKey: fd['key'] as String,
                      isRequired: fd['required'] as bool, headers: headers,
                    )),

                const SizedBox(height: 20),
                _sectionHeader('Preview & Edit Data', 'Tap cell untuk mengedit, ikon hapus untuk menghapus baris'),
                const SizedBox(height: 12),
                _editableTableCard(headers),
                const SizedBox(height: 16),

                // Perhatian
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _orange.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _orange.withValues(alpha: 0.25)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(color: _orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.warning_amber_rounded, color: _orange, size: 18)),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Perhatian', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _orange)),
                      SizedBox(height: 3),
                      Text('Pastikan pemetaan sudah benar sebelum import. Data yang diimport tidak dapat dibatalkan.',
                          style: TextStyle(fontSize: 12, color: _inkLt, height: 1.5)),
                    ])),
                  ]),
                ),
              ],
            ),
          ),
        ),
        _buildActionBar(),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon, required Color iconColor, required Color iconBg,
    required String title, required String subtitle, required String badge,
    required Color badgeColor, Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _bdr)),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: _inkLt)),
        ])),
        const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(6)),
            child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ]),
    );
  }

  Widget _statusBanner({required IconData icon, required Color color, required String text}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Row(children: [
        Icon(icon, color: color, size: 17), const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  Widget _infoBanner({required IconData icon, required Color color, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 16), const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12, height: 1.5))),
      ]),
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
      const SizedBox(height: 2),
      Text(subtitle, style: const TextStyle(fontSize: 12, color: _inkLt)),
    ]);
  }

  // ── Mapping Dropdown ────────────────────────────────────────────────────

  Widget _buildMappingDropdown({
    required String label, required String fieldKey,
    required bool isRequired, required List headers,
  }) {
    final currentIndex = _mapping[fieldKey];
    final isMapped     = currentIndex != null;
    final statusColor  = isMapped ? const Color(0xFF22C55E) : (isRequired ? _red : _inkLt);
    final statusIcon   = isMapped ? Icons.check_circle_rounded : (isRequired ? Icons.cancel_rounded : Icons.radio_button_unchecked_rounded);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(13),
        border: Border.all(color: isMapped ? const Color(0xFF22C55E).withValues(alpha: 0.4)
            : (isRequired ? _red.withValues(alpha: 0.35) : _bdr)),
      ),
      child: Row(children: [
        Icon(statusIcon, color: statusColor, size: 19),
        const SizedBox(width: 10),
        SizedBox(width: 108,
          child: Text(isRequired ? '$label *' : label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: _ink))),
        const Icon(Icons.east_rounded, size: 14, color: _inkLt),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<int?>(
            initialValue: currentIndex,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border:        OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _bdr)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _bdr)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _blue)),
              filled: true, fillColor: _surf,
            ),
            hint: const Text('Pilih kolom', style: TextStyle(fontSize: 12, color: _inkLt)),
            items: [
              const DropdownMenuItem<int?>(value: null,
                  child: Text('— Tidak digunakan —', style: TextStyle(fontSize: 12, color: _inkLt))),
              ...List.generate(headers.length, (i) => DropdownMenuItem<int?>(
                value: i,
                child: Text(headers[i].toString(), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              )),
            ],
            onChanged: (val) {
              setState(() {
                _mapping[fieldKey] = val;
                if (fieldKey == 'date') _detectedDateFormat = _detectDateFormat(_editableData, val);
              });
            },
          ),
        ),
      ]),
    );
  }

  // ── Editable Table ───────────────────────────────────────────────────────

  Widget _editableTableCard(List headers) {
    return Container(
      height: 380,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _bdr)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(_surf),
            headingTextStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _ink),
            dataTextStyle: const TextStyle(fontSize: 12, color: _ink),
            columnSpacing: 12, dividerThickness: 1,
            columns: [
              ...headers.map((h) => DataColumn(label: Text(h.toString()))),
              const DataColumn(label: Text('Hapus')),
            ],
            rows: List.generate(_editableData.length, (ri) {
              final row = _editableData[ri];
              return DataRow(cells: [
                ...List.generate(headers.length, (ci) {
                  final val = ci < row.length ? row[ci].toString() : '';
                  return DataCell(SizedBox(width: 140,
                    child: TextFormField(
                      initialValue: val,
                      onChanged: (v) => _editableData[ri][ci] = v,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: const BorderSide(color: _bdr)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: const BorderSide(color: _bdr)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: const BorderSide(color: _blue)),
                        filled: true, fillColor: _surf,
                      ),
                    ),
                  ));
                }),
                DataCell(GestureDetector(
                  onTap: () => setState(() => _editableData.removeAt(ri)),
                  child: Container(padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(color: _red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.delete_outline_rounded, color: _red, size: 17)),
                )),
              ]);
            }),
          ),
        ),
      ),
    );
  }

  // ── Action Bar ───────────────────────────────────────────────────────────

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -3))],
      ),
      child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!_isMappingValid)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.info_outline_rounded, size: 13, color: _red),
              const SizedBox(width: 5),
              Text('Lengkapi kolom wajib untuk mengaktifkan import',
                  style: TextStyle(fontSize: 11.5, color: Colors.red[400])),
            ]),
          ),
        Row(children: [
          Expanded(flex: 2,
            child: SizedBox(height: 48,
              child: OutlinedButton.icon(
                onPressed: _isImporting ? null : () => setState(() {
                  _selectedFile = null; _analysisResult = null;
                  _mapping = {}; _detectedDateFormat = null; _fileType = _FileType.unknown;
                }),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Ganti File', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(foregroundColor: _inkLt, side: const BorderSide(color: _bdr),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(flex: 3,
            child: SizedBox(height: 48,
              child: ElevatedButton.icon(
                onPressed: (_isImporting || !_isMappingValid) ? null : _showImportConfirmSheet,
                icon: _isImporting
                    ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_rounded, size: 18),
                label: Text(_isImporting ? 'Mengimport...' : 'Import Data',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white,
                    disabledBackgroundColor: _bdr,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
      ])),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // CUSTOM BOTTOM SHEETS  
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _showImportConfirmSheet() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ImportConfirmSheet(
        totalRows:  _analysisResult!['totalRows'] as int,
        fileType:   _fileType,
        dateFormat: _detectedDateFormat,
        mapping:    _mapping,
        fieldDefs:  _fieldDefs,
      ),
    );
    if (confirmed == true) await _runImport();
  }

  Future<bool> _showUnknownFormatSheet(String fileName) async {
    return await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UnknownFormatSheet(fileName: fileName),
    ) ?? false;
  }

  void _showHelp() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _HelpSheet(),
    );
  }

  // ── Snackbar ─────────────────────────────────────────────────────────────

  void _showSnack(String title, String msg, {Color bg = _teal}) {
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
  // FILE PICKER — ✅ FIX: .xls sekarang ditolak dengan pesan jelas
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _pickFile({required bool preferXlsx}) async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;
      
      final pickedFile = result.files.first;
      final fileName   = pickedFile.name.toLowerCase();

      _FileType detectedType;
      if (fileName.endsWith('.xlsx')) {
        // ✅ Only .xlsx is accepted — NOT .xls (old binary format unsupported by excel package)
        detectedType = _FileType.xlsx;
      } else if (fileName.endsWith('.xls')) {
        // ✅ FIX: .xls explicitly rejected with a helpful message
        if (mounted) {
          _showSnack(
            'Format .xls Tidak Didukung',
            'Buka file di Excel / Google Sheets, lalu simpan ulang sebagai .xlsx',
            bg: _orange,
          );
        }
        return;
      } else if (fileName.endsWith('.csv')) {
        detectedType = _FileType.csv;
      } else {
        final proceed = await _showUnknownFormatSheet(pickedFile.name);
        if (!proceed) return;
        detectedType = _FileType.csv;
      }

      File? file;
      if (pickedFile.path != null) {
        file = File(pickedFile.path!);
        if (!await file.exists()) throw Exception('File tidak ditemukan');
      } else if (pickedFile.bytes != null) {
        final ext    = detectedType == _FileType.xlsx ? 'xlsx' : 'csv';
        final tmpDir = Directory.systemTemp;
        file = File('${tmpDir.path}/import_${DateTime.now().millisecondsSinceEpoch}.$ext');
        await file.writeAsBytes(pickedFile.bytes!);
      } else {
        throw Exception('Tidak dapat mengakses file');
      }

      setState(() { _selectedFile = file; _fileType = detectedType; _isAnalyzing = true; });
      await _analyzeFile();
    } catch (e, st) {
      debugPrint('Error picking file: $e\n$st');
      _showSnack('Gagal memilih file', e.toString(), bg: _red);
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // ANALYZE
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _analyzeFile() async {
    if (_selectedFile == null) return;
    setState(() => _isAnalyzing = true);
    try {
      final allRows = _fileType == _FileType.xlsx
          ? await _parseXlsx(_selectedFile!)
          : await _parseCsv(_selectedFile!);

      if (allRows.isEmpty) throw Exception('File kosong atau tidak dapat dibaca');

      final headers     = allRows.first;
      final data        = allRows.length > 1 ? allRows.sublist(1) : <List<dynamic>>[];
      final autoMapping = _autoDetectMapping(headers);
      final dateFormat  = _detectDateFormat(List<List<dynamic>>.from(data), autoMapping['date']);

      setState(() {
        _analysisResult     = {'headers': headers, 'data': data, 'totalRows': data.length};
        _mapping            = autoMapping;
        _editableData       = List<List<dynamic>>.from(data);
        _detectedDateFormat = dateFormat;
        _isAnalyzing        = false;
      });

      _fadeCtrl..reset()..forward();
      final cnt = autoMapping.values.where((v) => v != null).length;
      _showSnack('Auto-detect selesai', '$cnt dari ${_fieldDefs.length} kolom dipetakan otomatis');
    } catch (e) {
      setState(() => _isAnalyzing = false);
      // ✅ FIX: Better error message distinguishing XLS decode failure
      final msg = e.toString().contains('FormatException') || e.toString().contains('decode')
          ? 'File tidak dapat dibaca. Jika ini file .xls, simpan ulang sebagai .xlsx terlebih dahulu.'
          : e.toString();
      if (mounted) _showSnack('Gagal membaca file', msg, bg: _red);
    }
  }

  Future<List<List<dynamic>>> _parseCsv(File file) async {
    final input = await file.readAsString();
    final delim = input.contains(';') ? ';' : ',';
    return CsvToListConverter(fieldDelimiter: delim, eol: '\n').convert(input);
  }

  Future<List<List<dynamic>>> _parseXlsx(File file) async {
    final bytes = await file.readAsBytes();
    // ✅ FIX: Wrap decode in try-catch to catch .xls binary format errors specifically
    Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      throw Exception(
        'File tidak bisa dibuka sebagai .xlsx. '
        'Jika ini file .xls (Excel 97-2003), buka di Excel atau Google Sheets '
        'lalu simpan ulang sebagai .xlsx (Excel 2007+).',
      );
    }

    Sheet? sheet;
    for (final name in excel.tables.keys) {
      final s = excel.tables[name];
      if (s != null && s.maxRows > 0) { sheet = s; break; }
    }
    if (sheet == null) throw Exception('Tidak ada sheet dengan data');

    final rows = <List<dynamic>>[];
    for (final row in sheet.rows) {
      final cells = row.map((cell) {
        if (cell == null) return '';
        final v = cell.value;
        if (v == null) return '';
        if (v is DateCellValue) {
          final dt = v.asDateTimeLocal();
          return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year}';
        }
        if (v is DoubleCellValue) return v.value.toString();
        if (v is IntCellValue)    return v.value.toString();
        if (v is BoolCellValue)   return v.value.toString();
        return v.toString();
      }).toList();
      if (cells.every((c) => c.toString().trim().isEmpty)) continue;
      rows.add(cells);
    }
    return rows;
  }

  // ════════════════════════════════════════════════════════════════════════
  // IMPORT
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _runImport() async {
    setState(() => _isImporting = true);
    try {
      final mappingForService = _mapping.map((k, v) => MapEntry(k, v?.toString()));
      final result = await _importService.importTransactions(
        data: _editableData, mapping: mappingForService, dateFormat: _detectedDateFormat,
      );
      if (mounted) {
        Get.back();
        _showSnack('Import berhasil', '${result['success']} berhasil · ${result['failed']} gagal');
      }
    } catch (e, st) {
      debugPrint('Import error: $e\n$st');
      if (mounted) _showSnack('Gagal import', e.toString(), bg: _red);
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// BOTTOM SHEET WIDGETS
// ════════════════════════════════════════════════════════════════════════════

class _ImportConfirmSheet extends StatelessWidget {
  final int                        totalRows;
  final _FileType                  fileType;
  final String?                    dateFormat;
  final Map<String, int?>          mapping;
  final List<Map<String, Object>>  fieldDefs;

  const _ImportConfirmSheet({
    required this.totalRows, required this.fileType, required this.dateFormat,
    required this.mapping, required this.fieldDefs,
  });

  @override
  Widget build(BuildContext context) {
    final mappedCount = mapping.values.where((v) => v != null).length;
    final isXlsx      = fileType == _FileType.xlsx;

    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _bdr, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.cloud_upload_rounded, color: _blue, size: 22)),
          const SizedBox(width: 14),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Konfirmasi Import', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
            Text('Periksa ringkasan sebelum melanjutkan', style: TextStyle(fontSize: 12, color: _inkLt)),
          ])),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          _statBox('Total Baris', '$totalRows', Icons.table_rows_outlined, _blue),
          const SizedBox(width: 10),
          _statBox('Kolom', '$mappedCount/${fieldDefs.length}', Icons.link_rounded, _teal),
          const SizedBox(width: 10),
          _statBox('Format', isXlsx ? 'Excel' : 'CSV', Icons.insert_drive_file_rounded, isXlsx ? _green : _blue),
        ]),
        const SizedBox(height: 14),
        if (dateFormat != null)
          _detailRow(Icons.calendar_month_rounded, 'Format tanggal', dateFormat!, _teal),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _red.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _red.withValues(alpha: 0.2))),
          child: const Row(children: [
            Icon(Icons.error_outline_rounded, color: _red, size: 16), SizedBox(width: 10),
            Expanded(child: Text('Data yang diimport tidak dapat dibatalkan. Pastikan pemetaan sudah benar.',
                style: TextStyle(fontSize: 12, color: _red, height: 1.5))),
          ]),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: SizedBox(height: 48,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(foregroundColor: _inkLt, side: const BorderSide(color: _bdr),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          )),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: SizedBox(height: 48,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.cloud_upload_rounded, size: 18),
              label: const Text('Import Sekarang', style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
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
        decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2))),
        child: Column(children: [
          Icon(icon, color: color, size: 18), const SizedBox(height: 5),
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(children: [
        Icon(icon, color: color, size: 15), const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontSize: 12, color: _inkLt)),
        Expanded(child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
      ]),
    );
  }
}

class _UnknownFormatSheet extends StatelessWidget {
  final String fileName;
  const _UnknownFormatSheet({required this.fileName});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _bdr, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _orange.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.help_outline_rounded, color: _orange, size: 28)),
        const SizedBox(height: 16),
        const Text('Format Tidak Dikenal', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 8),
        Text(fileName, style: const TextStyle(fontSize: 13, color: _inkLt), textAlign: TextAlign.center,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 10),
        const Text('File ini bukan .csv atau .xlsx. Ingin mencoba membukanya sebagai CSV?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _inkLt, height: 1.5)),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: SizedBox(height: 48,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(foregroundColor: _inkLt, side: const BorderSide(color: _bdr),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Batal'),
            ),
          )),
          const SizedBox(width: 10),
          Expanded(child: SizedBox(height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: _orange, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
              child: const Text('Coba sebagai CSV', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          )),
        ]),
      ]),
    );
  }
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 28),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: _bdr, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(children: [
            Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.menu_book_rounded, color: _blue, size: 20)),
            const SizedBox(width: 12),
            const Text('Panduan Import', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
          ]),
          const SizedBox(height: 22),

          _section('Format File', [
            _item(Icons.table_rows_outlined,   _blue,   'CSV (.csv)',     'Dipisahkan koma atau titik koma'),
            _item(Icons.grid_on_rounded,       _green,  'Excel (.xlsx)',  'Sheet pertama dibaca otomatis'),
            // ✅ FIX: Added explicit warning about .xls
            _item(Icons.block_rounded,         _red,    'Excel (.xls)',   'TIDAK didukung — simpan ulang sebagai .xlsx'),
          ]),
          _section('Kolom Wajib (*)', [
            _item(Icons.calendar_today_rounded,  _blue,   'Tanggal',       'Kolom berisi tanggal transaksi'),
            _item(Icons.inventory_2_outlined,    _teal,   'Produk',        'Nama produk atau layanan'),
            _item(Icons.person_outline_rounded,  _orange, 'No. Pelanggan', 'Nomor HP atau ID pelanggan'),
            _item(Icons.attach_money_rounded,    _green,  'Nominal',       'Harga tanpa simbol Rp'),
          ]),
          _section('Format Tanggal', [
            _code('dd/MM/yyyy   →  15/01/2024'),
            _code('dd-MM-yyyy   →  15-01-2024'),
            _code('yyyy-MM-dd   →  2024-01-15'),
            _code('dd MMM yyyy  →  15 Jan 2024'),
            _code('Tanggal Excel dikonversi otomatis'),
          ]),
          _section('Tips', [
            _item(Icons.auto_fix_high_rounded,  _blue,   'Auto-detect',   'Pemetaan kolom terdeteksi otomatis'),
            _item(Icons.edit_outlined,          _teal,   'Edit manual',   'Bisa diubah setelah analisis'),
            _item(Icons.payment_rounded,        _orange, 'Metode bayar',  'Diisi manual di Detail Transaksi'),
            _item(Icons.check_circle_outline,   _green,  'Status lunas',  'lunas/belum atau true/false'),
          ]),

          const SizedBox(height: 8),
          SizedBox(width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
              child: const Text('Mengerti', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(bottom: 10),
          child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _ink))),
      ...children,
      const SizedBox(height: 16),
    ]);
  }

  Widget _item(IconData icon, Color color, String label, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 15)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _ink)),
          Text(desc,  style: const TextStyle(fontSize: 11.5, color: _inkLt)),
        ])),
      ]),
    );
  }

  Widget _code(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: _surf, borderRadius: BorderRadius.circular(8), border: Border.all(color: _bdr)),
        child: Text(text, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: _ink)),
      ),
    );
  }
}