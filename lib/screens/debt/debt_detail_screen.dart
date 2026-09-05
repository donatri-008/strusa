import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:open_settings_plus/open_settings_plus.dart';
import '../../services/printer_service.dart';
import '../../utils/app_notification.dart';

const _blue = Color(0xFF2196F3);
const _blueDk = Color(0xFF1976D2);
const _blueXlt = Color(0xFFE3F2FD);
const _red = Color(0xFFEF4444);
const _green = Color(0xFF22C55E);
const _orange = Color(0xFFFF9800);
const _purple = Color(0xFF7C3AED);
const _ink = Color(0xFF111827);
const _inkMid = Color(0xFF374151);
const _inkLt = Color(0xFF9CA3AF);
const _surf = Color(0xFFF3F4F6);
const _bdr = Color(0xFFE5E7EB);

class _ThousandSepFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll('.', '');
    if (digits.isEmpty) return newValue.copyWith(text: '');
    final n = int.tryParse(digits) ?? 0;
    final formatted =
        NumberFormat('#,##0', 'id_ID').format(n).replaceAll(',', '.');
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

String _rawDigits(String formatted) => formatted.replaceAll('.', '');

class _PayMethod {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  final List<String>? subOptions;
  const _PayMethod({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
    this.subOptions,
  });
}

const _debtPayMethods = [
  _PayMethod(
      key: 'transfer_bank',
      label: 'Transfer Bank',
      icon: Icons.account_balance,
      color: _blue),
  _PayMethod(
      key: 'qris',
      label: 'QRIS',
      icon: Icons.qr_code_2,
      color: Color(0xFF9C27B0)),
  _PayMethod(
      key: 'tunai',
      label: 'Tunai',
      icon: Icons.payments,
      color: _green),
  _PayMethod(
      key: 'E-Wallet',
      label: 'E-Wallet',
      icon: Icons.wallet,
      color: Color(0xFFFF9800),
      subOptions: ['OVO', 'GoPay', 'Dana', 'ShopeePay', 'LinkAja']),
];

double _effectiveDebt(Map<String, dynamic> data) {
  if (data['isBayarSebagian'] == true) {
    return (data['remainingDebt'] ?? 0).toDouble();
  }
  return (data['totalAmount'] ?? 0).toDouble();
}

String _methodLabel(String key, String? sub) {
  final matches = _debtPayMethods.where((m) => m.key == key);
  final def = matches.isEmpty ? null : matches.first;
  if (def == null) return key;
  if (def.key == 'E-Wallet' && sub != null && sub.isNotEmpty) {
    return '${def.label} · $sub';
  }
  return def.label;
}

IconData _methodIcon(String key) {
  final matches = _debtPayMethods.where((m) => m.key == key);
  return matches.isEmpty ? Icons.payment : matches.first.icon;
}

Color _methodColor(String key) {
  final matches = _debtPayMethods.where((m) => m.key == key);
  return matches.isEmpty ? Colors.grey : matches.first.color;
}

class DebtDetailScreen extends StatefulWidget {
  final String customerName;
  final List<String> allNumbers;
  final List<QueryDocumentSnapshot> transactions;

  const DebtDetailScreen({
    super.key,
    required this.customerName,
    required this.allNumbers,
    required this.transactions,
  });

  @override
  State<DebtDetailScreen> createState() => _DebtDetailScreenState();
}

class _DebtDetailScreenState extends State<DebtDetailScreen>
    with TickerProviderStateMixin {
  bool _isUpdating = false;
  final Set<String> _selected = {};
  List<QueryDocumentSnapshot>? _cachedDocs;

  late final AnimationController _headerCtrl;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _headerFade =
        CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _headerSlide =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
            .animate(CurvedAnimation(
                parent: _headerCtrl, curve: Curves.easeOut));
    _headerCtrl.forward();
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> get _txStream {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final base = FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: uid)
        .where('isPaid', isEqualTo: false);

    if (widget.customerName.isNotEmpty) {
      return base
          .where('customerName', isEqualTo: widget.customerName)
          .orderBy('date', descending: false)
          .snapshots();
    } else if (widget.allNumbers.isNotEmpty) {
      return base
          .where('customerNumber',
              whereIn: widget.allNumbers.take(30).toList())
          .orderBy('date', descending: false)
          .snapshots();
    } else {
      return const Stream.empty();
    }
  }

  String get _displayNumber {
    if (widget.allNumbers.isEmpty) return '-';
    if (widget.allNumbers.length == 1) return widget.allNumbers.first;
    return '${widget.allNumbers.length} nomor berbeda';
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: StreamBuilder<QuerySnapshot>(
        stream: _txStream,
        builder: (ctx, snap) {
          if (snap.hasData) _cachedDocs = snap.data!.docs;
          final isLoading =
              snap.connectionState == ConnectionState.waiting &&
                  _cachedDocs == null;
          final docs = _cachedDocs ?? [];

          if (_cachedDocs != null) {
            final liveIds = docs.map((d) => d.id).toSet();
            _selected.removeWhere((id) => !liveIds.contains(id));
          }

          final totalDebt = docs.fold<double>(
              0,
              (s, d) =>
                  s + _effectiveDebt(d.data() as Map<String, dynamic>));
          final selectedDebt = docs
              .where((d) => _selected.contains(d.id))
              .fold<double>(
                  0,
                  (s, d) => s +
                      _effectiveDebt(d.data() as Map<String, dynamic>));
          final sebagianCount = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            return data['isBayarSebagian'] == true;
          }).length;
          final allSelected =
              docs.isNotEmpty && _selected.length == docs.length;

          if (isLoading) {
            return Scaffold(
              backgroundColor: _surf,
              body: Column(children: [
                _buildHeader(fmt, [], 0, 0, false),
                const Expanded(
                  child: Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                              color: _blue, strokeWidth: 2.5),
                          SizedBox(height: 16),
                          Text('Memuat data piutang...',
                              style: TextStyle(
                                  fontSize: 13, color: _inkLt)),
                        ]),
                  ),
                ),
              ]),
            );
          }

          return Scaffold(
            backgroundColor: _surf,
            body: Column(children: [
              _buildHeader(
                  fmt, docs, totalDebt, sebagianCount, allSelected),
              Expanded(
                child: docs.isEmpty
                    ? _allPaidState()
                    : ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(16, 16, 16, 140),
                        itemCount: docs.length,
                        itemBuilder: (ctx, i) =>
                            _buildCard(ctx, i, docs[i], fmt),
                      ),
              ),
            ]),
            bottomNavigationBar: AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              child: _selected.isEmpty
                  ? const SizedBox.shrink()
                  : _buildActionBar(fmt, selectedDebt),
            ),
          );
        },
      ),
    );
  }

  Widget _allPaidState() {
    return Center(
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.1),
                  shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_outline_rounded,
                  size: 56, color: _green),
            ),
            const SizedBox(height: 20),
            const Text('Semua Lunas!',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _ink)),
            const SizedBox(height: 8),
            const Text('Tidak ada piutang yang tersisa',
                style: TextStyle(fontSize: 13, color: _inkLt)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Get.back(result: true),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Kembali'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _blue,
                side: const BorderSide(color: _blue),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ]),
    );
  }

  Widget _buildHeader(
      NumberFormat fmt,
      List<QueryDocumentSnapshot> docs,
      double totalDebt,
      int sebagianCount,
      bool allSelected) {
    final name = widget.customerName.isNotEmpty
        ? widget.customerName
        : _displayNumber;
    final initials = name
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [_blue, _blueDk],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Text('Detail Piutang',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 19),
                      onPressed: () => Get.back(),
                    ),
                    if (_cachedDocs != null && docs.isNotEmpty)
                      Tooltip(
                        message:
                            allSelected ? 'Batal Semua' : 'Pilih Semua',
                        child: IconButton(
                          onPressed: () => setState(() {
                            if (allSelected) {
                              _selected.clear();
                            } else {
                              _selected.clear();
                              _selected.addAll(docs.map((d) => d.id));
                            }
                          }),
                          icon: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              allSelected
                                  ? Icons.deselect_rounded
                                  : Icons.select_all_rounded,
                              key: ValueKey(allSelected),
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),
              ],
            ),
          ),
          FadeTransition(
            opacity: _headerFade,
            child: SlideTransition(
              position: _headerSlide,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1.5),
                    ),
                    child: Center(
                      child: Text(initials,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.customerName.isNotEmpty
                                ? widget.customerName
                                : 'Pelanggan',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(_displayNumber,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ]),
                  ),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(fmt.format(totalDebt),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        Wrap(spacing: 6, children: [
                          _miniPill(
                              '${docs.length} transaksi',
                              Colors.white.withValues(alpha: 0.25),
                              Colors.white),
                          if (sebagianCount > 0)
                            _miniPill(
                                '$sebagianCount sebagian',
                                _red.withValues(alpha: 0.3),
                                Colors.white),
                        ]),
                      ]),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildCard(BuildContext ctx, int index,
      QueryDocumentSnapshot doc, NumberFormat fmt) {
    final data =
        (doc.data() ?? <String, dynamic>{}) as Map<String, dynamic>;
    final isSelected = _selected.contains(doc.id);
    final isSebagian = data['isBayarSebagian'] == true;
    final effectiveDebt = _effectiveDebt(data);
    final totalAmt = (data['totalAmount'] ?? 0).toDouble();
    final partialAmt = (data['partialAmount'] ?? 0).toDouble();
    final progress =
        isSebagian && totalAmt > 0 ? (partialAmt / totalAmt) : 0.0;
    final date = (data['date'] as Timestamp).toDate();
    final lastPaidAt = data['lastPaidAt'] != null
        ? (data['lastPaidAt'] as Timestamp).toDate()
        : null;
    final txNumber = (data['customerNumber'] ?? '').toString().trim();
    final paymentHistory =
        List<Map<String, dynamic>>.from(data['paymentHistory'] ?? []);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + index * 55),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
            offset: Offset(0, 12 * (1 - v)), child: child),
      ),
      child: GestureDetector(
        onTap: () => setState(() => isSelected
            ? _selected.remove(doc.id)
            : _selected.add(doc.id)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isSelected ? _blue : _bdr,
                width: isSelected ? 2 : 1),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? _blue.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.04),
                blurRadius: isSelected ? 14 : 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 22,
                          height: 22,
                          margin: const EdgeInsets.only(top: 1, right: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _blue
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: isSelected ? _blue : _bdr,
                                width: 2),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 14)
                              : null,
                        ),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          data['productName'] ?? 'Produk',
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: _ink,
                                              height: 1.3),
                                        ),
                                      ),
                                      if (isSebagian) ...[
                                        const SizedBox(width: 8),
                                        _pill('Sebagian', _red,
                                            Icons.money_off_rounded),
                                      ],
                                    ]),
                                const SizedBox(height: 6),
                                Wrap(
                                    spacing: 10,
                                    runSpacing: 4,
                                    children: [
                                      _metaChip(
                                          Icons.schedule_outlined,
                                          'Transaksi: ${DateFormat('dd MMM yy', 'id_ID').format(date)}'),
                                      if ((data['category'] ?? '')
                                          .isNotEmpty)
                                        _metaChip(Icons.widgets_outlined,
                                            data['category']),
                                      if (widget.allNumbers.length > 1 &&
                                          txNumber.isNotEmpty)
                                        _metaChip(Icons.numbers_rounded,
                                            txNumber),
                                    ]),
                                if (isSebagian) ...[
                                  const SizedBox(height: 6),
                                  GestureDetector(
                                    onTap: () =>
                                        _pickLastPaidAt(doc, lastPaidAt),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: lastPaidAt != null
                                            ? _green.withValues(alpha: 0.08)
                                            : Colors.grey
                                                .withValues(alpha: 0.07),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        border: Border.all(
                                            color: lastPaidAt != null
                                                ? _green.withValues(
                                                    alpha: 0.3)
                                                : _bdr),
                                      ),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.payments_rounded,
                                                size: 12,
                                                color: lastPaidAt != null
                                                    ? _green
                                                    : _inkLt),
                                            const SizedBox(width: 5),
                                            Text(
                                              lastPaidAt != null
                                                  ? 'Bayar terakhir: ${DateFormat('dd MMM yyyy', 'id_ID').format(lastPaidAt)}'
                                                  : 'Belum ada pembayaran',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: lastPaidAt != null
                                                      ? _green
                                                      : _inkLt,
                                                  fontWeight:
                                                      FontWeight.w500),
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(
                                                Icons
                                                    .edit_calendar_rounded,
                                                size: 11,
                                                color: lastPaidAt != null
                                                    ? _green
                                                    : _inkLt),
                                          ]),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                if (isSebagian) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: progress.clamp(0.0, 1.0),
                                      minHeight: 7,
                                      backgroundColor:
                                          _red.withValues(alpha: 0.12),
                                      valueColor:
                                          const AlwaysStoppedAnimation(
                                              _green),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                            '${(progress * 100).toStringAsFixed(0)}% terbayar',
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: _green,
                                                fontWeight:
                                                    FontWeight.w500)),
                                        Text(
                                            'sisa ${(100 - progress * 100).toStringAsFixed(0)}%',
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: _inkLt)),
                                      ]),
                                  const SizedBox(height: 12),
                                  IntrinsicHeight(
                                    child: Row(children: [
                                      _amountCol('Total',
                                          fmt.format(totalAmt), _inkMid),
                                      _vDivider(),
                                      _amountCol('Dibayar',
                                          fmt.format(partialAmt), _green),
                                      _vDivider(),
                                      _amountCol(
                                          'Sisa Hutang',
                                          fmt.format(effectiveDebt),
                                          _red,
                                          bold: true),
                                    ]),
                                  ),
                                  if (paymentHistory.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    _buildPaymentHistorySection(
                                        doc,
                                        paymentHistory,
                                        fmt,
                                        totalAmt),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Expanded(
                                        child: _bayarSebagianButton(
                                            doc, fmt,
                                            label: 'Bayar Lagi')),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: _lunasiButton(doc, fmt)),
                                  ]),
                                ] else ...[
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Total Hutang',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: _inkLt)),
                                        Text(
                                          fmt.format(effectiveDebt),
                                          style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold,
                                              color: _blue),
                                        ),
                                      ]),
                                  const SizedBox(height: 12),
                                  _bayarSebagianButton(doc, fmt,
                                      label: 'Bayar Sebagian'),
                                ],
                              ]),
                        ),
                      ]),
                ),
                if (isSelected)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _blue.withValues(alpha: 0.07),
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(14)),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: _blue, size: 13),
                          const SizedBox(width: 6),
                          Text('Dipilih · ${fmt.format(effectiveDebt)}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: _blue,
                                  fontWeight: FontWeight.w600)),
                        ]),
                  ),
              ]),
        ),
      ),
    );
  }

  Widget _buildPaymentHistorySection(
    QueryDocumentSnapshot doc,
    List<Map<String, dynamic>> history,
    NumberFormat fmt,
    double totalAmt,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surf,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _bdr),
      ),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.history_rounded, size: 13, color: _inkLt),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Riwayat Bayar',
                    style: TextStyle(
                        fontSize: 11,
                        color: _inkLt,
                        fontWeight: FontWeight.w600)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: _blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: Text('${history.length} bayar',
                    style: const TextStyle(
                        fontSize: 10,
                        color: _blue,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 10),
            ...history
                .asMap()
                .entries
                .toList()
                .reversed
                .take(3)
                .map((entry) {
              final idx = entry.key;
              final hist = entry.value;
              final histDate = (hist['date'] as Timestamp).toDate();
              final histPayMethod =
                  hist['paymentMethod'] as String? ?? '';
              final histPaySub =
                  hist['paymentSubOption'] as String?;
              final isPelunasan = hist['isPelunasan'] == true;
              final amount = (hist['amount'] ?? 0) as num;
              final remaining = (hist['remaining'] ?? 0) as num;
              final color = _methodColor(histPayMethod);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: isPelunasan ? _blue : _green,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: (isPelunasan ? _blue : _green)
                                .withValues(alpha: 0.3),
                            width: 2)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(
                                DateFormat('dd MMM yyyy', 'id_ID')
                                    .format(histDate),
                                style: const TextStyle(
                                    fontSize: 11, color: _inkMid)),
                            if (histPayMethod.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Icon(_methodIcon(histPayMethod),
                                  size: 10, color: color),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(
                                  _methodLabel(
                                      histPayMethod, histPaySub),
                                  style: TextStyle(
                                      fontSize: 10, color: color),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ]),
                          if (remaining > 0)
                            Text('Sisa: ${fmt.format(remaining)}',
                                style: const TextStyle(
                                    fontSize: 10, color: _inkLt)),
                        ]),
                  ),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(fmt.format(amount),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isPelunasan ? _blue : _green)),
                        if (isPelunasan)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: _blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Pelunasan',
                                style: TextStyle(
                                    fontSize: 9,
                                    color: _blue,
                                    fontWeight: FontWeight.w600)),
                          ),
                      ]),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _showEditHistoryEntrySheet(
                        doc, idx, history, totalAmt),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: _blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.edit_rounded,
                          size: 12, color: _blue),
                    ),
                  ),
                ]),
              );
            }),
            if (history.length > 3) ...[
              const SizedBox(height: 2),
              Text('+ ${history.length - 3} pembayaran sebelumnya',
                  style: const TextStyle(
                      fontSize: 10,
                      color: _inkLt,
                      fontStyle: FontStyle.italic)),
            ],
          ]),
    );
  }

  void _showEditHistoryEntrySheet(
    QueryDocumentSnapshot doc,
    int historyIndex,
    List<Map<String, dynamic>> currentHistory,
    double totalAmt,
  ) {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final entry =
        Map<String, dynamic>.from(currentHistory[historyIndex]);

    final amountCtrl = TextEditingController(
        text: NumberFormat('#,##0', 'id_ID')
            .format((entry['amount'] as num?)?.toInt() ?? 0)
            .replaceAll(',', '.'));

    final rawDate = entry['date'];
    DateTime selectedDate =
        rawDate is Timestamp ? rawDate.toDate() : DateTime.now();
    String? selectedPayMethod =
        entry['paymentMethod'] as String?;
    String? selectedPaySubOption =
        entry['paymentSubOption'] as String?;
    bool isLoading = false;

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
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24))),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                        child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                                color: _bdr,
                                borderRadius:
                                    BorderRadius.circular(2)))),
                    const SizedBox(height: 20),
                    Row(children: [
                      Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: _blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.edit_rounded,
                              color: _blue, size: 22)),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                            Text(
                                'Edit Pembayaran #${historyIndex + 1}',
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: _ink)),
                            const Text(
                                'Ubah jumlah, metode, atau tanggal',
                                style: TextStyle(
                                    fontSize: 12, color: _inkLt)),
                          ])),
                    ]),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_ThousandSepFormatter()],
                      onChanged: (_) => setSheet(() {}),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Jumlah Dibayar',
                        prefixText: 'Rp ',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: _blue, width: 2)),
                        errorText: () {
                          if (amountCtrl.text.isEmpty) return null;
                          final v = int.tryParse(
                                  _rawDigits(amountCtrl.text)) ??
                              0;
                          if (v <= 0) return 'Masukkan jumlah valid';
                          final otherPaid = currentHistory
                              .asMap()
                              .entries
                              .where((e) => e.key != historyIndex)
                              .fold<int>(
                                  0,
                                  (s, e) =>
                                      s +
                                      ((e.value['amount'] as num?)
                                              ?.toInt() ??
                                          0));
                          if (otherPaid + v > totalAmt.toInt()) {
                            return 'Total melebihi tagihan (${fmt.format(totalAmt)})';
                          }
                          return null;
                        }(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildPaymentMethodSelector(
                      selectedKey: selectedPayMethod,
                      selectedSubOption: selectedPaySubOption,
                      onChanged: (key, sub) => setSheet(() {
                        selectedPayMethod = key;
                        selectedPaySubOption = sub;
                      }),
                    ),
                    const SizedBox(height: 16),
                    const Text('Tanggal Pembayaran',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _inkMid)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        FocusScope.of(sheetCtx).unfocus();
                        await Future.delayed(
                            const Duration(milliseconds: 100));
                        if (!sheetCtx.mounted) return;
                        final picked = await showDatePicker(
                            context: sheetRootCtx,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            helpText: 'Tanggal Pembayaran',
                            builder: (ctx, child) => Theme(
                                data: Theme.of(ctx).copyWith(
                                    colorScheme:
                                        const ColorScheme.light(
                                            primary: _blue)),
                                child: child!));
                        if (picked != null) {
                          setSheet(() => selectedDate = picked);
                        }
                      },
                      child:
                          _buildDatePickerRow(selectedDate, _blue),
                    ),
                    const SizedBox(height: 16),
                    Builder(builder: (_) {
                      final newAmount =
                          int.tryParse(_rawDigits(amountCtrl.text)) ??
                              0;
                      if (newAmount <= 0) return const SizedBox.shrink();
                      final otherPaid = currentHistory
                          .asMap()
                          .entries
                          .where((e) => e.key != historyIndex)
                          .fold<int>(
                              0,
                              (s, e) =>
                                  s +
                                  ((e.value['amount'] as num?)
                                          ?.toInt() ??
                                      0));
                      final newTotal = otherPaid + newAmount;
                      final newRemaining =
                          totalAmt.toInt() - newTotal;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: _blue.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    _blue.withValues(alpha: 0.2))),
                        child: Column(children: [
                          Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total terbayar',
                                    style: TextStyle(
                                        fontSize: 12, color: _inkMid)),
                                Text(fmt.format(newTotal),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: _green)),
                              ]),
                          const SizedBox(height: 6),
                          Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Sisa hutang',
                                    style: TextStyle(
                                        fontSize: 12, color: _inkMid)),
                                Text(
                                    fmt.format(newRemaining < 0
                                        ? 0
                                        : newRemaining),
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: newRemaining <= 0
                                            ? _green
                                            : const Color(
                                                0xFFFF9800))),
                              ]),
                          if (newRemaining <= 0) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: _green.withValues(alpha: 0.1),
                                  borderRadius:
                                      BorderRadius.circular(6)),
                              child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_outline,
                                        size: 12, color: _green),
                                    SizedBox(width: 4),
                                    Text('Status akan menjadi LUNAS',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: _green,
                                            fontWeight:
                                                FontWeight.w600)),
                                  ]),
                            ),
                          ],
                        ]),
                      );
                    }),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed:
                            (isLoading || selectedPayMethod == null)
                                ? null
                                : () async {
                                    final newAmount = int.tryParse(
                                            _rawDigits(
                                                amountCtrl.text)) ??
                                        0;
                                    if (newAmount <= 0) return;
                                    final otherPaid = currentHistory
                                        .asMap()
                                        .entries
                                        .where(
                                            (e) => e.key != historyIndex)
                                        .fold<int>(
                                            0,
                                            (s, e) =>
                                                s +
                                                ((e.value['amount']
                                                            as num?)
                                                        ?.toInt() ??
                                                    0));
                                    if (otherPaid + newAmount >
                                        totalAmt.toInt()) {
                                      return;
                                    }
                                    setSheet(() => isLoading = true);
                                    Navigator.pop(sheetCtx);
                                    await _saveEditedHistoryEntry(
                                      doc: doc,
                                      index: historyIndex,
                                      currentHistory: currentHistory,
                                      totalAmt: totalAmt,
                                      newAmount: newAmount,
                                      newDate: selectedDate,
                                      newMethod: selectedPayMethod!,
                                      newSubOption: selectedPaySubOption,
                                    );
                                  },
                        style: ElevatedButton.styleFrom(
                            backgroundColor:
                                selectedPayMethod == null
                                    ? Colors.grey
                                    : _blue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(14))),
                        child: Text(
                            selectedPayMethod == null
                                ? 'Pilih metode pembayaran dulu'
                                : 'Simpan Perubahan',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveEditedHistoryEntry({
    required QueryDocumentSnapshot doc,
    required int index,
    required List<Map<String, dynamic>> currentHistory,
    required double totalAmt,
    required int newAmount,
    required DateTime newDate,
    required String newMethod,
    required String? newSubOption,
  }) async {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final updatedHistory =
          List<Map<String, dynamic>>.from(currentHistory);
      final oldEntry = updatedHistory[index];

      updatedHistory[index] = {
        ...oldEntry,
        'amount': newAmount,
        'date': Timestamp.fromDate(newDate),
        'paymentMethod': newMethod,
        'paymentSubOption': newSubOption,
      };

      int runningPaid = 0;
      for (int i = 0; i < updatedHistory.length; i++) {
        runningPaid +=
            (updatedHistory[i]['amount'] as num?)?.toInt() ?? 0;
        final rem = totalAmt.toInt() - runningPaid;
        updatedHistory[i] = {
          ...updatedHistory[i],
          'remaining': rem < 0 ? 0 : rem,
          'isPelunasan': rem <= 0,
        };
      }

      final totalPaid = updatedHistory.fold<int>(
          0, (s, h) => s + ((h['amount'] as num?)?.toInt() ?? 0));
      final newRemaining = totalAmt.toInt() - totalPaid;
      final newIsPaid = newRemaining <= 0;
      final lastEntryDate =
          updatedHistory.last['date'] as Timestamp?;

      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(doc.id)
          .update({
        'paymentHistory': updatedHistory,
        'partialAmount': totalPaid,
        'remainingDebt': newRemaining < 0 ? 0 : newRemaining,
        'isPaid': newIsPaid,
        'isBayarSebagian': updatedHistory.isNotEmpty && !newIsPaid,
        'paymentMethod': updatedHistory.last['paymentMethod'],
        'paymentSubOption': updatedHistory.last['paymentSubOption'],
        'lastPaidAt': lastEntryDate,
        if (newIsPaid) 'paidAt': lastEntryDate,
        if (!newIsPaid) 'paidAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('activity_logs')
          .add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': 'edit_payment_history',
        'transactionId': doc.id,
        'description':
            'Mengedit riwayat pembayaran #${index + 1}: ${fmt.format(newAmount)} via ${_methodLabel(newMethod, newSubOption)}',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        AppNotification.saved('Riwayat pembayaran berhasil diperbarui');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.networkError();
      }
    }
  }

  Future<void> _pickLastPaidAt(
      QueryDocumentSnapshot doc, DateTime? current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Tanggal Bayar Terakhir',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme:
                const ColorScheme.light(primary: _green)),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(doc.id)
          .update({
        'lastPaidAt': Timestamp.fromDate(picked),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        AppNotification.saved(
            'Tanggal bayar terakhir diperbarui: ${DateFormat('dd MMMM yyyy', 'id_ID').format(picked)}');
      }
    } catch (e) {
      if (mounted) AppNotification.networkError();
    }
  }

  Widget _bayarSebagianButton(
      QueryDocumentSnapshot doc, NumberFormat fmt,
      {required String label}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showBayarSebagianSheet(doc, fmt),
        style: OutlinedButton.styleFrom(
          foregroundColor: _blue,
          side: const BorderSide(color: _blue, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        icon: const Icon(Icons.payments_outlined, size: 16),
        label: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _lunasiButton(
      QueryDocumentSnapshot doc, NumberFormat fmt) {
    final data =
        (doc.data() ?? <String, dynamic>{}) as Map<String, dynamic>;
    final sisa = _effectiveDebt(data);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => _showLunasiSheet(doc, fmt),
        style: ElevatedButton.styleFrom(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          padding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 14),
            const SizedBox(width: 6),
            Flexible(
              child: Text('Lunasi (${fmt.format(sisa)})',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }

  void _showBayarSebagianSheet(
      QueryDocumentSnapshot doc, NumberFormat fmt) {
    final data =
        (doc.data() ?? <String, dynamic>{}) as Map<String, dynamic>;
    final currentDebt = _effectiveDebt(data);
    final ctrl = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String? selectedPayMethod;
    String? selectedPaySubOption;

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
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                        child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                                color: _bdr,
                                borderRadius:
                                    BorderRadius.circular(2)))),
                    const SizedBox(height: 20),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: _blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.payments_outlined,
                            color: _blue, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                            const Text('Bayar Sebagian',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: _ink)),
                            Text(data['productName'] ?? 'Produk',
                                style: const TextStyle(
                                    fontSize: 12, color: _inkLt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ])),
                    ]),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _blueXlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _blue.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Sisa hutang saat ini',
                                style: TextStyle(
                                    fontSize: 13, color: _inkLt)),
                            Text(fmt.format(currentDebt),
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: _blue)),
                          ]),
                    ),
                    const SizedBox(height: 16),
                    _buildPaymentMethodSelector(
                      selectedKey: selectedPayMethod,
                      selectedSubOption: selectedPaySubOption,
                      onChanged: (key, sub) => setSheet(() {
                        selectedPayMethod = key;
                        selectedPaySubOption = sub;
                      }),
                    ),
                    const SizedBox(height: 16),
                    const Text('Tanggal Pembayaran',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _inkMid)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        FocusScope.of(sheetCtx).unfocus();
                        await Future.delayed(
                            const Duration(milliseconds: 100));
                        if (!sheetCtx.mounted) return;
                        final picked = await showDatePicker(
                          context: sheetRootCtx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          helpText: 'Tanggal Pembayaran',
                          builder: (ctx, child) => Theme(
                            data: Theme.of(ctx).copyWith(
                                colorScheme: const ColorScheme.light(
                                    primary: _blue)),
                            child: child!,
                          ),
                        );
                        if (picked != null) {
                          setSheet(() => selectedDate = picked);
                        }
                      },
                      child: _buildDatePickerRow(selectedDate, _blue),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: ctrl,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_ThousandSepFormatter()],
                      onChanged: (_) => setSheet(() {}),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Jumlah yang Dibayar',
                        prefixText: 'Rp ',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: _blue, width: 2),
                        ),
                        errorText: () {
                          if (ctrl.text.isEmpty) return null;
                          final v =
                              int.tryParse(_rawDigits(ctrl.text)) ?? 0;
                          if (v <= 0) return 'Masukkan jumlah valid';
                          if (v >= currentDebt) {
                            return 'Gunakan "Lunasi" untuk melunasi penuh';
                          }
                          return null;
                        }(),
                      ),
                    ),
                    if (ctrl.text.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Builder(builder: (_) {
                        final v =
                            int.tryParse(_rawDigits(ctrl.text)) ?? 0;
                        final sisa = currentDebt - v;
                        if (v <= 0 || v >= currentDebt) {
                          return const SizedBox.shrink();
                        }
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _green.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Sisa setelah bayar',
                                    style: TextStyle(
                                        fontSize: 12, color: _green)),
                                Text(fmt.format(sisa.round()),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: _green)),
                              ]),
                        );
                      }),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: selectedPayMethod == null
                            ? null
                            : () {
                                final v = int.tryParse(
                                        _rawDigits(ctrl.text)) ??
                                    0;
                                if (v > 0 && v < currentDebt) {
                                  Navigator.pop(sheetCtx);
                                  _processBayarSebagian(
                                      doc,
                                      v.toDouble(),
                                      selectedDate,
                                      selectedPayMethod!,
                                      selectedPaySubOption);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedPayMethod == null
                              ? Colors.grey
                              : _blue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(
                          selectedPayMethod == null
                              ? 'Pilih metode pembayaran dulu'
                              : 'Konfirmasi Pembayaran',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  void _showLunasiSheet(
      QueryDocumentSnapshot doc, NumberFormat fmt) {
    final data =
        (doc.data() ?? <String, dynamic>{}) as Map<String, dynamic>;
    final currentDebt = _effectiveDebt(data);
    DateTime selectedDate = DateTime.now();
    String? selectedPayMethod;
    String? selectedPaySubOption;

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
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                        child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                                color: _bdr,
                                borderRadius:
                                    BorderRadius.circular(2)))),
                    const SizedBox(height: 20),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12)),
                        child: const Icon(
                            Icons.check_circle_outline,
                            color: _green,
                            size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                            const Text('Lunasi Hutang',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: _ink)),
                            Text(
                                '${data['productName'] ?? 'Produk'} · ${fmt.format(currentDebt)}',
                                style: const TextStyle(
                                    fontSize: 12, color: _inkLt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ])),
                    ]),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _green.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline,
                            color: _green, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(
                          'Transaksi akan ditandai LUNAS sebesar ${fmt.format(currentDebt)}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: _green,
                              fontWeight: FontWeight.w500),
                        )),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    _buildPaymentMethodSelector(
                      selectedKey: selectedPayMethod,
                      selectedSubOption: selectedPaySubOption,
                      onChanged: (key, sub) => setSheet(() {
                        selectedPayMethod = key;
                        selectedPaySubOption = sub;
                      }),
                    ),
                    const SizedBox(height: 16),
                    const Text('Tanggal Pelunasan',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _inkMid)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        FocusScope.of(sheetCtx).unfocus();
                        await Future.delayed(
                            const Duration(milliseconds: 100));
                        if (!sheetCtx.mounted) return;
                        final picked = await showDatePicker(
                          context: sheetRootCtx,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          helpText: 'Tanggal Pelunasan',
                          builder: (ctx, child) => Theme(
                            data: Theme.of(ctx).copyWith(
                                colorScheme: const ColorScheme.light(
                                    primary: _green)),
                            child: child!,
                          ),
                        );
                        if (picked != null) {
                          setSheet(() => selectedDate = picked);
                        }
                      },
                      child:
                          _buildDatePickerRow(selectedDate, _green),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: selectedPayMethod == null
                            ? null
                            : () {
                                Navigator.pop(sheetCtx);
                                _processLunasi(
                                    doc,
                                    selectedDate,
                                    selectedPayMethod!,
                                    selectedPaySubOption);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedPayMethod == null
                              ? Colors.grey
                              : _green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(
                          selectedPayMethod == null
                              ? 'Pilih metode pembayaran dulu'
                              : 'Konfirmasi Pelunasan',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodSelector({
    required String? selectedKey,
    required String? selectedSubOption,
    required void Function(String key, String? sub) onChanged,
  }) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Metode Pembayaran',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _inkMid)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.8,
            children: _debtPayMethods
                .map((method) => _buildMethodTile(
                    method,
                    selectedKey == method.key,
                    () => onChanged(method.key, null)))
                .toList(),
          ),
          if (selectedKey == 'E-Wallet') ...[
            const SizedBox(height: 12),
            const Text('Pilih Platform',
                style: TextStyle(
                    fontSize: 12,
                    color: _inkMid,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (_debtPayMethods
                          .firstWhere((m) => m.key == 'E-Wallet')
                          .subOptions ??
                      [])
                  .map((sub) => ChoiceChip(
                        label: Text(sub,
                            style: TextStyle(
                                fontSize: 12,
                                color: selectedSubOption == sub
                                    ? Colors.white
                                    : Colors.black87)),
                        selected: selectedSubOption == sub,
                        selectedColor: const Color(0xFFFF9800),
                        onSelected: (_) =>
                            onChanged('E-Wallet', sub),
                      ))
                  .toList(),
            ),
          ],
          if (selectedKey != null &&
              selectedKey != 'E-Wallet') ...[
            const SizedBox(height: 8),
            Builder(builder: (_) {
              final matches = _debtPayMethods
                  .where((m) => m.key == selectedKey);
              final method = matches.isEmpty
                  ? _debtPayMethods.first
                  : matches.first;
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: method.color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.check_circle_rounded,
                      color: method.color, size: 14),
                  const SizedBox(width: 8),
                  Text('Metode: ${method.label}',
                      style: TextStyle(
                          fontSize: 12,
                          color: method.color,
                          fontWeight: FontWeight.w600)),
                ]),
              );
            }),
          ],
        ]);
  }

  Widget _buildMethodTile(
      _PayMethod method, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? method.color.withValues(alpha: 0.12)
              : Colors.grey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isSelected
                  ? method.color
                  : Colors.grey.withValues(alpha: 0.3),
              width: isSelected ? 2 : 1),
        ),
        child: Row(children: [
          Icon(method.icon,
              color: isSelected ? method.color : Colors.grey,
              size: 18),
          const SizedBox(width: 6),
          Expanded(
              child: Text(method.label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected
                          ? method.color
                          : Colors.black87),
                  overflow: TextOverflow.ellipsis)),
          if (isSelected)
            Icon(Icons.check_circle, color: method.color, size: 12),
        ]),
      ),
    );
  }

  Widget _buildDatePickerRow(DateTime date, Color color) {
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.calendar_today_rounded,
              color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Text('Tanggal dipilih',
                  style: TextStyle(fontSize: 10, color: _inkLt)),
              const SizedBox(height: 2),
              Text(
                  DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(date),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _ink),
                  overflow: TextOverflow.ellipsis),
            ])),
        if (isToday)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Text('Hari ini',
                style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w600)),
          )
        else
          Icon(Icons.edit_calendar_rounded, color: color, size: 16),
      ]),
    );
  }

  Future<void> _processBayarSebagian(
      QueryDocumentSnapshot doc,
      double bayar,
      DateTime paymentDate,
      String payMethod,
      String? paySubOption) async {
    final data =
        (doc.data() ?? <String, dynamic>{}) as Map<String, dynamic>;
    final currentDebt = _effectiveDebt(data);
    final newRemaining = currentDebt - bayar;
    final oldPartial = (data['partialAmount'] ?? 0).toDouble();
    final newPartial = oldPartial + bayar;
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final List<Map<String, dynamic>> paymentHistory =
          List<Map<String, dynamic>>.from(
              data['paymentHistory'] ?? []);
      paymentHistory.add({
        'amount': bayar.round(),
        'date': Timestamp.fromDate(paymentDate),
        'remaining': newRemaining.round(),
        'paymentMethod': payMethod,
        'paymentSubOption': paySubOption,
      });

      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(doc.id)
          .update({
        'isBayarSebagian': newRemaining > 0,
        'partialAmount': newPartial.round(),
        'remainingDebt':
            newRemaining.round() < 0 ? 0 : newRemaining.round(),
        'isPaid': newRemaining <= 0,
        'lastPaidAt': Timestamp.fromDate(paymentDate),
        'paymentHistory': paymentHistory,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('activity_logs')
          .add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': 'partial_payment',
        'transactionId': doc.id,
        'description':
            'Bayar sebagian ${fmt.format(bayar.round())}, sisa ${fmt.format(newRemaining.round())}',
        'paymentMethod': payMethod,
        'paymentSubOption': paySubOption,
        'paidAt': Timestamp.fromDate(paymentDate),
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        if (newRemaining <= 0) {
          AppNotification.paid('Transaksi telah lunas');
        } else {
          AppNotification.partialPaid(
              'Sisa hutang: ${fmt.format(newRemaining.round())}');
        }
      }
    } catch (e) {
      if (mounted) AppNotification.networkError();
    }
  }

  Future<void> _processLunasi(
      QueryDocumentSnapshot doc,
      DateTime paymentDate,
      String payMethod,
      String? paySubOption) async {
    final data =
        (doc.data() ?? <String, dynamic>{}) as Map<String, dynamic>;
    final currentDebt = _effectiveDebt(data);
    final oldPartial = (data['partialAmount'] ?? 0).toDouble();
    final newPartial = oldPartial + currentDebt;
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final List<Map<String, dynamic>> paymentHistory =
          List<Map<String, dynamic>>.from(
              data['paymentHistory'] ?? []);
      paymentHistory.add({
        'amount': currentDebt.round(),
        'date': Timestamp.fromDate(paymentDate),
        'remaining': 0,
        'paymentMethod': payMethod,
        'paymentSubOption': paySubOption,
        'isPelunasan': true,
      });

      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(doc.id)
          .update({
        'isBayarSebagian': false,
        'partialAmount': newPartial.round(),
        'remainingDebt': 0,
        'isPaid': true,
        'paidAt': Timestamp.fromDate(paymentDate),
        'lastPaidAt': Timestamp.fromDate(paymentDate),
        'paymentHistory': paymentHistory,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('activity_logs')
          .add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': 'settle_debt',
        'transactionId': doc.id,
        'description':
            'Melunasi hutang ${fmt.format(currentDebt.round())} — LUNAS',
        'paymentMethod': payMethod,
        'paymentSubOption': paySubOption,
        'paidAt': Timestamp.fromDate(paymentDate),
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        AppNotification.paid(
            'Hutang ${fmt.format(currentDebt.round())} telah dilunasi');
      }
    } catch (e) {
      if (mounted) AppNotification.networkError();
    }
  }

  Widget _buildActionBar(NumberFormat fmt, double selectedDebt) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Color(0x14000000),
              blurRadius: 20,
              offset: Offset(0, -4))
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: _bdr, borderRadius: BorderRadius.circular(2)),
          ),
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: Center(
                child: Text('${_selected.length}',
                    style: const TextStyle(
                        color: _green,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Text('${_selected.length} transaksi dipilih',
                  style:
                      const TextStyle(fontSize: 12, color: _inkLt)),
              const SizedBox(height: 2),
              Text(fmt.format(selectedDebt),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _ink)),
            ])),
            TextButton(
              onPressed: () => setState(() => _selected.clear()),
              child: const Text('Batal',
                  style: TextStyle(color: _inkLt, fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isUpdating
                  ? null
                  : () => _showBatchConfirmSheet(fmt, selectedDebt),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isUpdating
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 19),
                        const SizedBox(width: 10),
                        Text(
                            'Proses ${_selected.length} Pelunasan →',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ]),
            ),
          ),
          const SizedBox(height: 10),
          if (_selected.length == 1) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: _isUpdating
                    ? null
                    : () async {
                        final selectedDoc = (_cachedDocs ?? [])
                            .firstWhere(
                                (d) => _selected.contains(d.id));
                        final data = (selectedDoc.data() ??
                            <String, dynamic>{}) as Map<String, dynamic>;
                        final isSebagian =
                            data['isBayarSebagian'] == true;
                        final totalAmt =
                            (data['totalAmount'] ?? 0).toDouble();
                        final partialAmt =
                            (data['partialAmount'] ?? 0).toDouble();
                        final remainingDebt = isSebagian
                            ? (data['remainingDebt'] ?? 0).toDouble()
                            : totalAmt;

                        final receiptData = ReceiptData(
                          transactionId: selectedDoc.id,
                          productName:
                              data['productName'] ?? 'Produk',
                          customerNumber:
                              (data['customerNumber'] ?? '').toString(),
                          customerName:
                              widget.customerName.isNotEmpty
                                  ? widget.customerName
                                  : (data['customerName'] ?? '')
                                      .toString(),
                          totalAmount: totalAmt.round(),
                          nominal:
                              (data['nominal'] ?? 0) as int,
                          adminFee:
                              (data['adminFee'] ?? 0) as int,
                          paymentMethod: 'Hutang',
                          isPaid: false,
                          isBayarSebagian: isSebagian,
                          partialAmount: isSebagian
                              ? partialAmt.round()
                              : null,
                          remainingDebt: remainingDebt.round(),
                          transactionDate:
                              (data['date'] as Timestamp).toDate(),
                          category:
                              (data['category'] ?? '').toString(),
                          items: const [],
                          kembalian: 0,
                        );

                        await PrinterService()
                            .showReceiptPreview(context, receiptData);
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _blue,
                  side:
                      const BorderSide(color: _blue, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Lihat Struk',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ]),
              ),
            ),
          ] else if (_selected.length > 1) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: _isUpdating
                    ? null
                    : () =>
                        _showGabungStrukSheet(fmt, selectedDebt),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _purple,
                  side:
                      const BorderSide(color: _purple, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.receipt_long_rounded,
                          size: 18),
                      const SizedBox(width: 8),
                      Text(
                          'Jadikan 1 Struk (${_selected.length} transaksi)',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ]),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _showBluetoothOffNotif() {
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF8F00),
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20)),
                ),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bluetooth_disabled_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Bluetooth Mati',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFF8F00)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline_rounded,
                          color: Color(0xFFFF8F00), size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Bluetooth perlu dinyalakan untuk mencetak struk via printer thermal.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF7B4F00),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Get.back(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              const Color(0xFF6B7280),
                          side: const BorderSide(
                              color: Color(0xFFD1D5DB)),
                          padding: const EdgeInsets.symmetric(
                              vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Batal',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Get.back();
                          switch (OpenSettingsPlus.shared) {
                            case OpenSettingsPlusAndroid settings:
                              settings.bluetooth();
                            case OpenSettingsPlusIOS settings:
                              settings.bluetooth();
                            default:
                              if (Platform.isAndroid) {
                                FlutterBluePlus.turnOn();
                              }
                          }
                        },
                        icon: const Icon(Icons.bluetooth_rounded,
                            size: 18),
                        label: const Text('Nyalakan',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8F00),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                ]),
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: true,
    );
  }

  void _showGabungStrukSheet(NumberFormat fmt, double selectedDebt) {
    final selectedDocs = (_cachedDocs ?? [])
        .where((d) => _selected.contains(d.id))
        .toList();
    if (selectedDocs.isEmpty) return;

    final strukturKey = GlobalKey();
    final List<Map<String, dynamic>> allItems = [];
    for (final doc in selectedDocs) {
      final data =
          (doc.data() ?? <String, dynamic>{}) as Map<String, dynamic>;
      allItems.add(data);
    }

    final firstData = allItems.first;
    final customerName =
        widget.customerName.isNotEmpty ? widget.customerName : '';
    final customerNumber =
        (firstData['customerNumber'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF1F5F9),
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(children: [
            Container(
              color: Colors.white,
              child: Column(children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _purple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.receipt_long_rounded,
                          color: _purple, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Text('Preview Struk Gabungan',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold)),
                        Text(
                            '${selectedDocs.length} transaksi · ${fmt.format(selectedDebt)}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(sheetCtx),
                    ),
                  ]),
                ),
                const Divider(height: 1),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 20),
                child: Center(
                  child: RepaintBoundary(
                    key: strukturKey,
                    child: _GabungStrukPreview(
                      docs: selectedDocs,
                      customerName: customerName,
                      customerNumber: customerNumber,
                      fmt: fmt,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final btState = await FlutterBluePlus
                          .adapterState.first
                          .timeout(const Duration(seconds: 3))
                          .catchError(
                              (_) => BluetoothAdapterState.off);
                      if (btState != BluetoothAdapterState.on) {
                        if (sheetCtx.mounted) {
                          Navigator.pop(sheetCtx);
                        }
                        _showBluetoothOffNotif();
                        return;
                      }
                      final receiptData =
                          _buildGabungReceiptData(selectedDocs);
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      try {
                        await PrinterService()
                            .printReceipt(receiptData);
                      } catch (e) {
                        if (mounted) {
                          AppNotification.printError(e.toString());
                        }
                      }
                    },
                    icon:
                        const Icon(Icons.print_rounded, size: 20),
                    label: const Text('Cetak Struk'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        final ctx = strukturKey.currentContext;
                        if (ctx == null) return;
                        final boundary = ctx.findRenderObject()
                            as RenderRepaintBoundary;
                        final image =
                            await boundary.toImage(pixelRatio: 3.0);
                        final byteData = await image.toByteData(
                            format: ui.ImageByteFormat.png);
                        if (byteData == null) return;
                        final pngBytes =
                            byteData.buffer.asUint8List();
                        if (sheetCtx.mounted) {
                          Navigator.pop(sheetCtx);
                        }
                        final tempDir =
                            await getTemporaryDirectory();
                        final file = File(
                            '${tempDir.path}/struk_gabungan.png');
                        await file.writeAsBytes(pngBytes);
                        await SharePlus.instance.share(ShareParams(
                          files: [
                            XFile(file.path,
                                mimeType: 'image/png')
                          ],
                        ));
                      } catch (e) {
                        AppNotification.shareError();
                      }
                    },
                    icon: const Icon(Icons.share_rounded, size: 20),
                    label: const Text('Bagikan Struk'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  ReceiptData _buildGabungReceiptData(
      List<QueryDocumentSnapshot> docs) {
    double totalPartial = 0;
    double totalRemaining = 0;
    DateTime? oldestDate;
    String? firstCustomerName;
    String? firstCustomerNumber;
    String? firstCategory;
    final List<ReceiptItem> items = [];

    for (final doc in docs) {
      final data =
          (doc.data() ?? <String, dynamic>{}) as Map<String, dynamic>;
      final isSebagian = data['isBayarSebagian'] == true;
      final originalAmt = (data['totalAmount'] ?? 0).toDouble();
      final partialAmt = (data['partialAmount'] ?? 0).toDouble();
      final remainingDebt = isSebagian
          ? (data['remainingDebt'] ?? 0).toDouble()
          : originalAmt;
      final date = (data['date'] as Timestamp).toDate();

      totalPartial += partialAmt;
      totalRemaining += remainingDebt;

      firstCustomerName ??= data['customerName'] as String?;
      firstCustomerNumber ??= data['customerNumber'] as String?;
      firstCategory ??= data['category'] as String?;

      if (oldestDate == null || date.isBefore(oldestDate)) {
        oldestDate = date;
      }

      items.add(ReceiptItem(
        productName: data['productName'] ?? 'Produk',
        quantity: 1,
        hargaJual: remainingDebt.round(),
        subtotal: remainingDebt.round(),
        customerNumber: (data['customerNumber'] ?? '').toString(),
        nominal: (data['nominal'] ?? 0) as int,
        adminFee: (data['adminFee'] ?? 0) as int,
        atasNama: (data['atasNama'] ?? '').toString(),
        category: (data['category'] ?? '').toString(),
      ));
    }

    final gabungId = docs.map((d) => d.id.substring(0, 4)).join('');

    return ReceiptData(
      transactionId: gabungId,
      productName: items.length == 1
          ? items.first.productName
          : '${items.length} Produk Piutang',
      customerNumber: firstCustomerNumber ?? '',
      customerName: firstCustomerName ?? widget.customerName,
      totalAmount: totalRemaining.round(),
      nominal: 0,
      adminFee: 0,
      paymentMethod: 'Hutang',
      isPaid: false,
      isBayarSebagian: totalPartial > 0,
      partialAmount:
          totalPartial > 0 ? totalPartial.round() : null,
      remainingDebt: totalRemaining.round(),
      transactionDate: oldestDate ?? DateTime.now(),
      category: firstCategory ?? '',
      items: items.length > 1 ? items : [],
      kembalian: 0,
    );
  }

  void _showBatchConfirmSheet(NumberFormat fmt, double selectedDebt) {
    final docs = List<String>.from(_selected);
    DateTime paidDate = DateTime.now();
    String? selectedPayMethod;
    String? selectedPaySubOption;
    bool isProcessing = false;

    final defaultFormatted = NumberFormat('#,##0', 'id_ID')
        .format(selectedDebt.round())
        .replaceAll(',', '.');
    final amountCtrl = TextEditingController(text: defaultFormatted);
    final previewDocs =
        (_cachedDocs ?? []).where((d) => docs.contains(d.id)).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (sheetRootCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) {
          int enteredAmount() =>
              int.tryParse(_rawDigits(amountCtrl.text)) ?? 0;
          bool isKurang() =>
              enteredAmount() > 0 && enteredAmount() < selectedDebt;
          bool isLebih() => enteredAmount() > selectedDebt;

          List<Map<String, dynamic>> previewAllocation() {
            final result = <Map<String, dynamic>>[];
            double budget = enteredAmount().toDouble();
            for (final doc in previewDocs) {
              final data = (doc.data() ?? <String, dynamic>{})
                  as Map<String, dynamic>;
              final debt = _effectiveDebt(data);
              final paid = budget >= debt ? debt : budget;
              budget =
                  (budget - paid).clamp(0, double.infinity);
              if (paid > 0) {
                result.add({
                  'name': data['productName'] ?? 'Produk',
                  'debt': debt,
                  'paid': paid,
                  'isLunas': paid >= debt,
                  'remaining': debt - paid,
                });
              }
            }
            return result;
          }

          return Padding(
            padding: EdgeInsets.only(
                bottom:
                    MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(28)),
              ),
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.fromLTRB(24, 16, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                        child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                                color: _bdr,
                                borderRadius:
                                    BorderRadius.circular(2)))),
                    const SizedBox(height: 20),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.1),
                            borderRadius:
                                BorderRadius.circular(14)),
                        child: const Icon(
                            Icons.playlist_add_check_rounded,
                            color: _green,
                            size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                            Text(
                                'Konfirmasi ${docs.length} Pelunasan',
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: _ink)),
                            const SizedBox(height: 3),
                            const Row(children: [
                              Icon(Icons.sort_rounded,
                                  size: 11, color: _inkLt),
                              SizedBox(width: 4),
                              Text(
                                  'Urutan: piutang terlama dilunasi dulu',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: _inkLt)),
                            ]),
                          ])),
                    ]),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _green.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                              const Text('Total hutang dipilih',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: _inkLt)),
                              const SizedBox(height: 4),
                              Text(fmt.format(selectedDebt),
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: _green)),
                              const SizedBox(height: 4),
                              Text(
                                '${docs.length} transaksi · ${widget.customerName.isNotEmpty ? widget.customerName : _displayNumber}',
                                style: const TextStyle(
                                    fontSize: 11, color: _inkLt),
                              ),
                            ])),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color:
                                  _green.withValues(alpha: 0.12),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded,
                              color: _green, size: 22),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: _surf,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _bdr)),
                      child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Row(children: [
                              Icon(Icons.receipt_long_rounded,
                                  size: 13, color: _inkLt),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                    'Urutan pelunasan (terlama → terbaru)',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: _inkLt,
                                        fontWeight:
                                            FontWeight.w600)),
                              ),
                            ]),
                            const SizedBox(height: 10),
                            ...previewDocs
                                .asMap()
                                .entries
                                .take(5)
                                .map((entry) {
                              final i = entry.key;
                              final doc = entry.value;
                              final d = (doc.data() ??
                                      <String, dynamic>{})
                                  as Map<String, dynamic>;
                              final debt = _effectiveDebt(d);
                              final date = (d['date'] as Timestamp)
                                  .toDate();
                              return Padding(
                                padding: const EdgeInsets.only(
                                    bottom: 8),
                                child: Row(children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                        color: _green.withValues(
                                            alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(
                                                6)),
                                    child: Center(
                                        child: Text('${i + 1}',
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: _green,
                                                fontWeight: FontWeight
                                                    .bold))),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                          children: [
                                        Text(
                                            d['productName'] ??
                                                'Produk',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: _ink),
                                            overflow:
                                                TextOverflow
                                                    .ellipsis),
                                        Text(
                                            DateFormat(
                                                    'dd MMM yy',
                                                    'id_ID')
                                                .format(date),
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: _inkLt)),
                                      ])),
                                  const SizedBox(width: 8),
                                  Text(fmt.format(debt),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight:
                                              FontWeight.w600,
                                          color: _inkMid)),
                                ]),
                              );
                            }),
                            if (previewDocs.length > 5) ...[
                              const SizedBox(height: 4),
                              Text(
                                  '+ ${previewDocs.length - 5} transaksi lainnya',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: _inkLt,
                                      fontStyle: FontStyle.italic)),
                            ],
                          ]),
                    ),
                    const SizedBox(height: 20),
                    const Divider(height: 1, color: _bdr),
                    const SizedBox(height: 20),
                    _buildPaymentMethodSelector(
                      selectedKey: selectedPayMethod,
                      selectedSubOption: selectedPaySubOption,
                      onChanged: (key, sub) => setSheet(() {
                        selectedPayMethod = key;
                        selectedPaySubOption = sub;
                      }),
                    ),
                    const SizedBox(height: 16),
                    const Text('Tanggal Pelunasan',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _inkMid)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        FocusScope.of(sheetCtx).unfocus();
                        await Future.delayed(
                            const Duration(milliseconds: 100));
                        if (!sheetCtx.mounted) return;
                        final picked = await showDatePicker(
                          context: sheetRootCtx,
                          initialDate: paidDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          helpText: 'Tanggal Pelunasan',
                          builder: (ctx, child) => Theme(
                            data: Theme.of(ctx).copyWith(
                                colorScheme:
                                    const ColorScheme.light(
                                        primary: _green)),
                            child: child!,
                          ),
                        );
                        if (picked != null) {
                          setSheet(() => paidDate = picked);
                        }
                      },
                      child: _buildDatePickerRow(paidDate, _green),
                    ),
                    const SizedBox(height: 16),
                    const Text('Jumlah yang Dibayar',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _inkMid)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [_ThousandSepFormatter()],
                      onChanged: (_) => setSheet(() {}),
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _ink),
                      decoration: InputDecoration(
                        prefixText: 'Rp ',
                        prefixStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _inkMid),
                        hintText: '0',
                        filled: true,
                        fillColor: _surf,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: _bdr),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              const BorderSide(color: _bdr),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: _green, width: 2),
                        ),
                        errorText: () {
                          if (amountCtrl.text.isEmpty) {
                            return 'Masukkan jumlah pembayaran';
                          }
                          final v = int.tryParse(
                                  _rawDigits(amountCtrl.text)) ??
                              0;
                          if (v <= 0) {
                            return 'Jumlah harus lebih dari 0';
                          }
                          return null;
                        }(),
                        suffixIcon: amountCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                    color: _inkLt),
                                onPressed: () {
                                  amountCtrl.clear();
                                  setSheet(() {});
                                })
                            : null,
                      ),
                    ),
                    Builder(builder: (_) {
                      final entered = enteredAmount();
                      if (entered <= 0) return const SizedBox.shrink();
                      final diff = entered - selectedDebt;

                      if (diff == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(children: [
                            const Icon(Icons.check_circle_rounded,
                                size: 14, color: _green),
                            const SizedBox(width: 6),
                            Text(
                                'Sesuai total hutang (${fmt.format(selectedDebt)})',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: _green,
                                    fontWeight: FontWeight.w500)),
                          ]),
                        );
                      }

                      if (diff > 0) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius:
                                  BorderRadius.circular(10),
                              border: Border.all(
                                  color: _green.withValues(
                                      alpha: 0.4)),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Row(children: [
                                  Icon(Icons.check_circle_rounded,
                                      size: 14, color: _green),
                                  SizedBox(width: 6),
                                  Text('Semua piutang akan LUNAS',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: _green,
                                          fontWeight:
                                              FontWeight.w700)),
                                ]),
                                const SizedBox(height: 8),
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    border: Border.all(
                                        color: _green.withValues(
                                            alpha: 0.3)),
                                  ),
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment
                                              .spaceBetween,
                                      children: [
                                        const Row(children: [
                                          Icon(
                                              Icons.savings_rounded,
                                              size: 16,
                                              color: _green),
                                          SizedBox(width: 8),
                                          Text(
                                              'Kembalian untuk pelanggan',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: _inkMid,
                                                  fontWeight:
                                                      FontWeight
                                                          .w500)),
                                        ]),
                                        Text(
                                            fmt.format(diff.round()),
                                            style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight:
                                                    FontWeight.bold,
                                                color: _green)),
                                      ]),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFFFFB300)
                                    .withValues(alpha: 0.5)),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(
                                    Icons.warning_amber_rounded,
                                    size: 14,
                                    color: Color(0xFFFFB300)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Kurang ${fmt.format((-diff).round())} dari total hutang',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF7B6000),
                                        fontWeight:
                                            FontWeight.w600),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 6),
                              const Row(children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 12,
                                    color: Color(0xFF7B6000)),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Dibayar ke piutang terlama dulu, sisanya tetap tercatat',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF7B6000)),
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      );
                    }),
                    Builder(builder: (_) {
                      final entered = enteredAmount();
                      if (entered <= 0 || selectedPayMethod == null) {
                        return const SizedBox.shrink();
                      }
                      final allocation = previewAllocation();
                      if (allocation.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _blue.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    _blue.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Row(children: [
                                  Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 13,
                                      color: _blue),
                                  SizedBox(width: 6),
                                  Text(
                                      'Preview alokasi pembayaran',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: _blue,
                                          fontWeight:
                                              FontWeight.w600)),
                                ]),
                                const SizedBox(height: 10),
                                ...allocation.map((item) => Padding(
                                      padding:
                                          const EdgeInsets.only(
                                              bottom: 6),
                                      child: Row(children: [
                                        Icon(
                                          item['isLunas']
                                              ? Icons
                                                  .check_circle_rounded
                                              : Icons
                                                  .radio_button_checked,
                                          size: 13,
                                          color: item['isLunas']
                                              ? _green
                                              : _orange,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                            child: Text(
                                                item['name'],
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: _ink),
                                                overflow: TextOverflow
                                                    .ellipsis)),
                                        const SizedBox(width: 8),
                                        Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment
                                                    .end,
                                            children: [
                                              Text(
                                                '${fmt.format((item['paid'] as double).round())} dibayar',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: item[
                                                            'isLunas']
                                                        ? _green
                                                        : _orange,
                                                    fontWeight:
                                                        FontWeight
                                                            .w600),
                                              ),
                                              if (!(item['isLunas']
                                                  as bool))
                                                Text(
                                                  'sisa ${fmt.format((item['remaining'] as double).round())}',
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: _inkLt),
                                                ),
                                            ]),
                                      ]),
                                    )),
                                if (isLebih()) ...[
                                  const Divider(
                                      height: 12, color: _bdr),
                                  Row(children: [
                                    const Icon(Icons.savings_rounded,
                                        size: 13, color: _green),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                        child: Text('Kembalian',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: _green,
                                                fontWeight:
                                                    FontWeight
                                                        .w600))),
                                    Text(
                                      fmt.format((enteredAmount() -
                                              selectedDebt)
                                          .round()),
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: _green,
                                          fontWeight:
                                              FontWeight.bold),
                                    ),
                                  ]),
                                ],
                              ]),
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                    if (selectedPayMethod != null) ...[
                      Builder(builder: (_) {
                        final entered = enteredAmount();
                        final lebih = isLebih();
                        final kurang = isKurang();
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: lebih
                                ? const Color(0xFFE8F5E9)
                                : kurang
                                    ? const Color(0xFFFFF8E1)
                                    : _blueXlt,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: lebih
                                    ? _green.withValues(alpha: 0.3)
                                    : kurang
                                        ? const Color(0xFFFFB300)
                                            .withValues(alpha: 0.4)
                                        : _blue
                                            .withValues(alpha: 0.2)),
                          ),
                          child: Column(children: [
                            _summaryRow(
                              icon: Icons.attach_money_rounded,
                              label: 'Jumlah Dibayar',
                              value: entered > 0
                                  ? fmt.format(entered)
                                  : fmt.format(selectedDebt),
                              color: lebih
                                  ? _green
                                  : kurang
                                      ? _orange
                                      : _green,
                              bold: true,
                            ),
                            if (lebih) ...[
                              const SizedBox(height: 8),
                              _summaryRow(
                                icon: Icons.savings_rounded,
                                label: 'Kembalian',
                                value: fmt.format(
                                    (entered - selectedDebt)
                                        .round()),
                                color: _green,
                                bold: true,
                              ),
                            ],
                            if (kurang) ...[
                              const SizedBox(height: 8),
                              _summaryRow(
                                icon: Icons
                                    .account_balance_wallet_outlined,
                                label: 'Sisa Piutang',
                                value: fmt.format(
                                    (selectedDebt - entered)
                                        .round()),
                                color: _red,
                                bold: true,
                              ),
                            ],
                            const SizedBox(height: 8),
                            _summaryRow(
                              icon: Icons.payment_rounded,
                              label: 'Metode',
                              value: selectedPayMethod! +
                                  (selectedPaySubOption != null
                                      ? ' · $selectedPaySubOption'
                                      : ''),
                              color: _blue,
                            ),
                            const SizedBox(height: 8),
                            _summaryRow(
                              icon: Icons.calendar_today_rounded,
                              label: 'Tanggal',
                              value: DateFormat(
                                      'dd MMMM yyyy', 'id_ID')
                                  .format(paidDate),
                              color: _blue,
                            ),
                          ]),
                        );
                      }),
                      const SizedBox(height: 16),
                    ],
                    Row(children: [
                      SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: isProcessing
                              ? null
                              : () => Navigator.pop(sheetCtx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _inkLt,
                            side: const BorderSide(color: _bdr),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(14)),
                          ),
                          child: const Text('Batal',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () {
                              final entered = enteredAmount();
                              if (selectedPayMethod == null ||
                                  isProcessing ||
                                  entered <= 0) {
                                return;
                              }
                              setSheet(() => isProcessing = true);
                              Navigator.pop(sheetCtx);
                              _executeBatchLunasi(
                                docs: docs,
                                paidDate: paidDate,
                                payMethod: selectedPayMethod!,
                                paySubOption: selectedPaySubOption,
                                fmt: fmt,
                                paidAmount: entered.toDouble(),
                                totalSelectedDebt: selectedDebt,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: () {
                                final entered = enteredAmount();
                                if (selectedPayMethod == null ||
                                    entered <= 0) {
                                  return Colors.grey[300];
                                }
                                return isKurang()
                                    ? const Color(0xFFFFB300)
                                    : _green;
                              }(),
                              foregroundColor: () {
                                final entered = enteredAmount();
                                if (selectedPayMethod == null ||
                                    entered <= 0) {
                                  return _inkLt;
                                }
                                return isKurang()
                                    ? const Color(0xFF7B6000)
                                    : Colors.white;
                              }(),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14)),
                            ),
                            child: isProcessing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2))
                                : Builder(builder: (_) {
                                    final entered = enteredAmount();
                                    String label;
                                    IconData icon;
                                    if (selectedPayMethod == null) {
                                      label = 'Pilih metode dulu';
                                      icon = Icons.payment_rounded;
                                    } else if (entered <= 0) {
                                      label = 'Masukkan jumlah';
                                      icon = Icons.edit_rounded;
                                    } else if (isLebih()) {
                                      label =
                                          'Konfirmasi + Kembalian';
                                      icon = Icons.savings_rounded;
                                    } else if (isKurang()) {
                                      label =
                                          'Konfirmasi Bayar Sebagian';
                                      icon =
                                          Icons.payments_outlined;
                                    } else {
                                      label = 'Konfirmasi Lunas';
                                      icon =
                                          Icons.check_circle_rounded;
                                    }
                                    return Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize:
                                          MainAxisSize.min,
                                      children: [
                                        Icon(icon, size: 18),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(label,
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight
                                                      .w700),
                                              overflow: TextOverflow
                                                  .ellipsis,
                                              maxLines: 1),
                                        ),
                                      ],
                                    );
                                  }),
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _summaryRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool bold = false,
  }) {
    return Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 8),
      Text(label,
          style: const TextStyle(fontSize: 12, color: _inkLt)),
      const Spacer(),
      Text(value,
          style: TextStyle(
              fontSize: 13,
              fontWeight:
                  bold ? FontWeight.bold : FontWeight.w600,
              color: color)),
    ]);
  }

  Future<void> _executeBatchLunasi({
    required List<String> docs,
    required DateTime paidDate,
    required String payMethod,
    required String? paySubOption,
    required NumberFormat fmt,
    required double totalSelectedDebt,
    double? paidAmount,
  }) async {
    setState(() => _isUpdating = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final batch = FirebaseFirestore.instance.batch();
      final cachedDocs = _cachedDocs ?? [];

      final effectivePaid = paidAmount ?? totalSelectedDebt;
      final isPartialPayment = effectivePaid < totalSelectedDebt;
      final isLebihPayment = effectivePaid > totalSelectedDebt;

      int lunasDocs = 0;
      int sebagianDocs = 0;
      // ignore: unused_local_variable
      int skippedDocs = 0;

      double remainingBudget = effectivePaid;
      final orderedDocs =
          cachedDocs.where((d) => docs.contains(d.id)).toList();

      for (final docSnapshot in orderedDocs) {
        final data = (docSnapshot.data() ?? <String, dynamic>{})
            as Map<String, dynamic>;
        final docDebt = _effectiveDebt(data);
        final oldPartial = (data['partialAmount'] ?? 0).toDouble();

        final docPaid =
            remainingBudget >= docDebt ? docDebt : remainingBudget;
        remainingBudget =
            (remainingBudget - docPaid).clamp(0.0, double.infinity);

        if (docPaid <= 0) {
          skippedDocs++;
          continue;
        }

        final isDocLunas = docPaid >= docDebt;
        final newRemaining =
            isDocLunas ? 0.0 : (docDebt - docPaid);
        final newPartial = oldPartial + docPaid;

        final List<Map<String, dynamic>> paymentHistory =
            List<Map<String, dynamic>>.from(
                data['paymentHistory'] ?? []);
        paymentHistory.add({
          'amount': docPaid.round(),
          'date': Timestamp.fromDate(paidDate),
          'remaining': newRemaining.round(),
          'paymentMethod': payMethod,
          'paymentSubOption': paySubOption,
          if (isDocLunas) 'isPelunasan': true,
        });

        batch.update(
          FirebaseFirestore.instance
              .collection('transactions')
              .doc(docSnapshot.id),
          {
            'isPaid': isDocLunas,
            'isBayarSebagian': !isDocLunas,
            'partialAmount': newPartial.round(),
            'remainingDebt': newRemaining.round(),
            if (isDocLunas)
              'paidAt': Timestamp.fromDate(paidDate),
            'lastPaidAt': Timestamp.fromDate(paidDate),
            'paymentMethod': payMethod,
            'paymentSubOption': paySubOption,
            'paymentHistory': paymentHistory,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );

        if (isDocLunas) {
          lunasDocs++;
        } else {
          sebagianDocs++;
        }
      }

      await batch.commit();

      final kembalian = isLebihPayment
          ? (effectivePaid - totalSelectedDebt)
          : 0.0;

      await FirebaseFirestore.instance
          .collection('activity_logs')
          .add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': isPartialPayment
            ? 'batch_partial_payment'
            : 'mark_debt_as_paid',
        'description': isLebihPayment
            ? 'Bayar ${fmt.format(effectivePaid.round())} untuk ${docs.length} piutang (kembalian ${fmt.format(kembalian.round())})'
            : isPartialPayment
                ? 'Bayar sebagian ${fmt.format(effectivePaid.round())} — lunas: $lunasDocs, sebagian: $sebagianDocs'
                : 'Lunas ${docs.length} piutang — ${fmt.format(effectivePaid.round())}',
        'paymentMethod': payMethod,
        'paymentSubOption': paySubOption,
        'paidAmount': effectivePaid.round(),
        'kembalian': kembalian.round(),
        'paidAt': Timestamp.fromDate(paidDate),
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          _selected.clear();
          _isUpdating = false;
        });

        if (isLebihPayment) {
          AppNotification.kembalian(
              'Kembalian untuk pelanggan: ${fmt.format(kembalian.round())}');
        } else if (isPartialPayment) {
          AppNotification.partialPaid(lunasDocs > 0
              ? '${fmt.format(effectivePaid.round())} — $lunasDocs lunas, $sebagianDocs masih sebagian'
              : '${fmt.format(effectivePaid.round())} dicatat ke piutang terlama');
        } else {
          AppNotification.paid(
              '${docs.length} transaksi lunas · ${fmt.format(effectivePaid.round())}');
        }
      }
    } catch (e) {
      if (mounted) {
        AppNotification.networkError();
        setState(() => _isUpdating = false);
      }
    }
  }

  Widget _amountCol(String label, String value, Color color,
      {bool bold = false}) {
    return Expanded(
        child: Column(children: [
      Text(label,
          style:
              const TextStyle(fontSize: 10, color: _inkLt)),
      const SizedBox(height: 3),
      Text(value,
          style: TextStyle(
              fontSize: 12,
              fontWeight:
                  bold ? FontWeight.bold : FontWeight.w600,
              color: color),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis),
    ]));
  }

  Widget _vDivider() => Container(
      width: 1,
      height: 30,
      color: _bdr,
      margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _pill(String label, Color color, IconData icon) =>
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: color.withValues(alpha: 0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _miniPill(String label, Color bg, Color fg) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                color: fg,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      );

  Widget _metaChip(IconData icon, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: _inkLt),
        const SizedBox(width: 4),
        Flexible(
            child: Text(label,
                style:
                    const TextStyle(fontSize: 11, color: _inkLt),
                overflow: TextOverflow.ellipsis,
                maxLines: 1)),
      ]);
}

// ═══════════════════════════════════════════════════════════════════════════
// Widget preview struk gabungan (inline)
// ═══════════════════════════════════════════════════════════════════════════

class _GabungStrukPreview extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final String customerName;
  final String customerNumber;
  final NumberFormat fmt;

  const _GabungStrukPreview({
    required this.docs,
    required this.customerName,
    required this.customerNumber,
    required this.fmt,
  });

  static const _black = Color(0xFF000000);
  static const _dark = Color(0xFF1A1A1A);
  static const _medium = Color(0xFF555555);
  static const _light = Color(0xFF888888);
  static const _lineColor = Color(0xFFBBBBBB);
  static const _bg = Color(0xFFFFFFFF);
  static const _fontMono = 'monospace';

  @override
  Widget build(BuildContext context) {
    double grandTotal = 0;
    double grandPaid = 0;
    double grandRemaining = 0;
    DateTime? oldestDate;

    for (final doc in docs) {
      final data =
          (doc.data() ?? <String, dynamic>{}) as Map<String, dynamic>;
      final isSebagian = data['isBayarSebagian'] == true;
      final originalAmt = (data['totalAmount'] ?? 0).toDouble();
      final partialAmt = (data['partialAmount'] ?? 0).toDouble();
      final remaining = isSebagian
          ? (data['remainingDebt'] ?? 0).toDouble()
          : originalAmt;
      final date = (data['date'] as Timestamp).toDate();

      grandTotal += originalAmt;
      grandPaid += partialAmt;
      grandRemaining += remaining;

      if (oldestDate == null || date.isBefore(oldestDate)) {
        oldestDate = date;
      }
    }

    return Container(
      width: 300,
      color: _bg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bigCenter('STRUSA POS'),
          _center('Aplikasi Kasir & PPOB'),
          _thickLine(),
          _kv('Tgl',
              DateFormat('dd/MM/yy HH:mm', 'id_ID')
                  .format(DateTime.now())),
          _thickLine(),
          if (customerName.isNotEmpty) ...[
            _bigCenter(customerName.toUpperCase()),
            if (customerNumber.isNotEmpty) _center(customerNumber),
            _thinLine(),
          ],
          _boldCenter('${docs.length} PIUTANG'),
          _thinLine(),
          for (int i = 0; i < docs.length; i++) ...[
            _buildItemRow(i, docs[i]),
            if (i < docs.length - 1) _thinLine(),
          ],
          _thickLine(),
          if (grandPaid > 0) ...[
            _kv('Total Tagihan', fmt.format(grandTotal)),
            _kv('Sudah Dibayar', fmt.format(grandPaid)),
            _thinLine(),
          ],
          _totalRow('TOTAL HUTANG', fmt.format(grandRemaining)),
          _thinLine(),
          _boldCenter('Status: PIUTANG',
              color: const Color(0xFFFF9800)),
          _thickLine(),
          _boldCenter('Terima Kasih!'),
          _center('Simpan struk ini sebagai'),
          _center('bukti informasi piutang'),
        ],
      ),
    );
  }

  Widget _buildItemRow(int index, QueryDocumentSnapshot doc) {
    final data =
        (doc.data() ?? <String, dynamic>{}) as Map<String, dynamic>;
    final isSebagian = data['isBayarSebagian'] == true;
    final originalAmt = (data['totalAmount'] ?? 0).toDouble();
    final partialAmt = (data['partialAmount'] ?? 0).toDouble();
    final remaining = isSebagian
        ? (data['remainingDebt'] ?? 0).toDouble()
        : originalAmt;
    final date = (data['date'] as Timestamp).toDate();
    final productName = data['productName'] ?? 'Produk';
    final custNum =
        (data['customerNumber'] ?? '').toString().trim();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(right: 6, top: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text('${index + 1}',
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2196F3),
                          fontFamily: _fontMono)),
                ),
              ),
              Expanded(
                child: Text(productName,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _dark,
                        fontFamily: _fontMono)),
              ),
            ]),
            if (custNum.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 2),
                child: Row(children: [
                  const Text('No: ',
                      style: TextStyle(
                          fontSize: 10,
                          color: _medium,
                          fontFamily: _fontMono)),
                  Expanded(
                    child: Text(custNum,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                            fontSize: 10,
                            color: _dark,
                            fontWeight: FontWeight.w600,
                            fontFamily: _fontMono)),
                  ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Row(children: [
                const Text('Tgl: ',
                    style: TextStyle(
                        fontSize: 10,
                        color: _medium,
                        fontFamily: _fontMono)),
                Expanded(
                  child: Text(
                    DateFormat('dd MMM yy', 'id_ID').format(date),
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                        fontSize: 10,
                        color: _dark,
                        fontFamily: _fontMono),
                  ),
                ),
              ]),
            ),
            if (isSebagian && partialAmt > 0)
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 2),
                child: Row(children: [
                  const Text('Sudah dibayar: ',
                      style: TextStyle(
                          fontSize: 10,
                          color: _medium,
                          fontFamily: _fontMono)),
                  Expanded(
                    child: Text(
                      fmt.format(partialAmt),
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF22C55E),
                          fontWeight: FontWeight.w600,
                          fontFamily: _fontMono),
                    ),
                  ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Row(children: [
                Text(
                  isSebagian ? 'Sisa hutang: ' : 'Jumlah hutang: ',
                  style: const TextStyle(
                      fontSize: 10,
                      color: _medium,
                      fontFamily: _fontMono),
                ),
                Expanded(
                  child: Text(
                    fmt.format(remaining),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSebagian
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF2196F3),
                        fontFamily: _fontMono),
                  ),
                ),
              ]),
            ),
          ]),
    );
  }

  Widget _thickLine() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Container(height: 1.5, color: _lineColor),
      );

  Widget _thinLine() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(height: 0.8, color: _lineColor),
      );

  Widget _bigCenter(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _black,
                fontFamily: _fontMono,
                letterSpacing: 1.5)),
      );

  Widget _boldCenter(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color ?? _dark,
                fontFamily: _fontMono)),
      );

  Widget _center(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 10,
                color: _light,
                fontFamily: _fontMono)),
      );

  Widget _kv(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: _medium,
                  fontFamily: _fontMono)),
          Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      fontSize: 11,
                      color: _dark,
                      fontWeight: FontWeight.w600,
                      fontFamily: _fontMono))),
        ]),
      );

  Widget _totalRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _black,
                  fontFamily: _fontMono)),
          Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _black,
                      fontFamily: _fontMono))),
        ]),
      );
}