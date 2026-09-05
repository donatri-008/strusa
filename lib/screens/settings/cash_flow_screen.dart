import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import '../transaction/transaction_detail_screen.dart';
import '../../utils/app_notification.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Konstanta warna
// ─────────────────────────────────────────────────────────────────────────────
const _blue = Color(0xFF2196F3);
const _blueDk = Color(0xFF577DE7);
const _blueLt = Color(0xFFEFF6FF);
const _green = Color(0xFF16A34A);
const _greenLt = Color(0xFFF0FDF4);
const _red = Color(0xFFDC2626);
const _redLt = Color(0xFFFEF2F2);
const _orange = Color(0xFFEA580C);
const _orangeLt = Color(0xFFFFF7ED);
const _purple = Color(0xFF7C3AED);
const _purpleLt = Color(0xFFF5F3FF);
const _ink = Color(0xFF111827);
const _inkMd = Color(0xFF6B7280);
const _inkLt = Color(0xFF9CA3AF);
const _surf = Color(0xFFF8FAFC);
const _bdr = Color(0xFFE5E7EB);
const _white = Colors.white;

// ─────────────────────────────────────────────────────────────────────────────
// Thousand separator formatter
// ─────────────────────────────────────────────────────────────────────────────
class _ThousandFmt extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue nw) {
    if (nw.text.isEmpty) return nw;
    final digits = nw.text.replaceAll('.', '');
    if (digits.isEmpty) return nw.copyWith(text: '');
    final n = int.tryParse(digits) ?? 0;
    final fmt = NumberFormat('#,##0', 'id_ID').format(n).replaceAll(',', '.');
    return nw.copyWith(
        text: fmt, selection: TextSelection.collapsed(offset: fmt.length));
  }
}

String _rawInt(String s) => s.replaceAll('.', '');

// ─────────────────────────────────────────────────────────────────────────────
// Model kas keluar
// ─────────────────────────────────────────────────────────────────────────────
class _KasKeluarEntry {
  final String docId;
  final String keterangan;
  final String kategori;
  final double amount;
  final DateTime date;
  final bool kurangiLaba;

  const _KasKeluarEntry({
    required this.docId,
    required this.keterangan,
    required this.kategori,
    required this.amount,
    required this.date,
    required this.kurangiLaba,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Model kas masuk
// ─────────────────────────────────────────────────────────────────────────────
class _PaymentEntry {
  final String docId;
  final Map<String, dynamic> data;
  final double amount;
  final double profit;
  final String method;
  final DateTime paymentDate;

  const _PaymentEntry({
    required this.docId,
    required this.data,
    required this.amount,
    required this.profit,
    required this.method,
    required this.paymentDate,
  });
}

// ─────────────────────────────────────────────────────────────────────────────

class CashFlowScreen extends StatefulWidget {
  const CashFlowScreen({super.key});

  @override
  State<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends State<CashFlowScreen>
    with SingleTickerProviderStateMixin {
  DateTime _selectedDate = DateTime.now();
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  static const _kategoriKeluar = [
    'Operasional',
    'Pembelian Stok',
    'Gaji / Upah',
    'Sewa',
    'Transportasi',
    'Listrik / Air',
    'Penarikan Modal',
    'Lainnya',
  ];

  static const _kategoriIcons = <String, IconData>{
    'Operasional': Icons.settings_rounded,
    'Pembelian Stok': Icons.shopping_cart_rounded,
    'Gaji / Upah': Icons.people_rounded,
    'Sewa': Icons.home_work_rounded,
    'Transportasi': Icons.directions_car_rounded,
    'Listrik / Air': Icons.bolt_rounded,
    'Penarikan Modal': Icons.account_balance_rounded,
    'Lainnya': Icons.more_horiz_rounded,
  };

  static const _kategoriColors = <String, Color>{
    'Operasional': Color(0xFF7C3AED),
    'Pembelian Stok': Color(0xFF0891B2),
    'Gaji / Upah': Color(0xFF059669),
    'Sewa': Color(0xFFD97706),
    'Transportasi': Color(0xFF2563EB),
    'Listrik / Air': Color(0xFFEA580C),
    'Penarikan Modal': Color(0xFF7C3AED),
    'Lainnya': Color(0xFF6B7280),
  };

  static const _defaultKurangiLaba = {
    'Operasional',
    'Pembelian Stok',
    'Gaji / Upah',
    'Sewa',
    'Transportasi',
    'Listrik / Air',
    'Lainnya',
  };

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  bool get _isToday => DateUtils.isSameDay(_selectedDate, DateTime.now());

  void _prevDay() => setState(() {
        _selectedDate = _selectedDate.subtract(const Duration(days: 1));
        _fadeCtrl..reset()..forward();
      });

  void _nextDay() {
    if (_isToday) return;
    setState(() {
      _selectedDate = _selectedDate.add(const Duration(days: 1));
      _fadeCtrl..reset()..forward();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx)
            .copyWith(colorScheme: const ColorScheme.light(primary: _blue)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _fadeCtrl..reset()..forward();
      });
    }
  }

  // ── Form Tambah Kas Keluar ──────────────────────────────────────────────────
  void _showTambahKasKeluar() {
    final amountCtrl = TextEditingController();
    final keteranganCtrl = TextEditingController();
    String? selectedKategori;
    DateTime selectedDate = _selectedDate;
    bool isLoading = false;
    bool kurangiLaba = true;
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetRootCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36, height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _redLt,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.arrow_upward_rounded, color: _red, size: 22),
                      ),
                      const SizedBox(width: 14),
                      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Catat Kas Keluar',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _ink)),
                        Text('Pengeluaran harian bisnis',
                            style: TextStyle(fontSize: 12, color: _inkMd)),
                      ]),
                    ]),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_ThousandFmt()],
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Jumlah Pengeluaran',
                        prefixText: 'Rp ',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _red, width: 2),
                        ),
                        prefixIcon: const Icon(Icons.money_off_rounded, color: _red),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Jumlah harus diisi';
                        final n = int.tryParse(_rawInt(v)) ?? 0;
                        if (n <= 0) return 'Masukkan jumlah yang valid';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: keteranganCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Keterangan',
                        hintText: 'Contoh: Beli kertas struk, bayar listrik...',
                        prefixIcon: const Icon(Icons.notes_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _blue, width: 2),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Keterangan harus diisi' : null,
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () async {
                        FocusScope.of(sheetCtx).unfocus();
                        await Future.delayed(const Duration(milliseconds: 80));
                        if (!sheetCtx.mounted) return;
                        final picked = await showDatePicker(
                          context: sheetRootCtx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          builder: (ctx, child) => Theme(
                            data: Theme.of(ctx).copyWith(
                                colorScheme: const ColorScheme.light(primary: _red)),
                            child: child!,
                          ),
                        );
                        if (picked != null) setSheet(() => selectedDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        decoration: BoxDecoration(
                          color: _white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _bdr, width: 1.5),
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(color: _redLt, borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.calendar_today_rounded, color: _red, size: 16),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Tanggal', style: TextStyle(fontSize: 10, color: _inkLt)),
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(selectedDate),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink),
                              ),
                            ]),
                          ),
                          const Icon(Icons.edit_calendar_rounded, color: _inkLt, size: 16),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('Kategori',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _kategoriKeluar.map((k) {
                        final isSelected = selectedKategori == k;
                        final color = _kategoriColors[k] ?? _inkLt;
                        final icon = _kategoriIcons[k] ?? Icons.circle;
                        return GestureDetector(
                          onTap: () => setSheet(() {
                            selectedKategori = k;
                            kurangiLaba = _defaultKurangiLaba.contains(k);
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? color.withValues(alpha: 0.1) : _surf,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? color : _bdr,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(icon, size: 14, color: isSelected ? color : _inkLt),
                              const SizedBox(width: 6),
                              Text(k,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? color : _ink)),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                    if (selectedKategori == null) ...[
                      const SizedBox(height: 6),
                      const Text('Pilih kategori pengeluaran',
                          style: TextStyle(fontSize: 11, color: _red)),
                    ],
                    const SizedBox(height: 20),
                    _labaToggleCard(
                      kurangiLaba: kurangiLaba,
                      onChanged: (v) => setSheet(() => kurangiLaba = v),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: (isLoading || selectedKategori == null)
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                if (selectedKategori == null) return;
                                setSheet(() => isLoading = true);
                                try {
                                  final user = FirebaseAuth.instance.currentUser;
                                  final amount = int.parse(_rawInt(amountCtrl.text));
                                  await FirebaseFirestore.instance.collection('kas_keluar').add({
                                    'userId': user?.uid,
                                    'userEmail': user?.email,
                                    'amount': amount,
                                    'keterangan': keteranganCtrl.text.trim(),
                                    'kategori': selectedKategori,
                                    'kurangiLaba': kurangiLaba,
                                    'date': Timestamp.fromDate(selectedDate),
                                    'createdAt': FieldValue.serverTimestamp(),
                                  });
                                  if (sheetCtx.mounted) {
                                    Navigator.pop(sheetCtx);
                                    setState(() {
                                      if (!DateUtils.isSameDay(selectedDate, _selectedDate)) {
                                        _selectedDate = selectedDate;
                                        _fadeCtrl..reset()..forward();
                                      }
                                    });
                                    AppNotification.saved('Kas keluar berhasil disimpan');
                                  }
                                } catch (e) {
                                  setSheet(() => isLoading = false);
                                  AppNotification.saveFailed();
                                }
                              },
                        icon: isLoading
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(color: _white, strokeWidth: 2))
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          selectedKategori == null ? 'Pilih kategori dulu' : 'Simpan Kas Keluar',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedKategori == null ? Colors.grey[400] : _red,
                          foregroundColor: _white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared: Toggle Pengaruh Laba ────────────────────────────────────────────
  Widget _labaToggleCard({
    required bool kurangiLaba,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kurangiLaba ? _redLt : _blueLt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: kurangiLaba ? _red.withValues(alpha: 0.2) : _blue.withValues(alpha: 0.2),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            kurangiLaba ? Icons.trending_down_rounded : Icons.swap_horiz_rounded,
            color: kurangiLaba ? _red : _blue,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Pengaruh ke Laba',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: kurangiLaba ? _red : _blue),
              ),
              Text(
                kurangiLaba
                    ? 'Mengurangi laba bersih'
                    : 'Hanya mengurangi kas, laba tidak berubah',
                style: const TextStyle(fontSize: 11, color: _inkMd),
              ),
            ]),
          ),
          Switch.adaptive(
            value: kurangiLaba,
            onChanged: onChanged,
            activeThumbColor: _red,
            inactiveThumbColor: _blue,
            inactiveTrackColor: _blue.withValues(alpha: 0.3),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _labaOptionChip(
            label: 'Kurangi Laba',
            sublabel: 'Biaya operasional\n& pengeluaran rutin',
            icon: Icons.trending_down_rounded,
            color: _red,
            isActive: kurangiLaba,
            onTap: () => onChanged(true),
          ),
          const SizedBox(width: 10),
          _labaOptionChip(
            label: 'Tidak Pengaruhi Laba',
            sublabel: 'Penarikan modal\n& investasi',
            icon: Icons.swap_horiz_rounded,
            color: _blue,
            isActive: !kurangiLaba,
            onTap: () => onChanged(false),
          ),
        ]),
      ]),
    );
  }

  Widget _labaOptionChip({
    required String label,
    required String sublabel,
    required IconData icon,
    required Color color,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.1) : _white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? color.withValues(alpha: 0.4) : _bdr,
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: isActive ? color : _inkLt, size: 16),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: isActive ? color : _inkLt)),
            const SizedBox(height: 2),
            Text(sublabel,
                style: const TextStyle(fontSize: 10, color: _inkLt, height: 1.3)),
          ]),
        ),
      ),
    );
  }

  // ── Action menu ─────────────────────────────────────────────────────────────
  void _showKasKeluarActions(_KasKeluarEntry entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (_kategoriColors[entry.kategori] ?? _inkLt).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_kategoriIcons[entry.kategori] ?? Icons.circle,
                  color: _kategoriColors[entry.kategori] ?? _inkLt, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.keterangan,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              Text(
                  NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
                      .format(entry.amount),
                  style: const TextStyle(fontSize: 12, color: _red, fontWeight: FontWeight.w700)),
            ])),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _showEditKasKeluar(entry);
              },
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Edit', style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _blue,
                side: const BorderSide(color: _blue),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _hapusKasKeluar(entry.docId, entry.keterangan);
              },
              icon: const Icon(Icons.delete_rounded, size: 18),
              label: const Text('Hapus', style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: _white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _hapusKasKeluar(String docId, String keterangan) async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(ctx).padding.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: _bdr, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(color: _redLt, shape: BoxShape.circle),
            child: const Icon(Icons.delete_forever_rounded, color: _red, size: 32),
          ),
          const SizedBox(height: 16),
          const Text('Hapus Kas Keluar?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _surf, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _bdr),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.receipt_long_rounded, size: 14, color: _inkLt),
              const SizedBox(width: 8),
              Flexible(
                child: Text(keterangan,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink),
                    textAlign: TextAlign.center,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          const Text('Data ini akan dihapus permanen dan tidak bisa dikembalikan.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: _inkMd, height: 1.5)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _inkMd,
                    side: const BorderSide(color: _bdr),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Batal',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.delete_rounded, size: 18),
                  label: const Text('Ya, Hapus',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: _white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );

    if (confirm != true) return;
    await FirebaseFirestore.instance.collection('kas_keluar').doc(docId).delete();
    if (mounted) {
      AppNotification.deleted('Kas keluar "$keterangan" berhasil dihapus');
    }
  }

  // ── Edit Kas Keluar ─────────────────────────────────────────────────────────
  void _showEditKasKeluar(_KasKeluarEntry entry) {
    final amountCtrl = TextEditingController(
        text: NumberFormat('#,##0', 'id_ID')
            .format(entry.amount.toInt())
            .replaceAll(',', '.'));
    final keteranganCtrl = TextEditingController(text: entry.keterangan);
    String selectedKategori = entry.kategori;
    DateTime selectedDate = entry.date;
    bool isLoading = false;
    bool kurangiLaba = entry.kurangiLaba;
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetRootCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: _white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                          child: Container(
                              width: 36, height: 4,
                              decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(2)))),
                      const SizedBox(height: 20),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: _orangeLt, borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.edit_rounded, color: _orange, size: 22),
                        ),
                        const SizedBox(width: 14),
                        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Edit Kas Keluar',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _ink)),
                          Text('Ubah data pengeluaran',
                              style: TextStyle(fontSize: 12, color: _inkMd)),
                        ]),
                      ]),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: amountCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [_ThousandFmt()],
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'Jumlah Pengeluaran',
                          prefixText: 'Rp ',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _orange, width: 2),
                          ),
                          prefixIcon: const Icon(Icons.money_off_rounded, color: _orange),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Jumlah harus diisi';
                          final n = int.tryParse(_rawInt(v)) ?? 0;
                          if (n <= 0) return 'Masukkan jumlah yang valid';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: keteranganCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: 'Keterangan',
                          prefixIcon: const Icon(Icons.notes_rounded),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _blue, width: 2),
                          ),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Keterangan harus diisi' : null,
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () async {
                          FocusScope.of(sheetCtx).unfocus();
                          await Future.delayed(const Duration(milliseconds: 80));
                          if (!sheetCtx.mounted) return;
                          final picked = await showDatePicker(
                            context: sheetRootCtx,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            builder: (ctx, child) => Theme(
                              data: Theme.of(ctx).copyWith(
                                  colorScheme: const ColorScheme.light(primary: _orange)),
                              child: child!,
                            ),
                          );
                          if (picked != null) setSheet(() => selectedDate = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          decoration: BoxDecoration(
                            color: _white, borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _bdr, width: 1.5),
                          ),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(color: _orangeLt, borderRadius: BorderRadius.circular(8)),
                              child: const Icon(Icons.calendar_today_rounded, color: _orange, size: 16),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Tanggal', style: TextStyle(fontSize: 10, color: _inkLt)),
                              const SizedBox(height: 2),
                              Text(DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(selectedDate),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink)),
                            ])),
                            const Icon(Icons.edit_calendar_rounded, color: _inkLt, size: 16),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Kategori',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: _kategoriKeluar.map((k) {
                          final isSelected = selectedKategori == k;
                          final color = _kategoriColors[k] ?? _inkLt;
                          final icon = _kategoriIcons[k] ?? Icons.circle;
                          return GestureDetector(
                            onTap: () => setSheet(() {
                              selectedKategori = k;
                              kurangiLaba = _defaultKurangiLaba.contains(k);
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? color.withValues(alpha: 0.1) : _surf,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: isSelected ? color : _bdr,
                                    width: isSelected ? 1.5 : 1),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(icon, size: 14, color: isSelected ? color : _inkLt),
                                const SizedBox(width: 6),
                                Text(k,
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? color : _ink)),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      _labaToggleCard(
                        kurangiLaba: kurangiLaba,
                        onChanged: (v) => setSheet(() => kurangiLaba = v),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: isLoading
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;
                                  setSheet(() => isLoading = true);
                                  try {
                                    final amount = int.parse(_rawInt(amountCtrl.text));
                                    await FirebaseFirestore.instance
                                        .collection('kas_keluar')
                                        .doc(entry.docId)
                                        .update({
                                      'amount': amount,
                                      'keterangan': keteranganCtrl.text.trim(),
                                      'kategori': selectedKategori,
                                      'kurangiLaba': kurangiLaba,
                                      'date': Timestamp.fromDate(selectedDate),
                                    });
                                    if (sheetCtx.mounted) {
                                      Navigator.pop(sheetCtx);
                                      setState(() {
                                        if (!DateUtils.isSameDay(selectedDate, _selectedDate)) {
                                          _selectedDate = selectedDate;
                                          _fadeCtrl..reset()..forward();
                                        }
                                      });
                                      AppNotification.updated('Kas keluar berhasil diperbarui');
                                    }
                                  } catch (e) {
                                    setSheet(() => isLoading = false);
                                    AppNotification.saveFailed();
                                  }
                                },
                          icon: isLoading
                              ? const SizedBox(width: 18, height: 18,
                                  child: CircularProgressIndicator(color: _white, strokeWidth: 2))
                              : const Icon(Icons.save_rounded),
                          label: const Text('Simpan Perubahan',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _orange, foregroundColor: _white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _normalizeMethod(String raw, String sub) {
    if (raw.contains('tunai') || raw.contains('cash')) return 'Tunai';
    if (raw.contains('qris')) return 'QRIS';
    if (raw.contains('transfer')) return 'Transfer';
    if (raw.contains('e-wallet') || raw.contains('ewallet')) {
      return sub.isNotEmpty ? 'E-Wallet ($sub)' : 'E-Wallet';
    }
    if (raw.contains('hutang') || raw == '' || raw == '-') return 'Hutang';
    if (raw.contains('sebagian')) return 'Bayar Sebagian';
    return raw.isNotEmpty ? raw[0].toUpperCase() + raw.substring(1) : 'Lainnya';
  }

  IconData _iconForMethod(String method) {
    final m = method.toLowerCase();
    if (m.contains('tunai')) return Icons.payments_rounded;
    if (m.contains('qris')) return Icons.qr_code_2_rounded;
    if (m.contains('transfer')) return Icons.account_balance_rounded;
    if (m.contains('e-wallet')) return Icons.wallet_rounded;
    if (m.contains('hutang')) return Icons.pending_rounded;
    if (m.contains('sebagian')) return Icons.money_off_rounded;
    return Icons.payment_rounded;
  }

  Color _colorForMethod(String method) {
    final m = method.toLowerCase();
    if (m.contains('tunai')) return _green;
    if (m.contains('qris')) return const Color(0xFF9C27B0);
    if (m.contains('transfer')) return _blue;
    if (m.contains('e-wallet')) return _orange;
    if (m.contains('hutang')) return _red;
    if (m.contains('sebagian')) return _red;
    return _inkLt;
  }

  String _statusLabel(Map<String, dynamic> data) {
    final isPaid = data['isPaid'] ?? false;
    final isBayarSebagian = data['isBayarSebagian'] ?? false;
    final remainingDebt = (data['remainingDebt'] ?? 0) as num;
    if (isPaid) return 'Lunas';
    if (isBayarSebagian && remainingDebt > 0) return 'Sebagian';
    return 'Hutang';
  }

  Color _statusColor(Map<String, dynamic> data) {
    final label = _statusLabel(data);
    if (label == 'Lunas') return _green;
    if (label == 'Sebagian') return _orange;
    return _red;
  }

  double _hitungProfitTx(Map<String, dynamic> data) {
    final adminFee = (data['adminFee'] ?? 0).toDouble();
    final hargaBeli = (data['hargaBeli'] ?? 0).toDouble();
    final hargaJual = (data['nominal'] ?? 0).toDouble();
    final selisih = hargaBeli > 0 ? (hargaJual - hargaBeli) : 0.0;
    return selisih + adminFee;
  }

  List<_PaymentEntry> _extractPaymentsOnDate(List<QueryDocumentSnapshot> docs) {
    final entries = <_PaymentEntry>[];
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final history = data['paymentHistory'];
      final txProfit = _hitungProfitTx(data);

      if (history is List && history.isNotEmpty) {
        bool profitSudahDihitung = false;
        for (final h in history) {
          if (h is! Map<String, dynamic>) continue;
          DateTime? payDate;
          final rawDate = h['date'] ?? h['paidAt'] ?? h['paymentDate'];
          if (rawDate is Timestamp) {
            payDate = rawDate.toDate();
          } else if (rawDate is String) {
            payDate = DateTime.tryParse(rawDate);
          }
          if (payDate == null) continue;
          if (!DateUtils.isSameDay(payDate, _selectedDate)) continue;
          final amount = (h['amount'] ?? h['partialAmount'] ?? 0).toDouble();
          if (amount <= 0) continue;
          final method = _normalizeMethod(
            (h['paymentMethod'] ?? '').toString().toLowerCase(),
            (h['paymentSubOption'] ?? '').toString(),
          );
          final isFirst = !profitSudahDihitung;
          profitSudahDihitung = true;
          entries.add(_PaymentEntry(
              docId: doc.id,
              data: data,
              amount: amount,
              profit: (data['isPaid'] == true && isFirst) ? txProfit : 0.0,
              method: method,
              paymentDate: payDate));
        }
      } else {
        final isPaid = data['isPaid'] ?? false;
        final isBayarSebagian = data['isBayarSebagian'] ?? false;
        DateTime? payDate;
        if (isPaid) {
          final raw = data['paidAt'];
          if (raw is Timestamp) payDate = raw.toDate();
        } else if (isBayarSebagian) {
          final raw = data['lastPaidAt'];
          if (raw is Timestamp) payDate = raw.toDate();
        }
        if (payDate == null) continue;
        if (!DateUtils.isSameDay(payDate, _selectedDate)) continue;
        double amount = 0;
        if (isPaid && !isBayarSebagian) {
          amount = (data['totalAmount'] ?? 0).toDouble();
        } else if (isBayarSebagian) {
          amount = (data['partialAmount'] ?? 0).toDouble();
        }
        if (amount <= 0) continue;
        final method = _normalizeMethod(
          (data['paymentMethod'] ?? '').toString().toLowerCase(),
          (data['paymentSubOption'] ?? '').toString(),
        );
        entries.add(_PaymentEntry(
            docId: doc.id,
            data: data,
            amount: amount,
            profit: txProfit,
            method: method,
            paymentDate: payDate));
      }
    }
    entries.sort((a, b) => b.paymentDate.compareTo(a.paymentDate));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      backgroundColor: _surf,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showTambahKasKeluar,
        backgroundColor: _red,
        elevation: 2,
        icon: const Icon(Icons.add_rounded, color: _white),
        label: const Text('Kas Keluar',
            style: TextStyle(color: _white, fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('transactions')
                .where('userId', isEqualTo: user?.uid)
                .where('date',
                    isGreaterThanOrEqualTo:
                        DateTime.now().subtract(const Duration(days: 180)))
                .snapshots(),
            builder: (ctx, snapTx) {
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('kas_keluar')
                    .where('userId', isEqualTo: user?.uid)
                    .where('date',
                        isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(
                            _selectedDate.year, _selectedDate.month, _selectedDate.day)))
                    .where('date',
                        isLessThan: Timestamp.fromDate(DateTime(
                            _selectedDate.year, _selectedDate.month, _selectedDate.day + 1)))
                    .snapshots(),
                builder: (ctx2, snapKk) {
                  if (snapTx.connectionState == ConnectionState.waiting ||
                      snapKk.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: _blue));
                  }

                  final allTxDocs = snapTx.data?.docs ?? [];
                  final kasKeluarDocs = snapKk.data?.docs ?? [];
                  final entries = _extractPaymentsOnDate(allTxDocs);

                  final kasKeluarEntries = kasKeluarDocs.map((doc) {
                    final d = doc.data() as Map<String, dynamic>;
                    final rawDate = d['date'];
                    DateTime dt = rawDate is Timestamp ? rawDate.toDate() : DateTime.now();
                    return _KasKeluarEntry(
                      docId: doc.id,
                      keterangan: d['keterangan'] ?? '-',
                      kategori: d['kategori'] ?? 'Lainnya',
                      amount: (d['amount'] ?? 0).toDouble(),
                      date: dt,
                      kurangiLaba: d['kurangiLaba'] ?? true,
                    );
                  }).toList();
                  kasKeluarEntries.sort((a, b) => b.date.compareTo(a.date));

                  final totalMasuk = entries.fold<double>(0, (s, e) => s + e.amount);
                  final totalKeluar = kasKeluarEntries.fold<double>(0, (s, e) => s + e.amount);
                  final saldo = totalMasuk - totalKeluar;
                  final profitKotor = entries.fold<double>(0, (s, e) => s + e.profit);
                  final potonganLaba = kasKeluarEntries
                      .where((e) => e.kurangiLaba)
                      .fold<double>(0, (s, e) => s + e.amount);
                  final profitBersih = profitKotor - potonganLaba;

                  final tunai = entries
                      .where((e) => e.method.toLowerCase().contains('tunai'))
                      .fold<double>(0, (s, e) => s + e.amount);
                  final nonTunai = entries
                      .where((e) =>
                          !e.method.toLowerCase().contains('tunai') &&
                          !e.method.toLowerCase().contains('hutang'))
                      .fold<double>(0, (s, e) => s + e.amount);

                  if (entries.isEmpty && kasKeluarEntries.isEmpty) {
                    return _emptyState();
                  }

                  return FadeTransition(
                    opacity: _fade,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      children: [
                        _ringkasanCard(fmt, totalMasuk, totalKeluar, saldo),
                        const SizedBox(height: 12),
                        _labaCard(fmt, profitKotor, potonganLaba, profitBersih, totalKeluar),
                        const SizedBox(height: 20),
                        if (entries.isNotEmpty) ...[
                          _sectionHeader(
                            icon: Icons.arrow_downward_rounded,
                            iconColor: _green,
                            title: 'Kas Masuk',
                            count: entries.length,
                            total: fmt.format(totalMasuk),
                            totalColor: _green,
                          ),
                          const SizedBox(height: 10),
                          _kasMasukBreakdown(fmt, tunai, nonTunai),
                          const SizedBox(height: 8),
                          ...entries.map((e) => _txTile(e, fmt)),
                          const SizedBox(height: 16),
                        ],
                        if (kasKeluarEntries.isNotEmpty) ...[
                          _sectionHeader(
                            icon: Icons.arrow_upward_rounded,
                            iconColor: _red,
                            title: 'Kas Keluar',
                            count: kasKeluarEntries.length,
                            total: fmt.format(totalKeluar),
                            totalColor: _red,
                          ),
                          const SizedBox(height: 10),
                          _kasKeluarBreakdown(fmt, potonganLaba, totalKeluar - potonganLaba),
                          const SizedBox(height: 8),
                          ...kasKeluarEntries.map((e) => _kasKeluarTile(e, fmt)),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_blue, _blueDk],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _white, size: 19),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(
                  child: Text('Arus Kas',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _white, fontSize: 18, fontWeight: FontWeight.w700))),
              const SizedBox(width: 48),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, color: _white, size: 26),
                  onPressed: _prevDay,
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: _pickDate,
                    child: Column(children: [
                      Text(
                        _isToday ? 'Hari Ini' : DateFormat('EEEE', 'id_ID').format(_selectedDate),
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(height: 2),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(
                          DateFormat('dd MMMM yyyy', 'id_ID').format(_selectedDate),
                          style: const TextStyle(
                              color: _white, fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.calendar_today_rounded, color: Colors.white60, size: 13),
                      ]),
                    ]),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right_rounded,
                      color: _isToday ? Colors.white30 : _white, size: 26),
                  onPressed: _isToday ? null : _nextDay,
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Ringkasan: Kas Bersih + Masuk/Keluar ────────────────────────────────────
  Widget _ringkasanCard(NumberFormat fmt, double masuk, double keluar, double saldo) {
    final isPositive = saldo >= 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _bdr),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isPositive ? _greenLt : _redLt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                size: 13, color: isPositive ? _green : _red,
              ),
              const SizedBox(width: 4),
              Text('Kas Bersih',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: isPositive ? _green : _red)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          fmt.format(saldo),
          style: TextStyle(
            fontSize: 30, fontWeight: FontWeight.w800,
            color: isPositive ? _ink : _red,
          ),
        ),
        const SizedBox(height: 16),
        Container(height: 1, color: _bdr),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _flowStat(
            icon: Icons.arrow_downward_rounded,
            label: 'Kas Masuk',
            value: fmt.format(masuk),
            color: _green,
            bgColor: _greenLt,
          )),
          Container(width: 1, height: 44, color: _bdr,
              margin: const EdgeInsets.symmetric(horizontal: 12)),
          Expanded(child: _flowStat(
            icon: Icons.arrow_upward_rounded,
            label: 'Kas Keluar',
            value: fmt.format(keluar),
            color: _red,
            bgColor: _redLt,
          )),
        ]),
      ]),
    );
  }

  Widget _flowStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color bgColor,
  }) {
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, color: color, size: 12),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 5),
      Text(value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
    ]);
  }

  // ── Laba Card ────────────────────────────────────────────────────────────────
  Widget _labaCard(NumberFormat fmt, double profitKotor, double potonganLaba,
      double profitBersih, double totalKeluar) {
    final isProfit = profitBersih >= 0;
    final sisaKeluar = totalKeluar - potonganLaba;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _bdr),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isProfit ? _greenLt : _redLt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isProfit ? Icons.emoji_events_rounded : Icons.warning_amber_rounded,
              color: isProfit ? _green : _red, size: 18,
            ),
          ),
          const SizedBox(width: 12),
          const Text('Ringkasan Laba',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
        ]),
        const SizedBox(height: 16),
        Container(height: 1, color: _bdr),
        const SizedBox(height: 14),
        _labaItemRow(
          icon: Icons.receipt_long_rounded,
          label: 'Laba Kotor Transaksi',
          value: fmt.format(profitKotor),
          valueColor: _green,
        ),
        const SizedBox(height: 10),
        _labaItemRow(
          icon: Icons.remove_circle_outline_rounded,
          label: 'Biaya Operasional',
          value: '− ${fmt.format(potonganLaba)}',
          valueColor: _red,
        ),
        if (sisaKeluar > 0) ...[
          const SizedBox(height: 10),
          _labaItemRow(
            icon: Icons.swap_horiz_rounded,
            label: 'Keluar (tidak pengaruhi laba)',
            value: fmt.format(sisaKeluar),
            valueColor: _purple,
            isSmall: true,
          ),
        ],
        const SizedBox(height: 14),
        Container(height: 1, color: _bdr),
        const SizedBox(height: 14),
        Row(children: [
          const Text('Laba Bersih',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isProfit ? _greenLt : _redLt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isProfit ? _green.withValues(alpha: 0.3) : _red.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              fmt.format(profitBersih),
              style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800,
                color: isProfit ? _green : _red,
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _labaItemRow({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
    bool isSmall = false,
  }) {
    return Row(children: [
      Icon(icon, color: _inkLt, size: isSmall ? 13 : 15),
      const SizedBox(width: 10),
      Expanded(
        child: Text(label,
            style: TextStyle(fontSize: isSmall ? 11 : 12, color: _inkMd)),
      ),
      Text(value,
          style: TextStyle(
              fontSize: isSmall ? 12 : 13,
              fontWeight: FontWeight.w700,
              color: valueColor)),
    ]);
  }

  // ── Section Header ──────────────────────────────────────────────────────────
  Widget _sectionHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    required int count,
    required String total,
    required Color totalColor,
  }) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, color: iconColor, size: 15),
      ),
      const SizedBox(width: 10),
      Text('$title ($count)',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
      const Spacer(),
      Text(total,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: totalColor)),
    ]);
  }

  // ── Breakdown cards ─────────────────────────────────────────────────────────
  Widget _kasMasukBreakdown(NumberFormat fmt, double tunai, double nonTunai) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _greenLt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Expanded(child: _breakdownStat(
          icon: Icons.payments_rounded, label: 'Tunai',
          value: fmt.format(tunai), color: _green,
        )),
        Container(width: 1, height: 32, color: _green.withValues(alpha: 0.2)),
        Expanded(child: _breakdownStat(
          icon: Icons.credit_card_rounded, label: 'Non-Tunai',
          value: fmt.format(nonTunai), color: _blue,
        )),
      ]),
    );
  }

  Widget _kasKeluarBreakdown(NumberFormat fmt, double kurangiLaba, double tidakKurangi) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _redLt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _red.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Expanded(child: _breakdownStat(
          icon: Icons.trending_down_rounded, label: 'Kurangi Laba',
          value: fmt.format(kurangiLaba), color: _red,
        )),
        Container(width: 1, height: 32, color: _red.withValues(alpha: 0.2)),
        Expanded(child: _breakdownStat(
          icon: Icons.swap_horiz_rounded, label: 'Tidak ∝ Laba',
          value: fmt.format(tidakKurangi), color: _purple,
        )),
      ]),
    );
  }

  Widget _breakdownStat({
    required IconData icon, required String label,
    required String value, required Color color,
  }) {
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
    ]);
  }

  // ── Transaction Tile ────────────────────────────────────────────────────────
  Widget _txTile(_PaymentEntry entry, NumberFormat fmt) {
    final data = entry.data;
    final method = entry.method;
    final color = _colorForMethod(method);
    final statusLabel = _statusLabel(data);
    final statusColor = _statusColor(data);
    final isPaid = data['isPaid'] ?? false;
    final isSebagian = data['isBayarSebagian'] ?? false;
    final statusIcon = isSebagian && !isPaid
        ? Icons.money_off_rounded
        : isPaid ? Icons.check_circle : Icons.pending;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _bdr),
        boxShadow: const [
          BoxShadow(color: Color(0x05000000), blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Get.to(() =>
              TransactionDetailScreen(transactionId: entry.docId, transactionData: data)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(11)),
                child: Icon(_iconForMethod(method), color: color, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(data['productName'] ?? '-',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${data['customerNumber'] ?? ''}'
                  '${(data['customerName'] ?? '').isNotEmpty ? ' · ${data['customerName']}' : ''}',
                  style: const TextStyle(fontSize: 11, color: _inkMd),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(children: [
                  if (entry.profit != 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: entry.profit >= 0 ? _greenLt : _redLt,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text('Laba ${fmt.format(entry.profit)}',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600,
                              color: entry.profit >= 0 ? _green : _red)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(DateFormat('HH:mm', 'id_ID').format(entry.paymentDate),
                      style: const TextStyle(fontSize: 10, color: _inkLt)),
                ]),
              ])),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(fmt.format(entry.amount),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(statusIcon, color: statusColor, size: 10),
                    const SizedBox(width: 3),
                    Text(statusLabel,
                        style: TextStyle(
                            color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: _inkLt, size: 16),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Kas Keluar Tile ─────────────────────────────────────────────────────────
  Widget _kasKeluarTile(_KasKeluarEntry entry, NumberFormat fmt) {
    final color = _kategoriColors[entry.kategori] ?? _inkLt;
    final icon = _kategoriIcons[entry.kategori] ?? Icons.circle;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _bdr),
        boxShadow: const [
          BoxShadow(color: Color(0x05000000), blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showKasKeluarActions(entry),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entry.keterangan,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5)),
                    child: Text(entry.kategori,
                        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: entry.kurangiLaba ? _redLt : _purpleLt,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        entry.kurangiLaba ? Icons.trending_down_rounded : Icons.swap_horiz_rounded,
                        size: 9, color: entry.kurangiLaba ? _red : _purple,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        entry.kurangiLaba ? '−Laba' : '∝Laba',
                        style: TextStyle(
                            fontSize: 9, fontWeight: FontWeight.w600,
                            color: entry.kurangiLaba ? _red : _purple),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  Text(DateFormat('HH:mm', 'id_ID').format(entry.date),
                      style: const TextStyle(fontSize: 10, color: _inkLt)),
                ]),
              ])),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(fmt.format(entry.amount),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: _red)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: _redLt,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: _red.withValues(alpha: 0.2)),
                  ),
                  child: const Text('Keluar',
                      style: TextStyle(color: _red, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: _inkLt, size: 16),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Empty State ─────────────────────────────────────────────────────────────
  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: const BoxDecoration(color: _blueLt, shape: BoxShape.circle),
              child: const Icon(Icons.account_balance_wallet_outlined, size: 48, color: _blue),
            ),
            const SizedBox(height: 20),
            const Text('Tidak Ada Transaksi',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 6),
            Text(
              DateUtils.isSameDay(_selectedDate, DateTime.now())
                  ? 'Belum ada kas masuk atau keluar hari ini'
                  : 'Tidak ada data pada tanggal ini',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _inkMd),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      );
}