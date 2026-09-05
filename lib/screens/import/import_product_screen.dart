import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:lottie/lottie.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

// ── Design tokens ─────────────────────────────────────────────────────────
const _blue   = Color(0xFF2196F3);
const _green  = Color(0xFF1B7F4A);
const _red    = Color(0xFFE53935);
const _orange = Color(0xFFF57C00);
const _teal   = Color(0xFF00897B);
const _ink    = Color(0xFF111827);
const _inkLt  = Color(0xFF6B7280);
const _surf   = Color(0xFFF8FAFC);
const _bdr    = Color(0xFFE2E8F0);

const _requiredProductFields = ['name'];

enum _FileType { csv, xlsx, unknown }

// ─────────────────────────────────────────────────────────────────────────────

class ImportProductScreen extends StatefulWidget {
  const ImportProductScreen({super.key});

  @override
  State<ImportProductScreen> createState() => _ImportProductScreenState();
}

class _ImportProductScreenState extends State<ImportProductScreen>
    with SingleTickerProviderStateMixin {
  File?     _selectedFile;
  _FileType _fileType    = _FileType.unknown;
  bool      _isAnalyzing = false;
  bool      _isImporting = false;

  Map<String, dynamic>? _analysisResult;
  Map<String, int?>     _mapping      = {};
  List<List<dynamic>>   _editableData = [];

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fade;

  // ── Field defs ─────────────────────────────────────────────────────────
  static const _fieldDefs = [
    {'key': 'name',         'label': 'Nama Produk',  'required': true},
    {'key': 'category',     'label': 'Kategori',     'required': false},
    {'key': 'sellingPrice', 'label': 'Harga Jual',   'required': false},
    {'key': 'costPrice',    'label': 'Harga Beli',   'required': false},
    {'key': 'adminFee',     'label': 'Biaya Admin',  'required': false},
    {'key': 'description',  'label': 'Deskripsi',    'required': false},
    {'key': 'isActive',     'label': 'Status Aktif', 'required': false},
  ];

  static const _fieldSynonyms = <String, List<String>>{
    'name':         ['nama produk','nama','name','produk','product','item','layanan','barang'],
    'category':     ['kategori','category','cat','jenis','type','tipe'],
    'sellingPrice': ['harga jual','harga_jual','selling_price','sell_price','jual','hj','harga','price','selling'],
    'costPrice':    ['harga beli','harga_beli','cost_price','modal','beli','cost','hpp'],
    'adminFee':     ['biaya admin','biaya_admin','admin_fee','admin','fee','biaya','charge'],
    'description':  ['deskripsi','description','desc','keterangan','catatan','note'],
    'isActive':     ['status','aktif','active','is_active','status_aktif','enable'],
  };

  static const _validCategories = [
    'Pulsa', 'Paket Data', 'Token Listrik',
    'Tagihan', 'E-Wallet', 'Jasa Transfer', 'Lainnya',
  ];

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

  // ════════════════════════════════════════════════════════════════════════
  // VALIDASI
  // ════════════════════════════════════════════════════════════════════════

  bool get _isMappingValid => _requiredProductFields.every((f) => _mapping[f] != null);
  List<String> get _missingRequiredFields =>
      _requiredProductFields.where((f) => _mapping[f] == null).toList();
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
      title: const Text('Import Produk',
          style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton.icon(
            onPressed: _showHelp,
            icon: const Icon(Icons.help_outline_rounded, size: 17, color: _blue),
            label: const Text('Panduan', style: TextStyle(color: _blue, fontSize: 13)),
            style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ),
        ),
      ],
    );
  }

  // ── File Selection ────────────────────────────────────────────────────────

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
                decoration: BoxDecoration(color: _green.withValues(alpha: 0.06), shape: BoxShape.circle),
                child: Lottie.asset('assets/lottie/uploading.json', fit: BoxFit.contain),
              ),
              const SizedBox(height: 28),
              const Text('Import Data Produk',
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
                // ✅ FIX: Removed .xls from subtitle
                title: 'File Excel', subtitle: 'Hanya format .xlsx (Excel 2007+)',
                badgeColor: _green, badgeText: 'XLSX',
              ),
              const SizedBox(height: 24),

              // Template hint
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _orange.withValues(alpha: 0.2)),
                ),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.tips_and_updates_outlined, color: _orange, size: 16),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Gunakan fitur Ekspor Produk untuk mendapatkan template file yang siap diisi.',
                      style: TextStyle(fontSize: 12, color: _orange, height: 1.5),
                    ),
                  ),
                ]),
              ),

              // ✅ FIX: Added XLS warning
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _red.withValues(alpha: 0.2)),
                ),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.block_rounded, color: _red, size: 15),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'File .xls (Excel 97-2003) tidak didukung. Buka di Excel/Google Sheets lalu simpan ulang sebagai .xlsx.',
                      style: TextStyle(fontSize: 11.5, color: _red, height: 1.5),
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
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16), border: Border.all(color: _bdr)),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: iconColor, size: 22)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: _inkLt)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(8)),
              child: Text(badgeText,
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: _inkLt, size: 20),
          ]),
        ),
      ),
    );
  }

  // ── Analyzing ─────────────────────────────────────────────────────────────

  Widget _buildAnalyzing() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 120, height: 120, child: Lottie.asset('assets/lottie/uploading.json')),
        const SizedBox(height: 24),
        const Text('Menganalisis file...',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _ink)),
        const SizedBox(height: 8),
        const Text('Mendeteksi kolom produk secara otomatis',
            style: TextStyle(color: _inkLt, fontSize: 13)),
        const SizedBox(height: 28),
        const SizedBox(width: 28, height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: _green)),
      ]),
    );
  }

  // ── Mapping Preview ───────────────────────────────────────────────────────

  Widget _buildMappingPreview() {
    if (_analysisResult == null) return const Center(child: Text('Error'));
    final headers   = _analysisResult!['headers'] as List;
    final totalRows = _analysisResult!['totalRows'] as int;
    final isXlsx    = _fileType == _FileType.xlsx;

    return Column(children: [
      Expanded(
        child: FadeTransition(
          opacity: _fade,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _infoCard(
                icon: Icons.insert_drive_file_rounded,
                iconColor: isXlsx ? _green : _blue,
                iconBg: (isXlsx ? _green : _blue).withValues(alpha: 0.08),
                title: _selectedFile?.path.split('/').last ?? 'unknown',
                subtitle: '$totalRows baris ditemukan',
                badge: isXlsx ? 'Excel' : 'CSV',
                badgeColor: isXlsx ? _green : _blue,
                trailing: const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 22),
              ),
              const SizedBox(height: 10),

              if (!_isMappingValid)
                _statusBanner(icon: Icons.error_outline_rounded, color: _red,
                    text: 'Kolom wajib belum dipetakan: ${_missingRequiredFields.map(_fieldLabel).join(', ')}')
              else
                _statusBanner(icon: Icons.check_circle_outline_rounded, color: const Color(0xFF22C55E),
                    text: 'Semua kolom wajib sudah dipetakan'),

              const SizedBox(height: 8),
              _infoBanner(icon: Icons.info_outline_rounded, color: _blue,
                  text: 'Produk dengan nama yang sama akan ditambahkan sebagai entri baru, tidak menimpa data lama.'),
              const SizedBox(height: 20),

              _sectionHeader('Pemetaan Kolom', 'Kolom bertanda * wajib dipetakan'),
              const SizedBox(height: 12),
              ..._fieldDefs.map((fd) => _buildMappingDropdown(
                    label: fd['label'] as String,
                    fieldKey: fd['key'] as String,
                    isRequired: fd['required'] as bool,
                    headers: headers,
                  )),

              const SizedBox(height: 20),
              _sectionHeader('Preview & Edit Data', 'Tap cell untuk mengedit, ikon hapus untuk menghapus baris'),
              const SizedBox(height: 12),
              _editableTableCard(headers),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _orange.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _orange.withValues(alpha: 0.25)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                        color: _orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.warning_amber_rounded, color: _orange, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Perhatian',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _orange)),
                      SizedBox(height: 3),
                      Text(
                        'Kategori yang tidak dikenal akan otomatis masuk ke "Lainnya". '
                        'Kategori valid: Pulsa, Paket Data, Token Listrik, Tagihan, E-Wallet, Jasa Transfer, Lainnya.',
                        style: TextStyle(fontSize: 12, color: _inkLt, height: 1.5),
                      ),
                    ]),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
      _buildActionBar(),
    ]);
  }

  Widget _infoCard({
    required IconData icon, required Color iconColor, required Color iconBg,
    required String title, required String subtitle, required String badge,
    required Color badgeColor, Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _bdr)),
      child: Row(children: [
        Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: _inkLt)),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(6)),
          child: Text(badge,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ]),
    );
  }

  Widget _statusBanner({required IconData icon, required Color color, required String text}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  Widget _infoBanner({required IconData icon, required Color color, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
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

  // ── Mapping Dropdown ──────────────────────────────────────────────────────

  Widget _buildMappingDropdown({
    required String label, required String fieldKey,
    required bool isRequired, required List headers,
  }) {
    final currentIndex = _mapping[fieldKey];
    final isMapped     = currentIndex != null;
    final statusColor  = isMapped ? const Color(0xFF22C55E) : (isRequired ? _red : _inkLt);
    final statusIcon   = isMapped
        ? Icons.check_circle_rounded
        : (isRequired ? Icons.cancel_rounded : Icons.radio_button_unchecked_rounded);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isMapped
              ? const Color(0xFF22C55E).withValues(alpha: 0.4)
              : (isRequired ? _red.withValues(alpha: 0.35) : _bdr),
        ),
      ),
      child: Row(children: [
        Icon(statusIcon, color: statusColor, size: 19),
        const SizedBox(width: 10),
        SizedBox(
          width: 108,
          child: Text(isRequired ? '$label *' : label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: _ink)),
        ),
        const Icon(Icons.east_rounded, size: 14, color: _inkLt),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<int?>(
            initialValue: currentIndex,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _bdr)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _bdr)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _blue)),
              filled: true, fillColor: _surf,
            ),
            hint: const Text('Pilih kolom', style: TextStyle(fontSize: 12, color: _inkLt)),
            items: [
              const DropdownMenuItem<int?>(value: null,
                  child: Text('— Tidak digunakan —', style: TextStyle(fontSize: 12, color: _inkLt))),
              ...List.generate(headers.length, (i) => DropdownMenuItem<int?>(
                value: i,
                child: Text(headers[i].toString(),
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              )),
            ],
            onChanged: (val) => setState(() => _mapping[fieldKey] = val),
          ),
        ),
      ]),
    );
  }

  // ── Editable Table ────────────────────────────────────────────────────────

  Widget _editableTableCard(List headers) {
    return Container(
      height: 380,
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _bdr)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(_surf),
            headingTextStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _ink),
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
                  return DataCell(SizedBox(
                    width: 140,
                    child: TextFormField(
                      initialValue: val,
                      onChanged: (v) => _editableData[ri][ci] = v,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(color: _bdr)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(color: _bdr)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(7),
                            borderSide: const BorderSide(color: _blue)),
                        filled: true, fillColor: _surf,
                      ),
                    ),
                  ));
                }),
                DataCell(GestureDetector(
                  onTap: () => setState(() => _editableData.removeAt(ri)),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                        color: _red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.delete_outline_rounded, color: _red, size: 17),
                  ),
                )),
              ]);
            }),
          ),
        ),
      ),
    );
  }

  // ── Action Bar ────────────────────────────────────────────────────────────

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -3)),
        ],
      ),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _isImporting
                      ? null
                      : () => setState(() {
                            _selectedFile = null;
                            _analysisResult = null;
                            _mapping = {};
                            _fileType = _FileType.unknown;
                          }),
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Ganti File', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: _inkLt,
                      side: const BorderSide(color: _bdr),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: (_isImporting || !_isMappingValid) ? null : _showImportConfirmSheet,
                  icon: _isImporting
                      ? const SizedBox(
                          width: 17, height: 17,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: Text(_isImporting ? 'Mengimport...' : 'Import Produk',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _green, foregroundColor: Colors.white,
                      disabledBackgroundColor: _bdr,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // BOTTOM SHEETS
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _showImportConfirmSheet() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ImportProductConfirmSheet(
        totalRows: _analysisResult!['totalRows'] as int,
        fileType:  _fileType,
        mapping:   _mapping,
        fieldDefs: _fieldDefs,
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
        ) ??
        false;
  }

  void _showHelp() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ProductHelpSheet(),
    );
  }

  // ── Snackbar ──────────────────────────────────────────────────────────────

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
      final result = await FilePicker.platform.pickFiles(
    allowMultiple: false,
  );
      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.first;
      final fileName   = pickedFile.name.toLowerCase();

      _FileType detectedType;
      if (fileName.endsWith('.xlsx')) {
        // ✅ Only .xlsx is accepted
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
        file = File('${tmpDir.path}/import_product_${DateTime.now().millisecondsSinceEpoch}.$ext');
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

      setState(() {
        _analysisResult = {'headers': headers, 'data': data, 'totalRows': data.length};
        _mapping        = autoMapping;
        _editableData   = List<List<dynamic>>.from(data);
        _isAnalyzing    = false;
      });

      _fadeCtrl..reset()..forward();
      final cnt = autoMapping.values.where((v) => v != null).length;
      _showSnack('Auto-detect selesai', '$cnt dari ${_fieldDefs.length} kolom dipetakan otomatis');
    } catch (e) {
      setState(() => _isAnalyzing = false);
      // ✅ FIX: Better error message for decode failures
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
    // ✅ FIX: Catch decode errors from .xls binary files specifically
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
    int success = 0, failed = 0;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Pengguna tidak ditemukan');

      final batch = FirebaseFirestore.instance.batch();
      final col   = FirebaseFirestore.instance.collection('products');

      for (final row in _editableData) {
        try {
          String get(String key) {
            final idx = _mapping[key];
            if (idx == null || idx >= row.length) return '';
            return row[idx].toString().trim();
          }

          final name = get('name');
          if (name.isEmpty) { failed++; continue; }

          String rawCat = get('category');
          String category = 'Lainnya';
          for (final valid in _validCategories) {
            if (valid.toLowerCase() == rawCat.toLowerCase()) { category = valid; break; }
          }

          double parseNum(String key) {
            final v = get(key).replaceAll(RegExp(r'[^0-9.]'), '');
            return double.tryParse(v) ?? 0.0;
          }

          bool isActive = true;
          final rawStatus = get('isActive').toLowerCase();
          if (rawStatus == 'false' || rawStatus == 'tidak aktif' ||
              rawStatus == 'nonaktif' || rawStatus == '0') {
            isActive = false;
          }

          final doc = col.doc();
          batch.set(doc, {
            'userId':       user.uid,
            'name':         name,
            'category':     category,
            'sellingPrice': parseNum('sellingPrice'),
            'costPrice':    parseNum('costPrice'),
            'adminFee':     parseNum('adminFee'),
            'description':  get('description'),
            'isActive':     isActive,
            'createdAt':    DateTime.now().toIso8601String(),
          });
          success++;
        } catch (_) { failed++; }
      }

      await batch.commit();

      if (mounted) {
        Navigator.pop(context);
        _showSnack(
          'Import Berhasil',
          '$success produk ditambahkan · $failed gagal',
          bg: _green,
        );
      }
    } catch (e, st) {
      debugPrint('Import product error: $e\n$st');
      if (mounted) _showSnack('Gagal Import', e.toString(), bg: _red);
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// BOTTOM SHEET: Konfirmasi Import Produk
// ════════════════════════════════════════════════════════════════════════════

class _ImportProductConfirmSheet extends StatelessWidget {
  final int                        totalRows;
  final _FileType                  fileType;
  final Map<String, int?>          mapping;
  final List<Map<String, Object>>  fieldDefs;

  const _ImportProductConfirmSheet({
    required this.totalRows, required this.fileType,
    required this.mapping, required this.fieldDefs,
  });

  @override
  Widget build(BuildContext context) {
    final mappedCount = mapping.values.where((v) => v != null).length;
    final isXlsx      = fileType == _FileType.xlsx;

    return Container(
      decoration: const BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: _bdr, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Row(children: [
          Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.cloud_upload_rounded, color: _green, size: 22)),
          const SizedBox(width: 14),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Konfirmasi Import Produk',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
            Text('Periksa ringkasan sebelum melanjutkan',
                style: TextStyle(fontSize: 12, color: _inkLt)),
          ])),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          _statBox('Total Baris', '$totalRows', Icons.inventory_2_rounded, _green),
          const SizedBox(width: 10),
          _statBox('Kolom', '$mappedCount/${fieldDefs.length}', Icons.link_rounded, _teal),
          const SizedBox(width: 10),
          _statBox('Format', isXlsx ? 'Excel' : 'CSV', Icons.insert_drive_file_rounded,
              isXlsx ? _green : _blue),
        ]),
        const SizedBox(height: 14),
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
              style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white,
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
}

// ════════════════════════════════════════════════════════════════════════════
// BOTTOM SHEET: Format Tidak Dikenal
// ════════════════════════════════════════════════════════════════════════════

class _UnknownFormatSheet extends StatelessWidget {
  final String fileName;
  const _UnknownFormatSheet({required this.fileName});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: _bdr, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _orange.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: const Icon(Icons.help_outline_rounded, color: _orange, size: 28)),
        const SizedBox(height: 16),
        const Text('Format Tidak Dikenal',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 8),
        Text(fileName, style: const TextStyle(fontSize: 13, color: _inkLt),
            textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
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
              child: const Text('Coba sebagai CSV',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          )),
        ]),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// BOTTOM SHEET: Panduan Import Produk
// ════════════════════════════════════════════════════════════════════════════

class _ProductHelpSheet extends StatelessWidget {
  const _ProductHelpSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 28),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: _bdr, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(children: [
            Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: _green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.menu_book_rounded, color: _green, size: 20)),
            const SizedBox(width: 12),
            const Text('Panduan Import Produk',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
          ]),
          const SizedBox(height: 22),

          _section('Format File', [
            _item(Icons.table_rows_outlined,  _blue,  'CSV (.csv)',    'Dipisahkan koma atau titik koma'),
            _item(Icons.grid_on_rounded,      _green, 'Excel (.xlsx)', 'Sheet pertama dibaca otomatis'),
            // ✅ FIX: Added .xls warning in help sheet
            _item(Icons.block_rounded,        _red,   'Excel (.xls)',  'TIDAK didukung — simpan ulang sebagai .xlsx'),
          ]),
          _section('Kolom Wajib (*)', [
            _item(Icons.inventory_2_outlined, _green, 'Nama Produk', 'Kolom berisi nama produk/layanan'),
          ]),
          _section('Kolom Opsional', [
            _item(Icons.category_rounded,             _teal,   'Kategori',    'Pulsa, Paket Data, Token Listrik, dll'),
            _item(Icons.sell_rounded,                 _blue,   'Harga Jual',  'Angka tanpa simbol Rp'),
            _item(Icons.shopping_bag_rounded,         _orange, 'Harga Beli',  'Harga modal / HPP'),
            _item(Icons.admin_panel_settings_rounded, _teal,   'Biaya Admin', 'Biaya tambahan layanan'),
            _item(Icons.toggle_on_rounded,            _green,  'Status Aktif','aktif/tidak aktif atau true/false'),
          ]),
          _section('Kategori Valid', [
            _code('Pulsa · Paket Data · Token Listrik'),
            _code('Tagihan · E-Wallet · Jasa Transfer · Lainnya'),
            _code('Kategori tidak dikenal → otomatis "Lainnya"'),
          ]),
          _section('Tips', [
            _item(Icons.file_download_rounded, _blue,   'Gunakan template', 'Ekspor produk dulu sebagai template file'),
            _item(Icons.auto_fix_high_rounded, _teal,   'Auto-detect',      'Kolom terdeteksi otomatis dari nama header'),
            _item(Icons.edit_outlined,         _orange, 'Edit manual',      'Bisa diubah sebelum import di tabel preview'),
          ]),

          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white,
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