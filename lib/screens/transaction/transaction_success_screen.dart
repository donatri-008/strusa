import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../home/main_screen.dart';
import '../../services/printer_service.dart';

class TransactionSuccessScreen extends StatelessWidget {
  final String transactionId;
  final String productName;
  final String customerNumber;
  final String customerName;
  final String atasNama;
  final int totalAmount;
  final int nominal;
  final int adminFee;
  final String paymentMethod;
  final bool isPaid;
  final String? token;
  final String? kwh;
  final bool isBayarSebagian;
  final int? partialAmount;
  final int remainingDebt;

  // ── FIX #1: nullable DateTime, tidak perlu _TodayPlaceholder lagi ──
  final DateTime? transactionDate;

  final String category;

  /// Kembalian jika pelanggan membayar lebih dari total tagihan
  final int kembalian;

  /// Jumlah yang benar-benar dibayarkan pelanggan (jika ada kembalian)
  final int? paidAmount;

  /// Daftar item untuk multi-produk. Kosong = single-item mode.
  final List<ReceiptItem> items;

  const TransactionSuccessScreen({
    super.key,
    required this.transactionId,
    required this.productName,
    required this.customerNumber,
    this.customerName = '',
    this.atasNama = '',
    required this.totalAmount,
    this.nominal = 0,
    this.adminFee = 0,
    required this.paymentMethod,
    required this.isPaid,
    this.token,
    this.kwh,
    this.isBayarSebagian = false,
    this.partialAmount,
    this.remainingDebt = 0,
    // ── FIX #1: nullable, tidak ada default const yang berbahaya ──
    this.transactionDate,
    this.category = '',
    this.items = const [],
    this.kembalian = 0,
    this.paidAmount,
  });

  // ── FIX #1: getter aman — null → DateTime.now() ──
  DateTime get _resolvedDate => transactionDate ?? DateTime.now();

  bool get _isMultiItem => items.length > 1;

  /// Ada kembalian (bayar lebih)
  bool get _hasKembalian => kembalian > 0;

  bool get _isHutangPenuh => !isPaid && !isBayarSebagian;

  bool get _shouldHidePaymentMethod =>
      _isHutangPenuh || paymentMethod == 'Hutang';

  // ── Category helpers ──────────────────────────────────────────────────────

  bool _hidesAdminFee(String cat) =>
      cat == 'Pulsa' ||
      cat == 'Paket Data' ||
      cat == 'Token Listrik' ||
      cat == 'Lainnya';

  bool _hidesAtasNama(String cat) =>
      cat == 'Pulsa' ||
      cat == 'Paket Data' ||
      cat == 'E-Wallet' ||
      cat == 'Jasa Transfer' ||
      cat == 'Lainnya';

  bool _hasNominalFee(String cat) =>
      cat == 'Tagihan' || cat == 'E-Wallet' || cat == 'Jasa Transfer';

  bool get _hasAdminFee => !_hidesAdminFee(category);
  bool get _hasAtasNama => !_hidesAtasNama(category);

  void _showReceiptPreview(BuildContext context) {
    final String receiptPaymentMethod =
        _shouldHidePaymentMethod ? '' : paymentMethod;

    PrinterService().showReceiptPreview(
      context,
      ReceiptData(
        transactionId: transactionId,
        productName: productName,
        customerNumber: customerNumber,
        customerName: customerName,
        atasNama: atasNama,
        totalAmount: totalAmount,
        nominal: items.isNotEmpty ? items.first.nominal : nominal,
        adminFee: items.isNotEmpty ? items.first.adminFee : adminFee,
        paymentMethod: receiptPaymentMethod,
        isPaid: isPaid,
        isBayarSebagian: isBayarSebagian,
        partialAmount: partialAmount,
        remainingDebt: remainingDebt,
        transactionDate: _resolvedDate,
        token: token,
        kwh: kwh,
        category: items.isNotEmpty ? items.first.category : category,
        items: items,
        kembalian: kembalian,
        paidAmount: paidAmount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    // ── Warna & label status ──────────────────────────────────────────────
    final Color statusColor = isBayarSebagian
        ? const Color(0xFFF44336)
        : _hasKembalian
            ? const Color(0xFF00BCD4)
            : isPaid
                ? const Color(0xFF4CAF50)
                : const Color(0xFFFF9800);

    final String statusLabel = isBayarSebagian
        ? 'Bayar Sebagian (Ada Hutang)'
        : _hasKembalian
            ? 'Lunas'
            : isPaid
                ? 'Lunas'
                : 'Hutang';

    final IconData statusIcon = isBayarSebagian
        ? Icons.money_off_rounded
        : _hasKembalian
            ? Icons.currency_exchange_rounded
            : isPaid
                ? Icons.check_circle_rounded
                : Icons.pending_rounded;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const SizedBox(height: 24),

                // ── Icon Status ───────────────────────────────────────────
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.4), width: 2),
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 52),
                ),

                const SizedBox(height: 20),

                const Text('Transaksi Berhasil!',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF212121))),

                const SizedBox(height: 6),

                // Status chip
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(statusIcon, color: statusColor, size: 15),
                    const SizedBox(width: 6),
                    Text(statusLabel,
                        style: TextStyle(
                            fontSize: 13,
                            color: statusColor,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),

                // ── Banner kembalian menonjol ─────────────────────────────
                if (_hasKembalian) ...[
                  const SizedBox(height: 16),
                  _kembalianBanner(fmt),
                ],

                const SizedBox(height: 20),

                // ── Tanggal Transaksi ──────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF2196F3).withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.calendar_today_rounded,
                          color: Color(0xFF2196F3), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Tanggal Transaksi',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF2196F3))),
                          const SizedBox(height: 3),
                          Text(
                            DateFormat('EEEE, dd MMMM yyyy', 'id_ID')
                                .format(_resolvedDate),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827)),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 16),

                // ── Kartu Ringkasan ────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Total Tagihan ──────────────────────────────────
                      Center(
                        child: Column(children: [
                          Text('Total Tagihan',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[600])),
                          const SizedBox(height: 6),
                          Text(fmt.format(totalAmount),
                              style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2196F3))),
                        ]),
                      ),

                      // ── Rincian Bayar Sebagian ─────────────────────────
                      if (isBayarSebagian && partialAmount != null) ...[
                        const SizedBox(height: 12),
                        _rincianBayarSebagian(fmt),
                      ],

                      // ── Rincian Kembalian ──────────────────────────────
                      if (_hasKembalian) ...[
                        const SizedBox(height: 12),
                        _rincianKembalian(fmt),
                      ],

                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),

                      // ── Info Pelanggan ─────────────────────────────────
                      if (customerName.isNotEmpty)
                        _infoRow('Nama Pelanggan', customerName),
                      if (customerNumber.isNotEmpty)
                        _infoRow('No. Pelanggan', customerNumber),

                      const SizedBox(height: 4),

                      // ══════════════════════════════════════════════════
                      // MODE A — Multi-item
                      // ══════════════════════════════════════════════════
                      if (_isMultiItem) ...[
                        const Divider(),
                        const SizedBox(height: 4),
                        Row(children: [
                          Container(
                            width: 4,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2196F3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${items.length} Produk',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2196F3))),
                        ]),
                        const SizedBox(height: 10),
                        ...items.asMap().entries.map((entry) =>
                            _buildMultiItemRow(entry.key, entry.value, fmt)),
                        const SizedBox(height: 4),
                      ]
                      // ══════════════════════════════════════════════════
                      // MODE B — Single-item
                      // ══════════════════════════════════════════════════
                      else ...[
                        _infoRow('Produk', productName),

                        if (customerNumber.isEmpty &&
                            items.isNotEmpty &&
                            items.first.customerNumber.isNotEmpty)
                          _infoRow('No. Pelanggan',
                              items.first.customerNumber),

                        if (items.isNotEmpty &&
                            items.first.showAtasNama)
                          _infoRow('Atas Nama', items.first.atasNama)
                        else if (items.isEmpty &&
                            atasNama.trim().isNotEmpty &&
                            _hasAtasNama)
                          _infoRow('Atas Nama', atasNama.trim()),

                        if (items.isNotEmpty &&
                            items.first.hasNominalFee &&
                            items.first.nominal > 0)
                          _infoRow('Nominal',
                              fmt.format(items.first.nominal))
                        else if (items.isEmpty &&
                            nominal > 0 &&
                            _hasNominalFee(category))
                          _infoRow('Nominal', fmt.format(nominal)),

                        if (items.isNotEmpty &&
                            items.first.showAdminFee)
                          _infoRow('Biaya Admin',
                              fmt.format(items.first.adminFee))
                        else if (items.isEmpty &&
                            adminFee > 0 &&
                            _hasAdminFee)
                          _infoRow('Biaya Admin', fmt.format(adminFee)),

                        if (token != null && token!.isNotEmpty)
                          _infoRow('Token', token!),
                        if (kwh != null && kwh!.isNotEmpty)
                          _infoRow('KWH', kwh!),
                      ],

                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),

                      // ── Info Transaksi ─────────────────────────────────
                      _infoRow('ID Transaksi',
                          '#${transactionId.substring(0, 10).toUpperCase()}'),

                      if (!_shouldHidePaymentMethod &&
                          paymentMethod.isNotEmpty)
                        _infoRow('Metode Bayar', paymentMethod),

                      _infoRowColored('Status', statusLabel, statusColor),
                    ],
                  ),
                ),

                // ── Banner Hutang ──────────────────────────────────────────
                if (!isPaid || isBayarSebagian) ...[
                  const SizedBox(height: 16),
                  _hutangBanner(fmt, statusColor),
                ],
              ]),
            ),
          ),

          // ── Tombol Aksi ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
            child: Column(children: [
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => _showReceiptPreview(context),
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('Lihat & Cetak Struk'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => Get.offAll(() => const MainScreen()),
                  icon: const Icon(Icons.home_rounded,
                      color: Color(0xFF2196F3)),
                  label: const Text('Kembali ke Beranda'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2196F3)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Banner kembalian besar & mencolok ─────────────────────────────────────

  Widget _kembalianBanner(NumberFormat fmt) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00BCD4), Color(0xFF0097A7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00BCD4).withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: [
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.currency_exchange_rounded,
              color: Colors.white, size: 20),
          SizedBox(width: 8),
          Text('KEMBALIAN',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1.2)),
        ]),
        const SizedBox(height: 8),
        Text(
          fmt.format(kembalian),
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
        if (paidAmount != null) ...[
          const SizedBox(height: 4),
          Text(
            'Dibayar ${fmt.format(paidAmount)} · Tagihan ${fmt.format(totalAmount)}',
            style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ]),
    );
  }

  // ── Multi-item row ──────────────────────────────────────────────────────────

  Widget _buildMultiItemRow(int index, ReceiptItem item, NumberFormat fmt) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFF2196F3).withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1, right: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text('${index + 1}',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2196F3))),
              ),
            ),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(item.productName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
                if (item.category.isNotEmpty)
                  Text(item.category,
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[500])),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (item.quantity > 1)
                Text('${fmt.format(item.hargaJual)} ×${item.quantity}',
                    style: TextStyle(fontSize: 10, color: Colors.grey[400])),
              Text(fmt.format(item.subtotal),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827))),
            ]),
          ]),

          if (item.customerNumber.isNotEmpty) ...[
            const SizedBox(height: 4),
            _itemDetailRow(
                icon: Icons.tag_rounded,
                label: 'No. Pelanggan',
                value: item.customerNumber),
          ],
          if (item.showAtasNama) ...[
            const SizedBox(height: 2),
            _itemDetailRow(
                icon: Icons.badge_outlined,
                label: 'Atas Nama',
                value: item.atasNama),
          ],
          if (item.hasNominalFee && item.nominal > 0) ...[
            const SizedBox(height: 2),
            _itemDetailRow(
                icon: Icons.payments_outlined,
                label: 'Nominal',
                value: fmt.format(item.nominal)),
          ],
          if (item.showAdminFee) ...[
            const SizedBox(height: 2),
            _itemDetailRow(
                icon: Icons.receipt_long_outlined,
                label: 'Biaya Admin',
                value: fmt.format(item.adminFee)),
          ],
        ],
      ),
    );
  }

  Widget _itemDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 32),
      child: Row(children: [
        Icon(icon, size: 12, color: Colors.grey[400]),
        const SizedBox(width: 4),
        Text('$label: ',
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151)),
              textAlign: TextAlign.end),
        ),
      ]),
    );
  }

  // ── Widget Helpers ─────────────────────────────────────────────────────────

  Widget _rincianBayarSebagian(NumberFormat fmt) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF44336).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFFF44336).withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        _splitRow('Dibayar sekarang', fmt.format(partialAmount),
            const Color(0xFF4CAF50)),
        const SizedBox(height: 6),
        _splitRow(
            'Sisa hutang', fmt.format(remainingDebt), const Color(0xFFF44336)),
      ]),
    );
  }

  Widget _rincianKembalian(NumberFormat fmt) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF00BCD4).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFF00BCD4).withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        if (paidAmount != null)
          _splitRow('Uang diterima', fmt.format(paidAmount),
              const Color(0xFF2196F3)),
        if (paidAmount != null) const SizedBox(height: 6),
        _splitRow('Total tagihan', fmt.format(totalAmount), Colors.grey),
        const SizedBox(height: 6),
        _splitRow('Kembalian', fmt.format(kembalian),
            const Color(0xFF00BCD4)),
      ]),
    );
  }

  Widget _splitRow(String label, String value, Color color) => Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.w500)),
          ),
          Text(value,
              style: TextStyle(
                  fontSize: 13, color: color, fontWeight: FontWeight.bold)),
        ],
      );

  Widget _hutangBanner(NumberFormat fmt, Color color) {
    final msg = isBayarSebagian && remainingDebt > 0
        ? 'Sisa hutang sebesar ${fmt.format(remainingDebt)} perlu dilunasi kemudian.'
        : 'Seluruh tagihan ${fmt.format(totalAmount)} dicatat sebagai hutang.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(msg,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 6,
              child: Text(
                value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
                textAlign: TextAlign.end,
                softWrap: true,
              ),
            ),
          ],
        ),
      );

  Widget _infoRowColored(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 4,
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Text(value,
                  style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
}