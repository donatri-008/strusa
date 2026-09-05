import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../services/printer_service.dart';
import '../../utils/app_notification.dart';
import 'new_transaction_screen.dart';
import 'transaction_success_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Thousand separator formatter
// ─────────────────────────────────────────────────────────────────────────────
class _ThousandSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final digits = newValue.text.replaceAll('.', '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final n = int.tryParse(digits) ?? 0;
    final formatted =
        NumberFormat('#,##0', 'id_ID').format(n).replaceAll(',', '.');
    return newValue.copyWith(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length));
  }
}

String _rawInt(String formatted) => formatted.replaceAll('.', '');

// ─────────────────────────────────────────────────────────────────────────────
// Model metode pembayaran
// ─────────────────────────────────────────────────────────────────────────────
class PaymentMethod {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  final List<String>? subOptions;

  const PaymentMethod({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
    this.subOptions,
  });
}

const _paymentMethods = [
  PaymentMethod(
    key: 'transfer_bank',
    label: 'Transfer Bank',
    icon: Icons.account_balance,
    color: Color(0xFF2196F3),
  ),
  PaymentMethod(
    key: 'qris',
    label: 'QRIS',
    icon: Icons.qr_code_2,
    color: Color(0xFF9C27B0),
  ),
  PaymentMethod(
    key: 'tunai',
    label: 'Tunai',
    icon: Icons.payments,
    color: Color(0xFF4CAF50),
  ),
  PaymentMethod(
    key: 'E-Wallet',
    label: 'E-Wallet',
    icon: Icons.wallet,
    color: Color(0xFFFF9800),
    subOptions: ['OVO', 'GoPay', 'Dana', 'ShopeePay', 'LinkAja'],
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Helper category checks
// ─────────────────────────────────────────────────────────────────────────────

bool _categoryHidesAdminFee(String category) =>
    category == 'Pulsa' ||
    category == 'Paket Data' ||
    category == 'Token Listrik' ||
    category == 'Lainnya';

bool _categoryHidesAtasNama(String category) =>
    category == 'Pulsa' ||
    category == 'Paket Data' ||
    category == 'E-Wallet' ||
    category == 'Jasa Transfer' ||
    category == 'Lainnya';

bool _categoryHasNominalFee(String category) =>
    category == 'Tagihan' ||
    category == 'E-Wallet' ||
    category == 'Jasa Transfer';

// ─────────────────────────────────────────────────────────────────────────────

class PaymentScreen extends StatefulWidget {
  // Multi-item cart
  final List<CartItem> cartItems;

  // Shared customer info
  final String customerNumber;
  final String customerName;
  final String atasNama;
  final DateTime transactionDate;

  const PaymentScreen({
    super.key,
    required this.cartItems,
    required this.customerNumber,
    required this.customerName,
    this.atasNama = '',
    required this.transactionDate,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String? _selectedMethodKey;
  String? _selectedSubOption;
  final TextEditingController _paidAmountCtrl = TextEditingController();
  bool _isProcessing = false;
  late DateTime _paymentDate;

  // ── FIX #3: flag eksplisit untuk hutang penuh, tidak bergantung nilai field ──
  bool _hutangPenuhMode = false;

  // ── Computed ───────────────────────────────────────────────────────────────

  int get _totalAmount =>
      widget.cartItems.fold(0, (s, i) => s + i.subtotalJual);

  int get _totalBeli =>
      widget.cartItems.fold(0, (s, i) => s + i.subtotalBeli);

  int get _paidAmount {
    if (_hutangPenuhMode) return 0;
    if (_paidAmountCtrl.text.trim().isEmpty) return _totalAmount;
    return int.tryParse(_rawInt(_paidAmountCtrl.text)) ?? 0;
  }

  /// Kembalian jika bayar lebih dari total
  int get _kembalian {
    if (_hutangPenuhMode) return 0;
    final lebih = _paidAmount - _totalAmount;
    return lebih > 0 ? lebih : 0;
  }

  int get _sisaHutang {
    if (_hutangPenuhMode) return _totalAmount;
    final sisa = _totalAmount - _paidAmount;
    return sisa > 0 ? sisa : 0;
  }

  /// Bayar lebih dari total tagihan
  bool get _isBayarLebih => !_hutangPenuhMode && _kembalian > 0;

  // ── FIX #3: pakai flag eksplisit, bukan deteksi dari nilai field ──
  bool get _isBayarSebagian =>
      !_hutangPenuhMode &&
      _sisaHutang > 0 &&
      _paidAmount > 0 &&
      !_isBayarLebih;

  bool get _isHutangPenuh => _hutangPenuhMode;

  PaymentMethod? get _currentMethodDef =>
      _paymentMethods.where((m) => m.key == _selectedMethodKey).firstOrNull;

  bool get _isValid {
    if (_isHutangPenuh) return true;
    if (_selectedMethodKey == null) return false;
    if (_selectedMethodKey == 'E-Wallet' && _selectedSubOption == null) {
      return false;
    }
    final typed = _rawInt(_paidAmountCtrl.text);
    if (typed.isNotEmpty) {
      final v = int.tryParse(typed) ?? 0;
      if (v < 0) return false;
    }
    return true;
  }

  String get _buttonLabel {
    if (_isHutangPenuh) return 'Simpan sebagai Hutang';
    if (_isBayarSebagian) return 'Proses (Bayar Sebagian)';
    if (_isBayarLebih) return 'Proses (Ada Kembalian)';
    return 'Proses Transaksi';
  }

  // ── Init ───────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _paymentDate = widget.transactionDate;
    _paidAmountCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _paidAmountCtrl.dispose();
    super.dispose();
  }

  // ── Date Picker ────────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Tanggal Pembayaran',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF2196F3))),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _paymentDate = picked);
  }

  // ── FIX #3: set flag hutang penuh secara eksplisit ──
  void _setHutangPenuh() {
    setState(() {
      _hutangPenuhMode = true;
      _paidAmountCtrl.clear();
      _selectedMethodKey = null;
      _selectedSubOption = null;
    });
  }

  /// Reset hutang penuh saat user mulai mengetik jumlah bayar
  void _clearHutangPenuhMode() {
    if (_hutangPenuhMode) {
      setState(() => _hutangPenuhMode = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(title: const Text('Pembayaran')),
      body: Column(children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildDatePicker(),
              const SizedBox(height: 16),
              _buildCard(
                title: 'Ringkasan Transaksi',
                children: [
                  if (widget.customerName.isNotEmpty)
                    _infoRow('Nama Pelanggan', widget.customerName),
                  if (widget.customerNumber.isNotEmpty)
                    _infoRow('No. Pelanggan', widget.customerNumber),
                  const Divider(height: 20),

                  // ── Item list ──
                  ...widget.cartItems.asMap().entries.map(
                      (e) => _buildItemRow(e.key, e.value, fmt)),

                  const Divider(height: 20),
                  _infoRow('TOTAL TAGIHAN', fmt.format(_totalAmount),
                      isTotal: true),

                  // Estimasi laba
                  if (_totalBeli > 0) ...[
                    const SizedBox(height: 8),
                    _buildLabaRow(fmt),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              _buildCard(
                title: 'Jumlah yang Dibayar',
                children: [
                  // ── Info hutang penuh aktif ──
                  if (_isHutangPenuh)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF44336).withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFFF44336)
                                .withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.pending_outlined,
                            color: Color(0xFFF44336), size: 16),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Mode Hutang Penuh aktif. Tidak perlu pilih metode pembayaran.',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFF44336),
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _hutangPenuhMode = false;
                          }),
                          child: const Icon(Icons.close_rounded,
                              color: Color(0xFFF44336), size: 18),
                        ),
                      ]),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2196F3).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFF2196F3)
                                .withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline,
                            color: Color(0xFF2196F3), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Kosongkan jika bayar penuh (${fmt.format(_totalAmount)}). ',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF2196F3),
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ]),
                    ),
                  const SizedBox(height: 14),
                  // ── FIX #3: onChanged reset flag hutang penuh ──
                  TextFormField(
                    controller: _paidAmountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_ThousandSeparatorFormatter()],
                    enabled: !_isHutangPenuh,
                    onChanged: (_) {
                      _clearHutangPenuhMode();
                      setState(() {});
                    },
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _isHutangPenuh ? Colors.grey : Colors.black),
                    decoration: InputDecoration(
                      labelText: 'Jumlah Dibayar',
                      hintText: _isHutangPenuh
                          ? 'Dicatat sebagai hutang penuh'
                          : 'Isi jumlah yang akan dibayar',
                      prefixText: 'Rp ',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Color(0xFF2196F3), width: 2),
                      ),
                      errorText: () {
                        if (_isHutangPenuh) return null;
                        if (_paidAmountCtrl.text.trim().isEmpty) return null;
                        final v =
                            int.tryParse(_rawInt(_paidAmountCtrl.text)) ?? 0;
                        if (v < 0) return 'Jumlah tidak boleh negatif';
                        return null;
                      }(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isHutangPenuh ? null : _setHutangPenuh,
                      icon: Icon(Icons.pending_outlined,
                          size: 18,
                          color: _isHutangPenuh
                              ? Colors.grey
                              : const Color(0xFFF44336)),
                      label: Text(
                        _isHutangPenuh
                            ? 'Mode Hutang Penuh Aktif'
                            : 'Tandai sebagai Hutang Penuh',
                        style: TextStyle(
                          color: _isHutangPenuh
                              ? Colors.grey
                              : const Color(0xFFF44336),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: _isHutangPenuh
                                ? Colors.grey
                                : const Color(0xFFF44336)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildPaymentPreview(fmt),
                ],
              ),
              const SizedBox(height: 16),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _isHutangPenuh ? 0.4 : 1.0,
                child: IgnorePointer(
                  ignoring: _isHutangPenuh,
                  child: _buildCard(
                    title: 'Metode Pembayaran',
                    titleSuffix: _isHutangPenuh
                        ? _badge('Hutang Penuh', Colors.orange)
                        : (_isBayarSebagian && _selectedMethodKey == null)
                            ? _badge('Wajib dipilih', Colors.red)
                            : null,
                    children: [
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2.8,
                        children:
                            _paymentMethods.map(_methodTile).toList(),
                      ),
                      if (_selectedMethodKey == 'E-Wallet') ...[
                        const SizedBox(height: 16),
                        const Text('Pilih Platform',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: (_currentMethodDef?.subOptions ?? [])
                              .map((sub) => ChoiceChip(
                                    label: Text(sub,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _selectedSubOption == sub
                                              ? Colors.white
                                              : Colors.black,
                                        )),
                                    selected: _selectedSubOption == sub,
                                    selectedColor: const Color(0xFFFF9800),
                                    onSelected: (_) => setState(
                                        () => _selectedSubOption = sub),
                                  ))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
        // ── Tombol Proses ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed:
                    (_isProcessing || !_isValid) ? null : _processPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isBayarLebih
                      ? const Color(0xFF00BCD4)
                      : _isBayarSebagian
                          ? const Color(0xFFFF9800)
                          : _isHutangPenuh
                              ? const Color(0xFFF44336)
                              : const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isBayarLebih
                                ? Icons.currency_exchange_rounded
                                : _isBayarSebagian
                                    ? Icons.payments_outlined
                                    : _isHutangPenuh
                                        ? Icons.pending_outlined
                                        : Icons.check_circle_outline,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(_buttonLabel,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Item Row di ringkasan ──────────────────────────────────────────────────

  Widget _buildItemRow(int index, CartItem item, NumberFormat fmt) {
    final isMulti = widget.cartItems.length > 1;
    final category = item.product.category;
    final nominal = int.tryParse(item.nominal.replaceAll('.', '')) ?? 0;
    final adminFee = int.tryParse(item.adminFee.replaceAll('.', '')) ??
        item.product.adminFee;
    final showNominalFee = _categoryHasNominalFee(category);
    final showAdminFee =
        adminFee > 0 && !_categoryHidesAdminFee(category);
    final showAtasNama =
        item.atasNama.trim().isNotEmpty && !_categoryHidesAtasNama(category);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFF2196F3).withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (isMulti) ...[
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1, right: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2196F3)),
                ),
              ),
            ),
          ],
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(item.product.name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              if (item.product.category.isNotEmpty)
                Text(item.product.category,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[500])),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (item.quantity > 1)
              Text(
                  '${fmt.format(item.hargaJual > 0 ? item.hargaJual : item.subtotalJual ~/ item.quantity)} ×${item.quantity}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            Text(fmt.format(item.subtotalJual),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2196F3))),
          ]),
        ]),

        if (item.customerNumber.isNotEmpty || showAtasNama ||
            (showNominalFee && nominal > 0) || showAdminFee) ...[
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: Colors.grey.withValues(alpha: 0.15)),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              if (item.customerNumber.isNotEmpty)
                _detailRow(Icons.tag_rounded, 'No. Pelanggan',
                    item.customerNumber),
              if (showAtasNama)
                _detailRow(Icons.badge_outlined, 'Atas Nama',
                    item.atasNama.trim()),
              if (showNominalFee && nominal > 0)
                _detailRow(Icons.payments_outlined, 'Nominal',
                    fmt.format(nominal)),
              if (showAdminFee)
                _detailRow(Icons.receipt_long_outlined, 'Biaya Admin',
                    fmt.format(adminFee)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 12, color: Colors.grey[400]),
          const SizedBox(width: 5),
          Text('$label: ',
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151))),
          ),
        ]),
      );

  Widget _buildLabaRow(NumberFormat fmt) {
    final laba = _totalAmount - _totalBeli;
    final isProfit = laba >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isProfit
            ? Colors.green.withValues(alpha: 0.07)
            : Colors.red.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isProfit
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Row(children: [
        Icon(
          isProfit ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          size: 14,
          color: isProfit ? Colors.green[700] : Colors.red[700],
        ),
        const SizedBox(width: 6),
        Text(
          'Estimasi Laba: ${fmt.format(laba.abs())}${laba < 0 ? ' (rugi)' : ''}',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isProfit ? Colors.green[700] : Colors.red[700]),
        ),
      ]),
    );
  }

  // ── Payment Preview ────────────────────────────────────────────────────────

  Widget _buildPaymentPreview(NumberFormat fmt) {
    if (_isHutangPenuh) {
      return _infoBanner(
        icon: Icons.pending_outlined,
        color: const Color(0xFFF44336),
        text: 'Seluruh tagihan ${fmt.format(_totalAmount)} dicatat sebagai hutang.',
      );
    }

    if (_paidAmountCtrl.text.trim().isEmpty) {
      return _infoBanner(
        icon: Icons.check_circle_outline,
        color: const Color(0xFF4CAF50),
        text:
            'Bayar penuh ${fmt.format(_totalAmount)} → transaksi langsung LUNAS.',
      );
    }
    final v = int.tryParse(_rawInt(_paidAmountCtrl.text)) ?? 0;
    if (v <= 0) return const SizedBox.shrink();

    // ── Bayar LEBIH → tampilkan kembalian ──
    if (_isBayarLebih) {
      return Column(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF00BCD4).withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFF00BCD4).withValues(alpha: 0.35)),
          ),
          child: Column(children: [
            _splitRow(
              'Dibayar',
              fmt.format(v),
              const Color(0xFF2196F3),
              Icons.payments_outlined,
            ),
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1)),
            _splitRow(
              'Total Tagihan',
              fmt.format(_totalAmount),
              Colors.grey,
              Icons.receipt_outlined,
            ),
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1)),
            _splitRow(
              'Kembalian',
              fmt.format(_kembalian),
              const Color(0xFF00BCD4),
              Icons.currency_exchange_rounded,
            ),
          ]),
        ),
        const SizedBox(height: 8),
        _infoBanner(
          icon: Icons.currency_exchange_rounded,
          color: const Color(0xFF00BCD4),
          text:
              'Kembalikan ${fmt.format(_kembalian)} kepada pelanggan.',
        ),
      ]);
    }

    // ── Bayar LUNAS ──
    if (v == _totalAmount) {
      return _infoBanner(
        icon: Icons.check_circle_outline,
        color: const Color(0xFF4CAF50),
        text: 'Bayar penuh → transaksi LUNAS.',
      );
    }

    // ── Bayar SEBAGIAN ──
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFF9800).withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFFFF9800).withValues(alpha: 0.35)),
        ),
        child: Column(children: [
          _splitRow('Dibayar sekarang', fmt.format(v),
              const Color(0xFF4CAF50), Icons.payments_outlined),
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1)),
          _splitRow('Sisa → otomatis jadi hutang', fmt.format(_sisaHutang),
              const Color(0xFFF44336), Icons.warning_amber_rounded),
        ]),
      ),
      const SizedBox(height: 8),
      _infoBanner(
        icon: Icons.info_outline,
        color: const Color(0xFFFF9800),
        text: 'Sisa ${fmt.format(_sisaHutang)} akan tercatat sebagai hutang.',
      ),
    ]);
  }

  Widget _splitRow(String label, String value, Color color, IconData icon) =>
      Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.w500))),
        Text(value,
            style: TextStyle(
                fontSize: 13, color: color, fontWeight: FontWeight.bold)),
      ]);

  // ── Date Picker Widget ─────────────────────────────────────────────────────

  Widget _buildDatePicker() {
    final isToday = DateUtils.isSameDay(_paymentDate, DateTime.now());
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFF2196F3).withValues(alpha: 0.4),
              width: 1.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.calendar_today_rounded,
                color: Color(0xFF2196F3), size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tanggal Pembayaran',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              const SizedBox(height: 3),
              Text(
                DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(_paymentDate),
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827)),
              ),
            ]),
          ),
          if (isToday)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('Hari ini',
                  style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF2196F3),
                      fontWeight: FontWeight.w600)),
            )
          else
            const Icon(Icons.edit_calendar_rounded,
                color: Color(0xFF2196F3), size: 18),
        ]),
      ),
    );
  }

  // ── Method Tile ────────────────────────────────────────────────────────────

  Widget _methodTile(PaymentMethod method) {
    final isSelected = _selectedMethodKey == method.key;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedMethodKey = method.key;
        _selectedSubOption = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? method.color.withValues(alpha: 0.12)
              : Colors.grey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? method.color
                : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Icon(method.icon,
              color: isSelected ? method.color : Colors.grey, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(method.label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? method.color : Colors.black87),
                  overflow: TextOverflow.ellipsis)),
          if (isSelected)
            Icon(Icons.check_circle, color: method.color, size: 13),
        ]),
      ),
    );
  }

  Widget _infoBanner(
          {required String text,
          required Color color,
          required IconData icon}) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w500))),
        ]),
      );

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: color)),
      );

  Widget _buildCard(
          {required String title,
          required List<Widget> children,
          Widget? titleSuffix}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2))
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            if (titleSuffix != null) ...[
              const SizedBox(width: 8),
              titleSuffix,
            ],
          ]),
          const Divider(height: 20),
          ...children,
        ]),
      );

  Widget _infoRow(String label, String value, {bool isTotal = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
          Text(label,
              style: TextStyle(
                fontSize: isTotal ? 16 : 14,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                color: isTotal ? const Color(0xFF2196F3) : Colors.grey[700],
              )),
          Text(value,
              style: TextStyle(
                fontSize: isTotal ? 18 : 14,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
                color: isTotal ? const Color(0xFF2196F3) : Colors.black,
              )),
        ]),
      );

  // ── Process Payment ────────────────────────────────────────────────────────

  Future<void> _processPayment() async {
    if (!_isValid) return;
    setState(() => _isProcessing = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final fmt = NumberFormat.currency(
          locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

      final paidNow = _paidAmount;
      final kembalian = _kembalian;
      final sisa = _sisaHutang;
      final isLunas = sisa == 0 && paidNow > 0;
      final isBayarSebagian = sisa > 0 && paidNow > 0;
      final isBayarLebih = kembalian > 0;
      final isHutangPenuh = _isHutangPenuh;
      final dateTimestamp = Timestamp.fromDate(_paymentDate);

      List<Map<String, dynamic>>? paymentHistory;
      if (isBayarSebagian) {
        paymentHistory = [
          {
            'amount': paidNow,
            'date': dateTimestamp,
            'remaining': sisa,
            'paymentMethod': _selectedMethodKey,
            'paymentSubOption': _selectedSubOption,
          }
        ];
      }

      // Serialize cart items
      final itemsData = widget.cartItems
          .map((item) => {
                'productId': item.product.id,
                'productName': item.product.name,
                'category': item.product.category,
                'quantity': item.quantity,
                'hargaJual': item.hargaJual,
                'hargaBeli': item.hargaBeli,
                'subtotalJual': item.subtotalJual,
                'subtotalBeli': item.subtotalBeli,
                'customerNumber': item.customerNumber,
                'atasNama': item.atasNama,
                'nominal':
                    int.tryParse(item.nominal.replaceAll('.', '')) ?? 0,
                'adminFee':
                    int.tryParse(item.adminFee.replaceAll('.', '')) ??
                        item.product.adminFee,
              })
          .toList();

      final primaryItem = widget.cartItems.first;
      final isMultiItem = widget.cartItems.length > 1;

      final docData = <String, dynamic>{
        'userId': user?.uid,
        'userEmail': user?.email,

        // Multi-item fields
        'items': itemsData,
        'isMultiItem': isMultiItem,
        'totalItems': widget.cartItems.length,
        'totalQty': widget.cartItems.fold(0, (s, i) => s + i.quantity),

        // Primary item (backward compat)
        'productId': primaryItem.product.id,
        'productName': isMultiItem
            ? '${primaryItem.product.name} +${widget.cartItems.length - 1} lainnya'
            : primaryItem.product.name,
        'category': primaryItem.product.category,

        // Customer
        'customerNumber': widget.customerNumber,
        'customerName': widget.customerName,
        'atasNama': widget.atasNama,

        // Amounts
        'nominal': widget.cartItems.fold(0, (s, i) {
          final nom =
              int.tryParse(i.nominal.replaceAll('.', '')) ?? i.hargaJual;
          return s + nom * i.quantity;
        }),
        'adminFee': widget.cartItems.fold(
            0,
            (s, i) =>
                s +
                (int.tryParse(i.adminFee.replaceAll('.', '')) ??
                    i.product.adminFee) *
                    i.quantity),
        'totalAmount': _totalAmount,
        'hargaBeli': _totalBeli,
        'hargaJual': _totalAmount,

        // Payment
        'paymentMethod': isHutangPenuh ? null : _selectedMethodKey,
        'paymentSubOption': isHutangPenuh ? null : _selectedSubOption,
        'partialAmount':
            isBayarSebagian ? paidNow : (isLunas ? _totalAmount : null),
        'remainingDebt': isHutangPenuh ? _totalAmount : sisa,
        'isBayarSebagian': isBayarSebagian,
        'isPaid': isLunas || isBayarLebih,

        // ── Kembalian ──
        'kembalian': isBayarLebih ? kembalian : 0,
        'paidAmount': isBayarLebih ? paidNow : null,

        'date': dateTimestamp,
        if (isLunas || isBayarLebih) 'paidAt': dateTimestamp,
        if (isBayarSebagian) 'lastPaidAt': dateTimestamp,
        if (paymentHistory != null) 'paymentHistory': paymentHistory,
        'createdAt': FieldValue.serverTimestamp(),
        'syncStatus': 'synced',
      };

      final docRef = await FirebaseFirestore.instance
          .collection('transactions')
          .add(docData);

      final String logDesc;
      if (isHutangPenuh) {
        logDesc = isMultiItem
            ? '${widget.cartItems.length} produk — dicatat sebagai hutang penuh ${fmt.format(_totalAmount)}'
            : 'Transaksi ${primaryItem.product.name} — dicatat sebagai hutang penuh ${fmt.format(_totalAmount)}';
      } else if (isBayarSebagian) {
        logDesc = isMultiItem
            ? '${widget.cartItems.length} produk — bayar ${fmt.format(paidNow)}, sisa ${fmt.format(sisa)}'
            : 'Transaksi ${primaryItem.product.name} — bayar ${fmt.format(paidNow)}, sisa ${fmt.format(sisa)}';
      } else if (isBayarLebih) {
        logDesc = isMultiItem
            ? '${widget.cartItems.length} produk — LUNAS ${fmt.format(_totalAmount)}, kembalian ${fmt.format(kembalian)}'
            : 'Transaksi ${primaryItem.product.name} — LUNAS ${fmt.format(_totalAmount)}, kembalian ${fmt.format(kembalian)}';
      } else {
        logDesc = isMultiItem
            ? '${widget.cartItems.length} produk — LUNAS ${fmt.format(_totalAmount)}'
            : 'Transaksi ${primaryItem.product.name} — LUNAS ${fmt.format(_totalAmount)}';
      }

      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': 'create_transaction',
        'transactionId': docRef.id,
        'description': logDesc,
        'timestamp': FieldValue.serverTimestamp(),
      });

      final String methodDisplay;
      if (isHutangPenuh) {
        methodDisplay = 'Hutang (belum dibayar)';
      } else if (_selectedMethodKey == 'E-Wallet' &&
          _selectedSubOption != null) {
        methodDisplay = '${_currentMethodDef?.label} · $_selectedSubOption';
      } else {
        methodDisplay =
            _currentMethodDef?.label ?? _selectedMethodKey ?? '-';
      }

      // ── Build ReceiptItem list untuk printer ──
      final receiptItems = widget.cartItems
          .map((item) => ReceiptItem(
                productName: item.product.name,
                quantity: item.quantity,
                hargaJual: item.hargaJual,
                subtotal: item.subtotalJual,
                customerNumber: item.customerNumber,
                nominal:
                    int.tryParse(item.nominal.replaceAll('.', '')) ?? 0,
                adminFee:
                    int.tryParse(item.adminFee.replaceAll('.', '')) ??
                        item.product.adminFee,
                atasNama: item.atasNama,
                category: item.product.category,
              ))
          .toList();

      if (mounted) {
        Get.off(() => TransactionSuccessScreen(
              transactionId: docRef.id,
              productName: isMultiItem
                  ? '${primaryItem.product.name} +${widget.cartItems.length - 1} lainnya'
                  : primaryItem.product.name,
              customerNumber: widget.customerNumber,
              customerName: widget.customerName,
              atasNama: widget.atasNama,
              totalAmount: _totalAmount,
              nominal: receiptItems.isNotEmpty
                  ? receiptItems.first.nominal
                  : 0,
              adminFee: receiptItems.isNotEmpty
                  ? receiptItems.first.adminFee
                  : 0,
              paymentMethod: methodDisplay,
              isPaid: isLunas || isBayarLebih,
              isBayarSebagian: isBayarSebagian,
              partialAmount: isBayarSebagian ? paidNow : null,
              remainingDebt: isHutangPenuh ? _totalAmount : sisa,
              transactionDate: _paymentDate,
              category: primaryItem.product.category,
              items: receiptItems,
              kembalian: isBayarLebih ? kembalian : 0,
              paidAmount: isBayarLebih ? paidNow : null,
            ));
      }
    } catch (e) {
      if (mounted) {
        AppNotification.unexpectedError('Gagal memproses transaksi: $e');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}