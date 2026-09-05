import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../services/printer_service.dart';
import '../../services/customer_service.dart';
import '../../utils/app_notification.dart';

// ─── Thousand separator formatter ────────────────────────────────────────────
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

// ─── Payment Method model ─────────────────────────────────────────────────────
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
      color: Color(0xFF2196F3)),
  PaymentMethod(
      key: 'qris',
      label: 'QRIS',
      icon: Icons.qr_code_2,
      color: Color(0xFF9C27B0)),
  PaymentMethod(
      key: 'tunai',
      label: 'Tunai',
      icon: Icons.payments,
      color: Color(0xFF4CAF50)),
  PaymentMethod(
      key: 'E-Wallet',
      label: 'E-Wallet',
      icon: Icons.wallet,
      color: Color(0xFFFF9800),
      subOptions: ['OVO', 'GoPay', 'Dana', 'ShopeePay', 'LinkAja']),
];

// ─── Item model (dari Firestore items[]) ─────────────────────────────────────
class _TransactionItem {
  final String productId;
  final String productName;
  final String category;
  final int quantity;
  final int hargaJual;
  final int hargaBeli;
  final int subtotalJual;
  final int subtotalBeli;
  final String customerNumber;
  final String atasNama;
  final int nominal;
  final int adminFee;

  const _TransactionItem({
    required this.productId,
    required this.productName,
    required this.category,
    required this.quantity,
    required this.hargaJual,
    required this.hargaBeli,
    required this.subtotalJual,
    required this.subtotalBeli,
    required this.customerNumber,
    required this.atasNama,
    required this.nominal,
    required this.adminFee,
  });

  factory _TransactionItem.fromMap(Map<String, dynamic> m) {
    final qty = (m['quantity'] as num?)?.toInt() ?? 1;
    final hargaJual = (m['hargaJual'] as num?)?.toInt() ?? 0;
    final hargaBeli = (m['hargaBeli'] as num?)?.toInt() ?? 0;
    return _TransactionItem(
      productId: m['productId'] as String? ?? '',
      productName: m['productName'] as String? ?? '',
      category: m['category'] as String? ?? '',
      quantity: qty,
      hargaJual: hargaJual,
      hargaBeli: hargaBeli,
      subtotalJual:
          (m['subtotalJual'] as num?)?.toInt() ?? hargaJual * qty,
      subtotalBeli:
          (m['subtotalBeli'] as num?)?.toInt() ?? hargaBeli * qty,
      customerNumber: m['customerNumber'] as String? ?? '',
      atasNama: m['atasNama'] as String? ?? '',
      nominal: (m['nominal'] as num?)?.toInt() ?? 0,
      adminFee: (m['adminFee'] as num?)?.toInt() ?? 0,
    );
  }

  int get laba => subtotalJual - subtotalBeli;
}

// ─────────────────────────────────────────────────────────────────────────────

class TransactionDetailScreen extends StatefulWidget {
  final String transactionId;
  final Map<String, dynamic> transactionData;

  const TransactionDetailScreen({
    super.key,
    required this.transactionId,
    required this.transactionData,
  });

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  bool _isUpdating = false;
  final _customerService = CustomerService();

  late String? _paymentMethod;
  late String? _paymentSubOption;
  late int? _partialAmount;
  late int _totalAmount;
  late String _customerName;
  late String _atasNama;
  late DateTime _transactionDate;
  DateTime? _paidAt;
  late bool _isPaid;
  late bool _isBayarSebagian;
  late int _remainingDebt;
  late int _kembalian;
  late int? _paidAmount;
  CustomerModel? _customerInfo;
  List<Map<String, dynamic>> _paymentHistory = [];

  // ── Multi-item support ────────────────────────────────────────────────────
  late List<_TransactionItem> _items;
  late bool _isMultiItem;

  @override
  void initState() {
    super.initState();
    _initFromData(widget.transactionData);
    _loadCustomerInfo();
  }

  void _initFromData(Map<String, dynamic> d) {
    _paymentMethod = d['paymentMethod'] as String?;
    _paymentSubOption = d['paymentSubOption'] as String?;
    _partialAmount = (d['partialAmount'] as num?)?.toInt();
    _totalAmount = (d['totalAmount'] as num?)?.toInt() ?? 0;
    _customerName = d['customerName'] as String? ?? '';
    _atasNama = d['atasNama'] as String? ?? '';
    _isPaid = d['isPaid'] as bool? ?? false;
    _isBayarSebagian = d['isBayarSebagian'] as bool? ?? false;
    _remainingDebt = (d['remainingDebt'] as num?)?.toInt() ?? 0;
    _kembalian = (d['kembalian'] as num?)?.toInt() ?? 0;
    _paidAmount = (d['paidAmount'] as num?)?.toInt();

    final raw = d['date'];
    _transactionDate =
        raw != null ? (raw as Timestamp).toDate() : DateTime.now();
    final paidRaw = d['paidAt'];
    _paidAt = paidRaw != null ? (paidRaw as Timestamp).toDate() : null;
    _paymentHistory =
        List<Map<String, dynamic>>.from(d['paymentHistory'] ?? []);

    final rawItems = d['items'] as List<dynamic>?;
    if (rawItems != null && rawItems.isNotEmpty) {
      _items = rawItems
          .map((e) => _TransactionItem.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
      _isMultiItem = d['isMultiItem'] as bool? ?? (_items.length > 1);
    } else {
      _isMultiItem = false;
      _items = [
        _TransactionItem(
          productId: d['productId'] as String? ?? '',
          productName: d['productName'] as String? ?? '',
          category: d['category'] as String? ?? '',
          quantity: 1,
          hargaJual: (d['hargaJual'] as num?)?.toInt() ?? _totalAmount,
          hargaBeli: (d['hargaBeli'] as num?)?.toInt() ?? 0,
          subtotalJual: _totalAmount,
          subtotalBeli: (d['hargaBeli'] as num?)?.toInt() ?? 0,
          customerNumber: d['customerNumber'] as String? ?? '',
          atasNama: d['atasNama'] as String? ?? '',
          nominal: (d['nominal'] as num?)?.toInt() ?? 0,
          adminFee: (d['adminFee'] as num?)?.toInt() ?? 0,
        )
      ];
    }
  }

  Future<void> _loadCustomerInfo() async {
    final number = widget.transactionData['customerNumber'] as String? ?? '';
    if (number.isEmpty) return;
    final info = await _customerService.getByNumber(number);
    if (mounted) setState(() => _customerInfo = info);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String get _primaryCategory =>
      _items.isNotEmpty ? _items.first.category : '';

  bool get _hasAdminFee {
    if (_isMultiItem) return false;
    const noAdmin = ['Pulsa', 'Paket Data', 'Token Listrik', 'Lainnya'];
    return !noAdmin.contains(_primaryCategory);
  }

  bool get _hasAtasNama {
    if (_isMultiItem) return false;
    const noAtasNama = [
      'Pulsa', 'Paket Data', 'E-Wallet', 'Jasa Transfer', 'Lainnya'
    ];
    return !noAtasNama.contains(_primaryCategory);
  }

  int get _totalLaba => _items.fold(0, (s, i) => s + i.laba);
  bool get _hasBeli => _items.any((i) => i.hargaBeli > 0);

  String get _lastPaymentMethodKey {
    if (_paymentHistory.isNotEmpty) {
      return _paymentHistory.last['paymentMethod'] as String? ??
          _paymentMethod ?? '';
    }
    return _paymentMethod ?? '';
  }

  String? get _lastPaymentSubOption {
    if (_paymentHistory.isNotEmpty) {
      return _paymentHistory.last['paymentSubOption'] as String?;
    }
    return _paymentSubOption;
  }

  PaymentMethod? get _lastMethodDef =>
      _paymentMethods
          .where((m) => m.key == _lastPaymentMethodKey)
          .firstOrNull;

  String get _paymentMethodDisplay {
    final key = _lastPaymentMethodKey;
    final sub = _lastPaymentSubOption;
    if (key.isEmpty) return '-';
    final def = _lastMethodDef;
    if (def == null) return key;
    if (def.key == 'E-Wallet' && sub != null) return '${def.label} · $sub';
    return def.label;
  }

  Color get _paymentMethodColor =>
      _lastMethodDef?.color ?? Colors.grey;

  String _methodLabel(String key, String? sub) {
    final def = _paymentMethods.where((m) => m.key == key).firstOrNull;
    if (def == null) return key;
    if (def.key == 'E-Wallet' && sub != null && sub.isNotEmpty) {
      return '${def.label} · $sub';
    }
    return def.label;
  }

  IconData _methodIcon(String key) =>
      _paymentMethods.where((m) => m.key == key).firstOrNull?.icon ??
      Icons.payment;
  Color _methodColor(String key) =>
      _paymentMethods.where((m) => m.key == key).firstOrNull?.color ??
      Colors.grey;

  // ── Receipt ───────────────────────────────────────────────────────────────

  Future<void> _showReceiptPreview() async {
    final receiptItems = _items
        .map((item) => ReceiptItem(
              productName: item.productName,
              quantity: item.quantity,
              hargaJual: item.hargaJual,
              subtotal: item.subtotalJual,
              customerNumber: item.customerNumber,
              nominal: item.nominal,
              adminFee: item.adminFee,
              atasNama: item.atasNama,
              category: item.category,
            ))
        .toList();

    await PrinterService().showReceiptPreview(
      context,
      ReceiptData(
        transactionId: widget.transactionId,
        productName: _isMultiItem
            ? '${_items.first.productName} +${_items.length - 1} lainnya'
            : _items.first.productName,
        customerNumber:
            widget.transactionData['customerNumber'] as String? ?? '',
        customerName: _customerName,
        atasNama: _atasNama,
        nominal: receiptItems.isNotEmpty ? receiptItems.first.nominal : 0,
        adminFee: receiptItems.isNotEmpty ? receiptItems.first.adminFee : 0,
        totalAmount: _totalAmount,
        paymentMethod: _paymentMethodDisplay,
        isPaid: _isPaid,
        isBayarSebagian: _isBayarSebagian,
        partialAmount: _partialAmount,
        remainingDebt: _isPaid ? 0 : _remainingDebt,
        transactionDate: _transactionDate,
        category: receiptItems.isNotEmpty
            ? receiptItems.first.category
            : _primaryCategory,
        items: receiptItems,
        kembalian: _kembalian,
        paidAmount: _paidAmount,
        token: widget.transactionData['token'] as String?,
        kwh: widget.transactionData['kwh'] as String?,
      ),
    );
  }

  // ── Date editing ──────────────────────────────────────────────────────────

  Future<void> _pickTransactionDate() async {
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _transactionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Tanggal Transaksi',
      builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
              colorScheme:
                  const ColorScheme.light(primary: Color(0xFF2196F3))),
          child: child!),
    );
    if (picked != null && mounted) {
      setState(() => _transactionDate = picked);
      await _saveTransactionDate(picked);
    }
  }

  Future<void> _saveTransactionDate(DateTime date) async {
    setState(() => _isUpdating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.transactionId)
          .update({
        'date': Timestamp.fromDate(date),
        'updatedAt': FieldValue.serverTimestamp()
      });
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': 'update_transaction_date',
        'transactionId': widget.transactionId,
        'description':
            'Mengubah tanggal transaksi menjadi ${DateFormat('dd MMMM yyyy', 'id_ID').format(date)}',
        'timestamp': FieldValue.serverTimestamp()
      });
      if (mounted) {
        AppNotification.updated('Tanggal transaksi berhasil diperbarui.');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.unexpectedError('Gagal menyimpan tanggal: $e');
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _pickPaidAt() async {
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    final initial = _paidAt ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Tanggal Pembayaran',
      builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
              colorScheme:
                  const ColorScheme.light(primary: Color(0xFF4CAF50))),
          child: child!),
    );
    if (picked != null && mounted) {
      setState(() => _paidAt = picked);
      await _savePaidAt(picked);
    }
  }

  Future<void> _savePaidAt(DateTime date) async {
    setState(() => _isUpdating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.transactionId)
          .update({
        'paidAt': Timestamp.fromDate(date),
        'updatedAt': FieldValue.serverTimestamp()
      });
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': 'update_paid_at',
        'transactionId': widget.transactionId,
        'description':
            'Mengubah tanggal pembayaran menjadi ${DateFormat('dd MMMM yyyy', 'id_ID').format(date)}',
        'timestamp': FieldValue.serverTimestamp()
      });
      if (mounted) {
        AppNotification.updated('Tanggal pembayaran berhasil diperbarui.');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.unexpectedError('Gagal menyimpan: $e');
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> _deleteTransaction() async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DeleteTransactionSheet(
        productName: _isMultiItem
            ? '${_items.first.productName} +${_items.length - 1} lainnya'
            : _items.first.productName,
        totalAmount: _totalAmount,
      ),
    );
    if (confirm != true) return;
    setState(() => _isUpdating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.transactionId)
          .delete();
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': 'delete_transaction',
        'transactionId': widget.transactionId,
        'description':
            'Menghapus transaksi ${_items.first.productName} — $_customerName',
        'timestamp': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        Get.back(result: 'deleted');
        AppNotification.deleted('Transaksi berhasil dihapus.');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.unexpectedError('Gagal menghapus: $e');
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // ── Cancel Payment ────────────────────────────────────────────────────────

  Future<void> _cancelPayment() async {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    DocumentSnapshot snap;
    try {
      snap = await FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.transactionId)
          .get();
    } catch (e) {
      if (mounted) {
        AppNotification.unexpectedError('Gagal membaca data: $e');
      }
      return;
    }

    final data = snap.data() as Map<String, dynamic>;
    final history =
        List<Map<String, dynamic>>.from(data['paymentHistory'] ?? []);
    final total = (data['totalAmount'] ?? _totalAmount) as num;

    final String cancelledTitle,
        cancelledSubtitle,
        cancelledAmountLabel,
        afterCancelLabel;
    final Map<String, dynamic> rollbackFields;

    if (history.isEmpty) {
      cancelledTitle = 'Batalkan Pembayaran Penuh';
      cancelledSubtitle = 'Pembayaran penuh akan dibatalkan';
      cancelledAmountLabel = fmt.format(total);
      afterCancelLabel = 'Hutang penuh ${fmt.format(total)}';
      rollbackFields = {
        'isPaid': false,
        'paidAt': null,
        'isBayarSebagian': false,
        'partialAmount': null,
        'remainingDebt': total.toInt(),
        'lastPaidAt': null,
        'updatedAt': FieldValue.serverTimestamp()
      };
    } else {
      final lastEntry = history.last;
      final cancelledAmount = (lastEntry['amount'] ?? 0) as num;
      final cancelledMethod = lastEntry['paymentMethod'] as String? ?? '-';
      final newHistory = history.sublist(0, history.length - 1);
      if (newHistory.isEmpty) {
        cancelledTitle = 'Batalkan Pembayaran Terakhir';
        cancelledSubtitle =
            'via ${_methodLabel(cancelledMethod, lastEntry['paymentSubOption'] as String?)}';
        cancelledAmountLabel = fmt.format(cancelledAmount);
        afterCancelLabel = 'Kembali ke hutang penuh ${fmt.format(total)}';
        rollbackFields = {
          'isPaid': false,
          'paidAt': null,
          'isBayarSebagian': false,
          'partialAmount': null,
          'remainingDebt': total.toInt(),
          'lastPaidAt': null,
          'paymentHistory': [],
          'updatedAt': FieldValue.serverTimestamp()
        };
      } else {
        final prevEntry = newHistory.last;
        final prevRemaining = (prevEntry['remaining'] ?? total) as num;
        final prevDate = prevEntry['date'] as Timestamp?;
        final newPartial = total.toInt() - prevRemaining.toInt();
        cancelledTitle = 'Batalkan Pembayaran Terakhir';
        cancelledSubtitle =
            'via ${_methodLabel(cancelledMethod, lastEntry['paymentSubOption'] as String?)}';
        cancelledAmountLabel = fmt.format(cancelledAmount);
        afterCancelLabel =
            'Sisa hutang kembali ke ${fmt.format(prevRemaining)}';
        rollbackFields = {
          'isPaid': false,
          'paidAt': null,
          'isBayarSebagian': true,
          'partialAmount': newPartial,
          'remainingDebt': prevRemaining.toInt(),
          'lastPaidAt': prevDate,
          'paymentHistory': newHistory,
          'updatedAt': FieldValue.serverTimestamp()
        };
      }
    }

    if (!mounted) return;
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _CancelPaymentSheet(
          title: cancelledTitle,
          subtitle: cancelledSubtitle,
          cancelledAmount: cancelledAmountLabel,
          afterCancelInfo: afterCancelLabel),
    );
    if (confirm != true) return;
    setState(() => _isUpdating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.transactionId)
          .update(rollbackFields);
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': 'cancel_last_payment',
        'transactionId': widget.transactionId,
        'description': history.isEmpty
            ? 'Membatalkan pembayaran penuh — kembali ke hutang penuh ${fmt.format(total)}'
            : 'Membatalkan pembayaran ${fmt.format((history.last['amount'] ?? 0) as num)} — sisa ${fmt.format(rollbackFields['remainingDebt'] as int)}',
        'timestamp': FieldValue.serverTimestamp()
      });
      final newHistory =
          rollbackFields['paymentHistory'] as List<Map<String, dynamic>>? ??
              [];
      setState(() {
        _isPaid = rollbackFields['isPaid'] as bool;
        _isBayarSebagian = rollbackFields['isBayarSebagian'] as bool;
        _remainingDebt = rollbackFields['remainingDebt'] as int;
        _partialAmount = rollbackFields['partialAmount'] as int?;
        _paidAt = null;
        _paymentHistory = newHistory;
        if (newHistory.isNotEmpty) {
          _paymentMethod = newHistory.last['paymentMethod'] as String?;
          _paymentSubOption = newHistory.last['paymentSubOption'] as String?;
        } else {
          _paymentMethod = null;
          _paymentSubOption = null;
        }
      });
      if (mounted) {
        AppNotification.warning('Dibatalkan', 'Pembayaran terakhir berhasil dibatalkan.');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.unexpectedError('Gagal membatalkan: $e');
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Transaksi'),
        actions: [
          IconButton(
              icon: const Icon(Icons.receipt_long_rounded),
              tooltip: 'Preview & Cetak Struk',
              onPressed: _showReceiptPreview),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: Color(0xFFE53935)),
            tooltip: 'Hapus Transaksi',
            onPressed: _isUpdating ? null : _deleteTransaction,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusBanner(),
          const SizedBox(height: 16),
          _buildDateRow(
            label: 'Tanggal Transaksi',
            date: _transactionDate,
            accentColor: const Color(0xFF2196F3),
            icon: Icons.calendar_today_rounded,
            onTap: _pickTransactionDate,
          ),
          if (_isPaid) ...[
            const SizedBox(height: 10),
            _buildDateRow(
              label: 'Tanggal Pembayaran',
              date: _paidAt,
              accentColor: const Color(0xFF4CAF50),
              icon: Icons.payments_rounded,
              onTap: _pickPaidAt,
              emptyHint: 'Ketuk untuk mengatur tanggal pembayaran',
            ),
          ],
          const SizedBox(height: 16),
          _buildCard(title: 'Informasi Pelanggan', children: [
            _buildEditableCustomerName(),
            _buildInfoRow(
                'No. Pelanggan',
                (_items.isNotEmpty &&
                        _items.first.customerNumber.isNotEmpty)
                    ? _items.first.customerNumber
                    : (widget.transactionData['customerNumber'] as String? ??
                                '')
                            .isNotEmpty
                        ? widget.transactionData['customerNumber'] as String
                        : '-'),
            if (!_isMultiItem && _hasAtasNama && _atasNama.isNotEmpty)
              _buildInfoRow('Atas Nama', _atasNama),
            if (_customerInfo != null && _customerInfo!.hasDebt) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pelanggan ini memiliki hutang: ${fmt.format(_customerInfo!.totalDebt)}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ]),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          _isMultiItem
              ? _buildMultiItemCard(fmt)
              : _buildSingleItemCard(),
          const SizedBox(height: 16),
          _buildCard(title: 'Rincian Pembayaran', children: [
            if (_isMultiItem) ...[
              ..._items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          '${item.productName}${item.quantity > 1 ? ' ×${item.quantity}' : ''}',
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF374151)),
                        ),
                      ),
                      Text(fmt.format(item.subtotalJual),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ]),
                  )),
              const Divider(height: 16),
            ] else ...[
              _buildInfoRow('Nominal',
                  fmt.format(widget.transactionData['nominal'] ?? 0)),
              if (_hasAdminFee)
                _buildInfoRow('Biaya Admin',
                    fmt.format(widget.transactionData['adminFee'] ?? 0)),
              const Divider(height: 16),
            ],
            _buildEditableTotalRow(fmt),
            if (_hasBeli) ...[
              const SizedBox(height: 8),
              _buildLabaRow(fmt),
            ],
            const Divider(height: 16),
            _buildEditablePaymentMethod(),
            if (_isBayarSebagian && _partialAmount != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      const Color(0xFFF44336).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFFF44336)
                          .withValues(alpha: 0.25)),
                ),
                child: Column(children: [
                  _splitRow('Dibayar sekarang',
                      fmt.format(_partialAmount),
                      const Color(0xFF4CAF50)),
                  const SizedBox(height: 6),
                  _splitRow(
                      'Sisa hutang',
                      fmt.format(_isPaid ? 0 : _remainingDebt),
                      _isPaid
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFF44336)),
                ]),
              ),
            ],
            if (_kembalian > 0) ...[
              const SizedBox(height: 12),
              _buildKembalianRow(fmt),
            ],
          ]),
          const SizedBox(height: 16),
          if (_paymentHistory.isNotEmpty) ...[
            _buildPaymentHistoryCard(fmt),
            const SizedBox(height: 16),
          ],
          if (!_isPaid && _isBayarSebagian) ...[
            _buildCard(title: 'Aksi Pembayaran', children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      _isUpdating ? null : _showBayarSebagianLagiSheet,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2196F3),
                    side: const BorderSide(
                        color: Color(0xFF2196F3), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Bayar Sebagian Lagi',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isUpdating ? null : _showLunasiSheet,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon:
                      const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(
                      'Lunasi Sisa (${fmt.format(_remainingDebt)})',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
            const SizedBox(height: 16),
          ],
          if (!_isPaid && !_isBayarSebagian)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isUpdating ? null : _markAsPaid,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50)),
                child: _isUpdating
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Tandai Sebagai Lunas'),
              ),
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Status Banner — FIXED: also shows isBayarSebagian state
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStatusBanner() {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  
    final Color gradientStart, gradientEnd;
    final String title, subtitle;
  
    if (_isPaid && _kembalian > 0) {
      // Lunas dengan kembalian
      gradientStart = const Color(0xFF00BCD4);
      gradientEnd = const Color(0xFF0097A7);
      title = 'LUNAS';
      subtitle = 'Kembalian: ${fmt.format(_kembalian)}';
    } else if (_isPaid) {
      gradientStart = const Color(0xFF4CAF50);
      gradientEnd = const Color(0xFF45a049);
      title = 'LUNAS';
      subtitle = 'Pembayaran telah diterima';
    } else if (_isBayarSebagian) {
      gradientStart = const Color(0xFFFF9800);
      gradientEnd = const Color(0xFFF57C00);
      title = 'BAYAR SEBAGIAN';
      subtitle = 'Ada sisa hutang yang belum dilunasi';
    } else {
      gradientStart = const Color(0xFFFF9800);
      gradientEnd = const Color(0xFFF57C00);
      title = 'BELUM LUNAS';
      subtitle = 'Menunggu pembayaran';
    }
  
    final icon = _isPaid
        ? (_kembalian > 0
            ? Icons.currency_exchange_rounded
            : Icons.check_circle)
        : Icons.pending;
  
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [gradientStart, gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 48),
        const SizedBox(width: 16),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 14)),
        ])),
        if (_isPaid || _isBayarSebagian)
          GestureDetector(
            onTap: _isUpdating ? null : _cancelPayment,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5)),
              ),
              child:
                  const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.undo_rounded, color: Colors.white, size: 14),
                SizedBox(width: 4),
                Text('Batalkan',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _buildKembalianRow(NumberFormat fmt) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF00BCD4).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFF00BCD4).withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_paidAmount != null) ...[
          _splitRow(
            'Uang Diterima',
            fmt.format(_paidAmount),
            const Color(0xFF2196F3),
          ),
          const SizedBox(height: 6),
          _splitRow(
            'Total Tagihan',
            fmt.format(_totalAmount),
            Colors.grey,
          ),
          const SizedBox(height: 6),
          const Divider(height: 8, color: Color(0xFFB2EBF2)),
          const SizedBox(height: 6),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF00BCD4).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: const Color(0xFF00BCD4).withValues(alpha: 0.45)),
          ),
          child: Row(children: [
            const Icon(Icons.currency_exchange_rounded,
                color: Color(0xFF00BCD4), size: 16),
            const SizedBox(width: 8),
            const Text(
              'KEMBALIAN',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00838F)),
            ),
            const Spacer(),
            Text(
              fmt.format(_kembalian),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00838F)),
            ),
          ]),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Single Item Card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSingleItemCard() {
    return _buildCard(title: 'Informasi Transaksi', children: [
      _buildInfoRow(
          'ID Transaksi', widget.transactionId.substring(0, 12)),
      _buildInfoRow('Produk', _items.first.productName),
      _buildInfoRow('Kategori', _items.first.category),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Multi Item Card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMultiItemCard(NumberFormat fmt) {
    return Container(
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
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Daftar Produk',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${_items.length} produk',
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF2196F3),
                    fontWeight: FontWeight.w600)),
          ),
        ]),
        const Divider(height: 24),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _items.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 16, indent: 44),
          itemBuilder: (_, i) => _buildItemRow(_items[i], i, fmt),
        ),
        const Divider(height: 20),
        _buildInfoRow(
            'ID Transaksi', widget.transactionId.substring(0, 12)),
      ]),
    );
  }

  Widget _buildItemRow(
      _TransactionItem item, int index, NumberFormat fmt) {
    final hasAtasNama = (item.category == 'Token Listrik' ||
            item.category == 'Tagihan') &&
        item.atasNama.isNotEmpty;
    final hasNumber = item.customerNumber.isNotEmpty;

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF2196F3).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text('${index + 1}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2196F3))),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(item.productName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
                Text(item.category,
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[500])),
              ]),
            ),
            Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
              if (item.quantity > 1)
                Text(
                  '${fmt.format(item.hargaJual)} ×${item.quantity}',
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              Text(fmt.format(item.subtotalJual),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2196F3))),
            ]),
          ]),
          if (hasNumber || hasAtasNama) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.15)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (hasNumber)
                  Row(children: [
                    Icon(Icons.tag,
                        size: 12, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: SelectableText(
                        item.customerNumber,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[600]),
                      ),
                    ),
                  ]),
                if (hasAtasNama) ...[
                  if (hasNumber) const SizedBox(height: 3),
                  Row(children: [
                    Icon(Icons.badge_outlined,
                        size: 12, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: SelectableText(
                        item.atasNama,
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[600]),
                      ),
                    ),
                  ]),
                ],
              ]),
            ),
          ],
          if (item.hargaBeli > 0) ...[
            const SizedBox(height: 6),
            Row(children: [
              Icon(
                item.laba >= 0
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                size: 12,
                color: item.laba >= 0
                    ? Colors.green[600]
                    : Colors.red[600],
              ),
              const SizedBox(width: 4),
              Text(
                'Laba: ${fmt.format(item.laba.abs())}${item.laba < 0 ? ' (rugi)' : ''}',
                style: TextStyle(
                    fontSize: 11,
                    color: item.laba >= 0
                        ? Colors.green[600]
                        : Colors.red[600],
                    fontWeight: FontWeight.w500),
              ),
            ]),
          ],
        ]),
      ),
    ]);
  }

  Widget _buildLabaRow(NumberFormat fmt) {
    final laba = _totalLaba;
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
          isProfit
              ? Icons.trending_up_rounded
              : Icons.trending_down_rounded,
          size: 14,
          color: isProfit ? Colors.green[700] : Colors.red[700],
        ),
        const SizedBox(width: 6),
        Text(
          'Laba: ${fmt.format(laba.abs())}${laba < 0 ? ' (rugi)' : ''}',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isProfit ? Colors.green[700] : Colors.red[700]),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Payment History Card — UPDATED with edit button per entry
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPaymentHistoryCard(NumberFormat fmt) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2))
          ]),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Riwayat Pembayaran',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_paymentHistory.length} transaksi',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF2196F3),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
        const Divider(height: 24),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _paymentHistory.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 16, indent: 52),
          itemBuilder: (_, i) {
            final entry = _paymentHistory[i];
            final amount = (entry['amount'] ?? 0) as num;
            final remaining = (entry['remaining'] ?? 0) as num;
            final methodKey = entry['paymentMethod'] as String? ?? '';
            final methodSub = entry['paymentSubOption'] as String?;
            final isPelunasan = entry['isPelunasan'] == true;
            final dateRaw = entry['date'];
            final date =
                dateRaw is Timestamp ? dateRaw.toDate() : null;
            final isLast = i == _paymentHistory.length - 1;
            final methodColor = _methodColor(methodKey);
            final methodIcon = _methodIcon(methodKey);
            final methodLabel = _methodLabel(methodKey, methodSub);
            return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Column(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isPelunasan
                        ? const Color(0xFF4CAF50).withValues(alpha: 0.15)
                        : methodColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: isPelunasan
                            ? const Color(0xFF4CAF50)
                            : methodColor,
                        width: 1.5),
                  ),
                  child: Center(
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isPelunasan
                                ? const Color(0xFF4CAF50)
                                : methodColor)),
                  ),
                ),
                if (!isLast)
                  Container(
                      width: 2,
                      height: 40,
                      color: Colors.grey.withValues(alpha: 0.2)),
              ]),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isPelunasan
                                            ? const Color(0xFF4CAF50).withValues(alpha: 0.1)
                                            : const Color(0xFF2196F3).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        isPelunasan ? 'Pelunasan' : 'Bayar Sebagian',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: isPelunasan
                                              ? const Color(0xFF4CAF50)
                                              : const Color(0xFF2196F3),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (isLast) ...[
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Container(
                                        padding:
                                            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Text(
                                          'Terakhir',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.orange,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(width: 8),

                            Flexible(
                              child: Text(
                                fmt.format(amount),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF111827),
                                ),
                              ),
                            ),

                            const SizedBox(width: 8),

                            GestureDetector(
                              onTap: () => _showEditHistoryEntrySheet(i),
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: const Icon(Icons.edit_rounded,
                                    size: 13, color: Color(0xFF2196F3)),
                              ),
                            ),
                          ],
                        ),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(methodIcon, size: 13, color: methodColor),
                  const SizedBox(width: 5),
                  Text(methodLabel.isNotEmpty ? methodLabel : '-',
                      style: TextStyle(
                          fontSize: 12,
                          color: methodColor,
                          fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 4),
                if (date != null)
                  Row(children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 12, color: Colors.grey[400]),
                    const SizedBox(width: 5),
                    Text(
                        DateFormat('dd MMM yyyy', 'id_ID').format(date),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[500])),
                  ]),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(
                    remaining == 0
                        ? Icons.check_circle_outline
                        : Icons.pending_outlined,
                    size: 12,
                    color: remaining == 0
                        ? const Color(0xFF4CAF50)
                        : Colors.orange,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    remaining == 0
                        ? 'Lunas'
                        : 'Sisa: ${fmt.format(remaining)}',
                    style: TextStyle(
                        fontSize: 11,
                        color: remaining == 0
                            ? const Color(0xFF4CAF50)
                            : Colors.orange,
                        fontWeight: FontWeight.w500),
                  ),
                ]),
              ])),
            ]);
          },
        ),
        const SizedBox(height: 16),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: (_isPaid
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFF2196F3))
                .withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: (_isPaid
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFF2196F3))
                    .withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Icon(
              _isPaid
                  ? Icons.check_circle_rounded
                  : Icons.payments_rounded,
              size: 16,
              color: _isPaid
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFF2196F3),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isPaid
                    ? 'Semua pembayaran telah dilunasi'
                    : 'Total dibayar: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(_partialAmount ?? 0)}  ·  Sisa: ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(_remainingDebt)}',
                style: TextStyle(
                    fontSize: 12,
                    color: _isPaid
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFF2196F3),
                    fontWeight: FontWeight.w500),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Edit History Entry Sheet — NEW
  // ─────────────────────────────────────────────────────────────────────────

  void _showEditHistoryEntrySheet(int historyIndex) {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final entry = Map<String, dynamic>.from(_paymentHistory[historyIndex]);

    final amountCtrl = TextEditingController(
        text: NumberFormat('#,##0', 'id_ID')
            .format((entry['amount'] as num?)?.toInt() ?? 0)
            .replaceAll(',', '.'));

    final rawDate = entry['date'];
    DateTime selectedDate =
        rawDate is Timestamp ? rawDate.toDate() : DateTime.now();
    String? selectedPayMethod = entry['paymentMethod'] as String?;
    String? selectedPaySubOption = entry['paymentSubOption'] as String?;
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
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Row(children: [
                  Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFF2196F3)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.edit_rounded,
                          color: Color(0xFF2196F3), size: 22)),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                    Text(
                        'Edit Pembayaran #${historyIndex + 1}',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827))),
                    const Text('Ubah jumlah, metode, atau tanggal',
                        style: TextStyle(
                            fontSize: 12, color: Color(0xFF9CA3AF))),
                  ])),
                ]),
                const SizedBox(height: 20),

                // ── Jumlah ─────────────────────────────────────────────
                TextFormField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_ThousandSeparatorFormatter()],
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
                            color: Color(0xFF2196F3), width: 2)),
                    errorText: () {
                      if (amountCtrl.text.isEmpty) return null;
                      final v =
                          int.tryParse(_rawInt(amountCtrl.text)) ?? 0;
                      if (v <= 0) return 'Masukkan jumlah valid';
                      // Total paid after edit must not exceed totalAmount
                      final otherPaid = _paymentHistory
                          .asMap()
                          .entries
                          .where((e) => e.key != historyIndex)
                          .fold<int>(
                              0,
                              (s, e) =>
                                  s +
                                  ((e.value['amount'] as num?)?.toInt() ??
                                      0));
                      if (otherPaid + v > _totalAmount) {
                        return 'Total melebihi tagihan (${fmt.format(_totalAmount)})';
                      }
                      return null;
                    }(),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Metode ─────────────────────────────────────────────
                _buildPaymentMethodSelector(
                    selectedKey: selectedPayMethod,
                    selectedSubOption: selectedPaySubOption,
                    onChanged: (key, sub) => setSheet(() {
                          selectedPayMethod = key;
                          selectedPaySubOption = sub;
                        }),
                    sheetCtx: sheetCtx),
                const SizedBox(height: 16),

                // ── Tanggal ────────────────────────────────────────────
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
                                    primary: Color(0xFF2196F3))),
                            child: child!));
                    if (picked != null) {
                      setSheet(() => selectedDate = picked);
                    }
                  },
                  child: _buildDatePickerRow(selectedDate,
                      const Color(0xFF2196F3), Icons.calendar_today_rounded),
                ),
                const SizedBox(height: 24),

                // ── Preview perubahan ──────────────────────────────────
                Builder(builder: (_) {
                  final newAmount =
                      int.tryParse(_rawInt(amountCtrl.text)) ?? 0;
                  if (newAmount <= 0) return const SizedBox.shrink();
                  final otherPaid = _paymentHistory
                      .asMap()
                      .entries
                      .where((e) => e.key != historyIndex)
                      .fold<int>(
                          0,
                          (s, e) =>
                              s +
                              ((e.value['amount'] as num?)?.toInt() ??
                                  0));
                  final newTotal = otherPaid + newAmount;
                  final newRemaining = _totalAmount - newTotal;
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: const Color(0xFF2196F3)
                            .withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFF2196F3)
                                .withValues(alpha: 0.2))),
                    child: Column(children: [
                      Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                        const Text('Total terbayar',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF374151))),
                        Text(fmt.format(newTotal),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4CAF50))),
                      ]),
                      const SizedBox(height: 6),
                      Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                        const Text('Sisa hutang',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF374151))),
                        Text(
                            fmt.format(
                                newRemaining < 0 ? 0 : newRemaining),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: newRemaining <= 0
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFFFF9800))),
                      ]),
                      if (newRemaining <= 0) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6)),
                          child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                            Icon(Icons.check_circle_outline,
                                size: 12, color: Color(0xFF4CAF50)),
                            SizedBox(width: 4),
                            Text('Status akan menjadi LUNAS',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF4CAF50),
                                    fontWeight: FontWeight.w600)),
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
                    onPressed: (isLoading || selectedPayMethod == null)
                        ? null
                        : () async {
                            final newAmount = int.tryParse(
                                    _rawInt(amountCtrl.text)) ??
                                0;
                            if (newAmount <= 0) return;

                            // Validate total
                            final otherPaid = _paymentHistory
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
                            if (otherPaid + newAmount > _totalAmount) {
                              return;
                            }

                            setSheet(() => isLoading = true);
                            Navigator.pop(sheetCtx);
                            await _saveEditedHistoryEntry(
                              index: historyIndex,
                              newAmount: newAmount,
                              newDate: selectedDate,
                              newMethod: selectedPayMethod!,
                              newSubOption: selectedPaySubOption,
                            );
                          },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: selectedPayMethod == null
                            ? Colors.grey
                            : const Color(0xFF2196F3),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
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

  /// Save edited history entry to Firestore and recalculate all derived fields.
  Future<void> _saveEditedHistoryEntry({
    required int index,
    required int newAmount,
    required DateTime newDate,
    required String newMethod,
    required String? newSubOption,
  }) async {
    setState(() => _isUpdating = true);
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    try {
      final user = FirebaseAuth.instance.currentUser;

      // Build updated history list
      final updatedHistory =
          List<Map<String, dynamic>>.from(_paymentHistory);
      final oldEntry = updatedHistory[index];

      updatedHistory[index] = {
        ...oldEntry,
        'amount': newAmount,
        'date': Timestamp.fromDate(newDate),
        'paymentMethod': newMethod,
        'paymentSubOption': newSubOption,
      };

      // Recalculate remaining for EACH entry in sequence
      int runningPaid = 0;
      for (int i = 0; i < updatedHistory.length; i++) {
        runningPaid +=
            (updatedHistory[i]['amount'] as num?)?.toInt() ?? 0;
        final rem = _totalAmount - runningPaid;
        updatedHistory[i] = {
          ...updatedHistory[i],
          'remaining': rem < 0 ? 0 : rem,
          // Mark as pelunasan if this is where it becomes fully paid
          if (rem <= 0) 'isPelunasan': true,
          if (rem > 0) 'isPelunasan': false,
        };
      }

      // Derive top-level fields from final state
      final totalPaid = updatedHistory.fold<int>(
          0, (s, h) => s + ((h['amount'] as num?)?.toInt() ?? 0));
      final newRemaining = _totalAmount - totalPaid;
      final newIsPaid = newRemaining <= 0;
      final newPartial = totalPaid;

      // lastPaidAt = date of last entry
      final lastEntryDate =
          updatedHistory.last['date'] as Timestamp?;

      final updateData = <String, dynamic>{
        'paymentHistory': updatedHistory,
        'partialAmount': newPartial,
        'remainingDebt': newRemaining < 0 ? 0 : newRemaining,
        'isPaid': newIsPaid,
        'isBayarSebagian': updatedHistory.isNotEmpty,
        'paymentMethod': updatedHistory.last['paymentMethod'],
        'paymentSubOption': updatedHistory.last['paymentSubOption'],
        'lastPaidAt': lastEntryDate,
        if (newIsPaid) 'paidAt': lastEntryDate,
        if (!newIsPaid) 'paidAt': null,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.transactionId)
          .update(updateData);

      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': 'edit_payment_history',
        'transactionId': widget.transactionId,
        'description':
            'Mengedit riwayat pembayaran #${index + 1}: ${fmt.format(newAmount)} via ${_methodLabel(newMethod, newSubOption)}',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update local state
      setState(() {
        _paymentHistory = updatedHistory;
        _partialAmount = newPartial;
        _remainingDebt = newRemaining < 0 ? 0 : newRemaining;
        _isPaid = newIsPaid;
        _isBayarSebagian = updatedHistory.isNotEmpty;
        _paymentMethod = updatedHistory.last['paymentMethod'] as String?;
        _paymentSubOption =
            updatedHistory.last['paymentSubOption'] as String?;
        if (newIsPaid && lastEntryDate != null) {
          _paidAt = lastEntryDate.toDate();
        } else {
          _paidAt = null;
        }
      });

      if (mounted) {
        AppNotification.updated('Riwayat pembayaran berhasil diperbarui.');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.unexpectedError('Gagal menyimpan: $e');
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Payment Method — FIXED save logic
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEditablePaymentMethod() {
    final isEmpty = _lastPaymentMethodKey.isEmpty;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
          Text('Metode',
              style:
                  TextStyle(fontSize: 14, color: Colors.grey[700])),
          GestureDetector(
              onTap: _showPaymentMethodSheet,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: isEmpty
                        ? Colors.grey.withValues(alpha: 0.1)
                        : _paymentMethodColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isEmpty
                            ? Colors.grey.withValues(alpha: 0.4)
                            : _paymentMethodColor
                                .withValues(alpha: 0.5))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!isEmpty) ...[
                    Icon(_lastMethodDef?.icon ?? Icons.payment,
                        size: 14, color: _paymentMethodColor),
                    const SizedBox(width: 6),
                  ],
                  Text(
                      isEmpty
                          ? 'Pilih metode'
                          : _paymentMethodDisplay,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isEmpty
                              ? Colors.grey
                              : _paymentMethodColor)),
                  const SizedBox(width: 6),
                  Icon(Icons.edit,
                      size: 13,
                      color: isEmpty
                          ? Colors.grey
                          : _paymentMethodColor),
                ]),
              )),
        ]));
  }

  void _showPaymentMethodSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentMethodSheet(
        currentKey: _paymentMethod,
        currentSubOption: _paymentSubOption,
        currentPartialAmount: _partialAmount,
        totalAmount: _totalAmount,
        onConfirm: (key, subOption, partialAmount, isHutangPenuh) async {
          setState(() {
            _paymentMethod = key;
            _paymentSubOption = subOption;
            _partialAmount = partialAmount;
            if (isHutangPenuh) {
              _isPaid = false;
              _isBayarSebagian = false;
              _remainingDebt = _totalAmount;
            } else if (partialAmount != null) {
              // Bayar sebagian mode
              _isBayarSebagian = true;
              _remainingDebt = _totalAmount - partialAmount;
              _isPaid = _remainingDebt <= 0;
            } else {
              // Full payment
              _isPaid = true;
              _isBayarSebagian = false;
              _remainingDebt = 0;
            }
          });
          await _savePaymentMethod(
              isHutangPenuh: isHutangPenuh,
              newPartialAmount: partialAmount);
        },
      ),
    );
  }

  Future<void> _savePaymentMethod({
    bool isHutangPenuh = false,
    int? newPartialAmount,
  }) async {
    setState(() => _isUpdating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final updateData = <String, dynamic>{
        'paymentMethod': isHutangPenuh ? null : _paymentMethod,
        'paymentSubOption':
            isHutangPenuh ? null : _paymentSubOption,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (isHutangPenuh) {
        // Revert to full debt
        updateData['isPaid'] = false;
        updateData['isBayarSebagian'] = false;
        updateData['partialAmount'] = null;
        updateData['remainingDebt'] = _totalAmount;
        updateData['paidAt'] = null;
      } else if (newPartialAmount != null) {
        // Partial payment
        final newRemaining = _totalAmount - newPartialAmount;
        updateData['isBayarSebagian'] = true;
        updateData['partialAmount'] = newPartialAmount;
        updateData['remainingDebt'] = newRemaining < 0 ? 0 : newRemaining;
        updateData['isPaid'] = newRemaining <= 0;
        if (newRemaining <= 0) {
          updateData['paidAt'] = FieldValue.serverTimestamp();
        }
      } else {
        // Full payment — no partial amount means fully paid
        updateData['isPaid'] = true;
        updateData['isBayarSebagian'] = false;
        updateData['partialAmount'] = _totalAmount;
        updateData['remainingDebt'] = 0;
        updateData['paidAt'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.transactionId)
          .update(updateData);

      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': 'update_payment_method',
        'transactionId': widget.transactionId,
        'description': isHutangPenuh
            ? 'Ditandai sebagai hutang penuh'
            : 'Mengubah metode pembayaran menjadi $_paymentMethodDisplay',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        AppNotification.updated(isHutangPenuh
          ? 'Ditandai sebagai hutang penuh.'
          : 'Metode pembayaran berhasil diperbarui.');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.unexpectedError('Gagal: $e');
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // ── Bayar Sebagian Lagi ───────────────────────────────────────────────────

  void _showBayarSebagianLagiSheet() {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
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
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Row(children: [
                  Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFF2196F3)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.payments_outlined,
                          color: Color(0xFF2196F3), size: 22)),
                  const SizedBox(width: 14),
                  const Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                    Text('Bayar Sebagian Lagi',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827))),
                    Text('Catat pembayaran parsial baru',
                        style: TextStyle(
                            fontSize: 12, color: Color(0xFF9CA3AF))),
                  ])),
                ]),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE3F2FD),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF2196F3)
                              .withValues(alpha: 0.25))),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                    const Text('Sisa hutang saat ini',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF374151))),
                    Text(fmt.format(_remainingDebt),
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2196F3))),
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
                    sheetCtx: sheetCtx),
                const SizedBox(height: 16),
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
                                    primary: Color(0xFF2196F3))),
                            child: child!));
                    if (picked != null) {
                      setSheet(() => selectedDate = picked);
                    }
                  },
                  child: _buildDatePickerRow(selectedDate,
                      const Color(0xFF2196F3), Icons.calendar_today_rounded),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_ThousandSeparatorFormatter()],
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
                        borderSide: const BorderSide(
                            color: Color(0xFF2196F3), width: 2)),
                    errorText: () {
                      if (ctrl.text.isEmpty) return null;
                      final v =
                          int.tryParse(_rawInt(ctrl.text)) ?? 0;
                      if (v <= 0) return 'Masukkan jumlah valid';
                      if (v >= _remainingDebt) {
                        return 'Gunakan "Lunasi Sisa" untuk melunasi penuh';
                      }
                      return null;
                    }(),
                  ),
                ),
                if (ctrl.text.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Builder(builder: (_) {
                    final v = int.tryParse(_rawInt(ctrl.text)) ?? 0;
                    final sisa = _remainingDebt - v;
                    if (v <= 0 || v >= _remainingDebt) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xFF22C55E)
                              .withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFF22C55E)
                                  .withValues(alpha: 0.3))),
                      child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                        const Text('Sisa setelah bayar',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF22C55E))),
                        Text(fmt.format(sisa.round()),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF22C55E))),
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
                            final v =
                                int.tryParse(_rawInt(ctrl.text)) ?? 0;
                            if (v > 0 && v < _remainingDebt) {
                              Navigator.pop(sheetCtx);
                              _processBayarSebagianLagi(
                                  v,
                                  selectedDate,
                                  selectedPayMethod!,
                                  selectedPaySubOption);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: selectedPayMethod == null
                            ? Colors.grey
                            : const Color(0xFF2196F3),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    child: Text(
                        selectedPayMethod == null
                            ? 'Pilih metode pembayaran dulu'
                            : 'Konfirmasi Pembayaran',
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

  void _showLunasiSheet() {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
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
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Row(children: [
                  Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.check_circle_outline,
                          color: Color(0xFF4CAF50), size: 22)),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                    const Text('Lunasi Sisa Hutang',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111827))),
                    Text('Total sisa: ${fmt.format(_remainingDebt)}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF9CA3AF))),
                  ])),
                ]),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50)
                          .withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFF4CAF50)
                              .withValues(alpha: 0.3))),
                  child: Row(children: [
                    const Icon(Icons.info_outline,
                        color: Color(0xFF4CAF50), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(
                            'Transaksi akan ditandai LUNAS setelah pelunasan sebesar ${fmt.format(_remainingDebt)}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF4CAF50),
                                fontWeight: FontWeight.w500))),
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
                    sheetCtx: sheetCtx,
                    excludeBayarSebagian: true),
                const SizedBox(height: 16),
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
                                    primary: Color(0xFF4CAF50))),
                            child: child!));
                    if (picked != null) {
                      setSheet(() => selectedDate = picked);
                    }
                  },
                  child: _buildDatePickerRow(selectedDate,
                      const Color(0xFF4CAF50), Icons.payments_rounded),
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
                            _processLunasiSisa(selectedDate,
                                selectedPayMethod!, selectedPaySubOption);
                          },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: selectedPayMethod == null
                            ? Colors.grey
                            : const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    child: Text(
                        selectedPayMethod == null
                            ? 'Pilih metode pembayaran dulu'
                            : 'Konfirmasi Pelunasan',
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

  Widget _buildPaymentMethodSelector({
    required String? selectedKey,
    required String? selectedSubOption,
    required void Function(String key, String? sub) onChanged,
    required BuildContext sheetCtx,
    bool excludeBayarSebagian = false,
  }) {
    final methods =
        _paymentMethods.where((m) => m.key != 'bayar_sebagian').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Metode Pembayaran',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151))),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.8,
        children: methods
            .map((method) => _buildPayMethodTile(method,
                selectedKey == method.key, () => onChanged(method.key, null)))
            .toList(),
      ),
      if (selectedKey == 'E-Wallet') ...[
        const SizedBox(height: 12),
        const Text('Pilih Platform E-Wallet',
            style: TextStyle(
                fontSize: 12,
                color: Color(0xFF374151),
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: (_paymentMethods
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
                    onSelected: (_) => onChanged('E-Wallet', sub),
                  ))
              .toList(),
        ),
      ],
      if (selectedKey != null && selectedKey != 'E-Wallet') ...[
        const SizedBox(height: 8),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: methods
                  .firstWhere((m) => m.key == selectedKey,
                      orElse: () => methods.first)
                  .color
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Icon(Icons.check_circle_rounded,
                color: methods
                    .firstWhere((m) => m.key == selectedKey,
                        orElse: () => methods.first)
                    .color,
                size: 14),
            const SizedBox(width: 8),
            Text(
                'Metode: ${methods.firstWhere((m) => m.key == selectedKey, orElse: () => methods.first).label}',
                style: TextStyle(
                    fontSize: 12,
                    color: methods
                        .firstWhere((m) => m.key == selectedKey,
                            orElse: () => methods.first)
                        .color,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ],
    ]);
  }

  Widget _buildPayMethodTile(
      PaymentMethod method, bool isSelected, VoidCallback onTap) {
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
                  width: isSelected ? 2 : 1)),
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
                        color:
                            isSelected ? method.color : Colors.black87),
                    overflow: TextOverflow.ellipsis)),
            if (isSelected)
              Icon(Icons.check_circle, color: method.color, size: 12),
          ]),
        ));
  }

  Widget _buildDatePickerRow(
      DateTime date, Color color, IconData icon) {
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: color.withValues(alpha: 0.4), width: 1.5)),
      child: Row(children: [
        Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 16)),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
          const Text('Tanggal dipilih',
              style:
                  TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
          const SizedBox(height: 2),
          Text(
              DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(date),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827)),
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
                      fontWeight: FontWeight.w600)))
        else
          Icon(Icons.edit_calendar_rounded, color: color, size: 16),
      ]),
    );
  }

  Future<void> _processBayarSebagianLagi(int bayar, DateTime paymentDate,
      String payMethod, String? paySubOption) async {
    setState(() => _isUpdating = true);
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final docRef = FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.transactionId);
      final snap = await docRef.get();
      final data = snap.data()!;
      final currentRemaining = (data['remainingDebt'] ?? 0) as num;
      final newRemaining = currentRemaining.toInt() - bayar;
      final oldPartial = (data['partialAmount'] ?? 0) as num;
      final newPartial = oldPartial.toInt() + bayar;
      final List<Map<String, dynamic>> paymentHistory =
          List<Map<String, dynamic>>.from(
              data['paymentHistory'] ?? []);
      paymentHistory.add({
        'amount': bayar,
        'date': Timestamp.fromDate(paymentDate),
        'remaining': newRemaining,
        'paymentMethod': payMethod,
        'paymentSubOption': paySubOption
      });
      await docRef.update({
        'isBayarSebagian': true,
        'partialAmount': newPartial,
        'remainingDebt': newRemaining,
        'isPaid': false,
        'lastPaidAt': Timestamp.fromDate(paymentDate),
        'paymentHistory': paymentHistory,
        'updatedAt': FieldValue.serverTimestamp()
      });
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': 'partial_payment_again',
        'transactionId': widget.transactionId,
        'description':
            'Bayar sebagian lagi ${fmt.format(bayar)}, sisa ${fmt.format(newRemaining)}',
        'paymentMethod': payMethod,
        'paymentSubOption': paySubOption,
        'paidAt': Timestamp.fromDate(paymentDate),
        'timestamp': FieldValue.serverTimestamp()
      });
      setState(() {
        _partialAmount = newPartial;
        _remainingDebt = newRemaining;
        _paymentHistory = paymentHistory;
        _paymentMethod = payMethod;
        _paymentSubOption = paySubOption;
      });
      if (mounted) {
        AppNotification.partialPaid('Sisa hutang: ${fmt.format(newRemaining)}');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.unexpectedError('Gagal memproses: $e');
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _processLunasiSisa(DateTime paymentDate, String payMethod,
      String? paySubOption) async {
    setState(() => _isUpdating = true);
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final docRef = FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.transactionId);
      final snap = await docRef.get();
      final data = snap.data()!;
      final currentRemaining = (data['remainingDebt'] ?? 0) as num;
      final oldPartial = (data['partialAmount'] ?? 0) as num;
      final newPartial =
          oldPartial.toInt() + currentRemaining.toInt();
      final List<Map<String, dynamic>> paymentHistory =
          List<Map<String, dynamic>>.from(
              data['paymentHistory'] ?? []);
      paymentHistory.add({
        'amount': currentRemaining.toInt(),
        'date': Timestamp.fromDate(paymentDate),
        'remaining': 0,
        'paymentMethod': payMethod,
        'paymentSubOption': paySubOption,
        'isPelunasan': true
      });
      await docRef.update({
        'isBayarSebagian': true,
        'partialAmount': newPartial,
        'remainingDebt': 0,
        'isPaid': true,
        'paidAt': Timestamp.fromDate(paymentDate),
        'lastPaidAt': Timestamp.fromDate(paymentDate),
        'paymentHistory': paymentHistory,
        'updatedAt': FieldValue.serverTimestamp()
      });
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': 'settle_debt',
        'transactionId': widget.transactionId,
        'description':
            'Melunasi sisa hutang ${fmt.format(currentRemaining.toInt())} — LUNAS',
        'paymentMethod': payMethod,
        'paymentSubOption': paySubOption,
        'paidAt': Timestamp.fromDate(paymentDate),
        'timestamp': FieldValue.serverTimestamp()
      });
      setState(() {
        _isPaid = true;
        _isBayarSebagian = true;
        _remainingDebt = 0;
        _partialAmount = newPartial;
        _paidAt = paymentDate;
        _paymentHistory = paymentHistory;
        _paymentMethod = payMethod;
        _paymentSubOption = paySubOption;
      });
      if (mounted) {
        AppNotification.paid('Hutang telah dilunasi sepenuhnya.');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.unexpectedError('Gagal memproses: $e');
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Widget _buildDateRow({
    required String label,
    required DateTime? date,
    required Color accentColor,
    required IconData icon,
    required VoidCallback onTap,
    String? emptyHint,
  }) {
    final isToday =
        date != null && DateUtils.isSameDay(date, DateTime.now());
    return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: accentColor.withValues(alpha: 0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ]),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: accentColor, size: 20)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Text(label,
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey[600])),
              const SizedBox(height: 3),
              date != null
                  ? Text(
                      DateFormat('EEEE, dd MMMM yyyy', 'id_ID')
                          .format(date),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827)))
                  : Text(emptyHint ?? 'Belum diatur',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[400],
                          fontStyle: FontStyle.italic)),
            ])),
            if (isToday)
              Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('Hari ini',
                      style: TextStyle(
                          fontSize: 10,
                          color: accentColor,
                          fontWeight: FontWeight.w600)))
            else
              Icon(Icons.edit_calendar_rounded,
                  color: accentColor, size: 18),
          ]),
        ));
  }

  Widget _splitRow(String label, String value, Color color) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label,
            style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w500)),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.bold)),
      ]);

  Widget _buildEditableCustomerName() {
    final isEmpty = _customerName.trim().isEmpty;
    return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
          Text('Nama Pelanggan',
              style:
                  TextStyle(fontSize: 14, color: Colors.grey[700])),
          GestureDetector(
              onTap: _showCustomerNameSheet,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: isEmpty
                        ? Colors.grey.withValues(alpha: 0.1)
                        : Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isEmpty
                            ? Colors.grey.withValues(alpha: 0.4)
                            : Colors.teal.withValues(alpha: 0.5))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.person_outline,
                      size: 14,
                      color: isEmpty ? Colors.grey : Colors.teal),
                  const SizedBox(width: 6),
                  Text(isEmpty ? 'Tambah nama' : _customerName,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isEmpty ? Colors.grey : Colors.teal)),
                  const SizedBox(width: 6),
                  Icon(Icons.edit,
                      size: 13,
                      color: isEmpty ? Colors.grey : Colors.teal),
                ]),
              )),
        ]));
  }

  void _showCustomerNameSheet() async {
    final allCustomers = await _customerService.getAll();
    if (!mounted) return;
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _CustomerNameSheet(
              currentName: _customerName,
              customerNumber:
                  widget.transactionData['customerNumber'] as String? ??
                      '',
              allCustomers: allCustomers,
              onConfirm: (name) async {
                setState(() => _customerName = name);
                await _saveCustomerName(name);
              },
            ));
  }

  Future<void> _saveCustomerName(String name) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final number =
          widget.transactionData['customerNumber'] as String? ?? '';
      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.transactionId)
          .update({
        'customerName': name.trim(),
        'updatedAt': FieldValue.serverTimestamp()
      });
      if (number.isNotEmpty && name.trim().isNotEmpty) {
        await _customerService.upsert(number: number, name: name.trim());
        await _loadCustomerInfo();
      }
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': 'update_customer_name',
        'transactionId': widget.transactionId,
        'description': 'Mengubah nama pelanggan menjadi $name',
        'timestamp': FieldValue.serverTimestamp()
      });
      if (mounted) {
        AppNotification.updated('Nama pelanggan berhasil diperbarui.');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.unexpectedError('Gagal menyimpan nama: $e');
      }
    }
  }

  Widget _buildEditableTotalRow(NumberFormat fmt) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
          const Text('TOTAL',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2196F3))),
          GestureDetector(
            onTap: _showEditTotalSheet,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(fmt.format(_totalAmount),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2196F3))),
              const SizedBox(width: 6),
              Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: const Color(0xFF2196F3)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.edit,
                      size: 14, color: Color(0xFF2196F3))),
            ]),
          ),
        ]));
  }

  void _showEditTotalSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditTotalSheet(
          currentTotal: _totalAmount,
          onConfirm: (val) {
            setState(() => _totalAmount = val);
            _saveTotalAmount();
          }),
    );
  }

  Future<void> _saveTotalAmount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.transactionId)
          .update({
        'totalAmount': _totalAmount,
        'updatedAt': FieldValue.serverTimestamp()
      });
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': 'update_total_amount',
        'transactionId': widget.transactionId,
        'description': 'Mengubah total menjadi $_totalAmount',
        'timestamp': FieldValue.serverTimestamp()
      });
      if (mounted) {
        AppNotification.updated('Total tagihan berhasil diperbarui.');
      }
    } catch (e) {
      if (mounted) {
        AppNotification.unexpectedError('Gagal: $e');
      }
    }
  }

  Future<void> _markAsPaid() async {
    DateTime paidDate = DateTime.now();
    String? selectedPayMethod;
    String? selectedPaySubOption;
    await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetRootCtx) => StatefulBuilder(
            builder: (sheetCtx, setSheet) => Padding(
                  padding: EdgeInsets.only(
                      bottom:
                          MediaQuery.of(sheetCtx).viewInsets.bottom),
                  child: Container(
                    decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24))),
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                    child: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          Center(
                              child: Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      borderRadius:
                                          BorderRadius.circular(2)))),
                          const SizedBox(height: 20),
                          Row(children: [
                            Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                    color: const Color(0xFF4CAF50)
                                        .withValues(alpha: 0.1),
                                    borderRadius:
                                        BorderRadius.circular(12)),
                                child: const Icon(
                                    Icons.check_circle_outline,
                                    color: Color(0xFF4CAF50),
                                    size: 22)),
                            const SizedBox(width: 14),
                            const Text('Tandai Sebagai Lunas',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF111827))),
                          ]),
                          const SizedBox(height: 20),
                          _buildPaymentMethodSelector(
                              selectedKey: selectedPayMethod,
                              selectedSubOption: selectedPaySubOption,
                              onChanged: (key, sub) => setSheet(() {
                                    selectedPayMethod = key;
                                    selectedPaySubOption = sub;
                                  }),
                              sheetCtx: sheetCtx,
                              excludeBayarSebagian: true),
                          const SizedBox(height: 16),
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
                                                  primary: Color(
                                                      0xFF4CAF50))),
                                      child: child!));
                              if (picked != null) {
                                setSheet(() => paidDate = picked);
                              }
                            },
                            child: _buildDatePickerRow(
                                paidDate,
                                const Color(0xFF4CAF50),
                                Icons.payments_rounded),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: selectedPayMethod == null
                                  ? null
                                  : () => Navigator.pop(sheetCtx),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      selectedPayMethod == null
                                          ? Colors.grey
                                          : const Color(0xFF4CAF50),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14))),
                              child: Text(
                                  selectedPayMethod == null
                                      ? 'Pilih metode pembayaran dulu'
                                      : 'Konfirmasi Lunas',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ])),
                  ),
                )));
    if (selectedPayMethod == null) return;
    if (!mounted) return;
    setState(() => _isUpdating = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.transactionId)
          .update({
        'isPaid': true,
        'isBayarSebagian': false,
        'remainingDebt': 0,
        'partialAmount': _totalAmount,
        'paidAt': Timestamp.fromDate(paidDate),
        'paymentMethod': selectedPayMethod,
        'paymentSubOption': selectedPaySubOption,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      setState(() {
        _isPaid = true;
        _isBayarSebagian = false;
        _remainingDebt = 0;
        _partialAmount = _totalAmount;
        _paidAt = paidDate;
        _paymentMethod = selectedPayMethod;
        _paymentSubOption = selectedPaySubOption;
      });
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': user?.uid,
        'userEmail': user?.email,
        'action': 'mark_as_paid',
        'transactionId': widget.transactionId,
        'description': 'Menandai transaksi sebagai lunas',
        'paymentMethod': selectedPayMethod,
        'paymentSubOption': selectedPaySubOption,
        'paidAt': Timestamp.fromDate(paidDate),
        'timestamp': FieldValue.serverTimestamp()
      });
      if (mounted) {
        Get.back(result: true);
        AppNotification.paid('Transaksi berhasil ditandai sebagai lunas.');

      }
    } catch (e) {
      if (mounted) {
        AppNotification.unexpectedError('Gagal: $e');
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Widget _buildCard(
          {required String title, required List<Widget> children}) =>
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
            ]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
          const Divider(height: 24),
          ...children
        ]),
      );

  Widget _buildInfoRow(String label, String value,
          {bool isTotal = false}) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            Text(label,
                style: TextStyle(
                    fontSize: isTotal ? 16 : 14,
                    fontWeight: isTotal
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isTotal
                        ? const Color(0xFF2196F3)
                        : Colors.grey[700])),
            Flexible(
                child: SelectableText(value,
                    style: TextStyle(
                        fontSize: isTotal ? 18 : 14,
                        fontWeight:
                            isTotal ? FontWeight.bold : FontWeight.w600,
                        color: isTotal
                            ? const Color(0xFF2196F3)
                            : Colors.black),
                    textAlign: TextAlign.end)),
          ]));
}

// ─── Delete Transaction Sheet ─────────────────────────────────────────────────
class _DeleteTransactionSheet extends StatelessWidget {
  final String productName;
  final int totalAmount;

  const _DeleteTransactionSheet(
      {required this.productName, required this.totalAmount});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(28))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 28),
        Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFFEF9A9A), width: 1.5)),
            child: const Icon(Icons.delete_forever_rounded,
                color: Color(0xFFE53935), size: 32)),
        const SizedBox(height: 16),
        const Text('Hapus Transaksi',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827)),
            textAlign: TextAlign.center),
        const SizedBox(height: 6),
        const Text('Tindakan ini tidak dapat dibatalkan',
            style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
              color: const Color(0xFFFFF3F3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFCDD2))),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              const Text('Produk',
                  style: TextStyle(
                      fontSize: 13, color: Color(0xFF6B7280))),
              Flexible(
                  child: Text(productName,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF111827)),
                      textAlign: TextAlign.end)),
            ]),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              const Text('Total',
                  style: TextStyle(
                      fontSize: 13, color: Color(0xFF6B7280))),
              Text(fmt.format(totalAmount),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE53935))),
            ]),
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFFFCDD2)),
            const SizedBox(height: 10),
            const Row(children: [
              Icon(Icons.warning_amber_rounded,
                  size: 14, color: Color(0xFF9CA3AF)),
              SizedBox(width: 8),
              Expanded(
                  child: Text(
                      'Data transaksi akan dihapus permanen dari sistem',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF374151)))),
            ]),
          ]),
        ),
        const SizedBox(height: 28),
        Row(children: [
          Expanded(
              child: OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF374151),
                side: const BorderSide(
                    color: Color(0xFFD1D5DB), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            child: const Text('Batal',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          )),
          const SizedBox(width: 12),
          Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.delete_forever_rounded, size: 16),
                  SizedBox(width: 8),
                  Text('Ya, Hapus',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ]),
              )),
        ]),
      ]),
    );
  }
}

// ─── Cancel Payment Sheet ─────────────────────────────────────────────────────
class _CancelPaymentSheet extends StatelessWidget {
  final String title, subtitle, cancelledAmount, afterCancelInfo;

  const _CancelPaymentSheet(
      {required this.title,
      required this.subtitle,
      required this.cancelledAmount,
      required this.afterCancelInfo});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(28))),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 28),
        Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                shape: BoxShape.circle,
                border: Border.all(
                    color: const Color(0xFFEF9A9A), width: 1.5)),
            child: const Icon(Icons.undo_rounded,
                color: Color(0xFFE53935), size: 32)),
        const SizedBox(height: 16),
        Text(title,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827)),
            textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(subtitle,
            style: const TextStyle(
                fontSize: 13, color: Color(0xFF6B7280)),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
              color: const Color(0xFFFFF3F3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFCDD2))),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              const Text('Pembayaran dibatalkan',
                  style: TextStyle(
                      fontSize: 13, color: Color(0xFF6B7280))),
              Text(cancelledAmount,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE53935))),
            ]),
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFFFCDD2)),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.arrow_forward_rounded,
                  size: 14, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(afterCancelInfo,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF374151)))),
            ]),
          ]),
        ),
        const SizedBox(height: 28),
        Row(children: [
          Expanded(
              child: OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF374151),
                side: const BorderSide(
                    color: Color(0xFFD1D5DB), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            child: const Text('Tidak, Kembali',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          )),
          const SizedBox(width: 12),
          Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.undo_rounded, size: 16),
                  SizedBox(width: 8),
                  Text('Ya, Batalkan',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ]),
              )),
        ]),
      ]),
    );
  }
}

// ─── Edit Total Sheet ─────────────────────────────────────────────────────────
class _EditTotalSheet extends StatefulWidget {
  final int currentTotal;
  final void Function(int) onConfirm;

  const _EditTotalSheet(
      {required this.currentTotal, required this.onConfirm});

  @override
  State<_EditTotalSheet> createState() => _EditTotalSheetState();
}

class _EditTotalSheetState extends State<_EditTotalSheet> {
  late TextEditingController _ctrl;
  final _fmt = NumberFormat.currency(
      locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: NumberFormat('#,##0', 'id_ID')
            .format(widget.currentTotal)
            .replaceAll(',', '.'));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int? get _parsedValue => int.tryParse(_rawInt(_ctrl.text));
  bool get _isValid => _parsedValue != null && _parsedValue! > 0;
  bool get _isChanged =>
      _parsedValue != null && _parsedValue != widget.currentTotal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(28))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),
            Row(children: [
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFF2196F3)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.edit_rounded,
                      color: Color(0xFF2196F3), size: 20)),
              const SizedBox(width: 14),
              const Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                Text('Edit Harga Jual',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827))),
                Text('Ubah total tagihan pelanggan',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFF9CA3AF))),
              ])),
            ]),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0))),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                const Text('Harga saat ini',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFF9CA3AF))),
                Text(_fmt.format(widget.currentTotal),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151))),
              ]),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [_ThousandSeparatorFormatter()],
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827)),
              decoration: InputDecoration(
                labelText: 'Harga Jual Baru',
                prefixText: 'Rp ',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                        color: Color(0xFF2196F3), width: 2)),
                errorText: () {
                  if (_ctrl.text.isEmpty) return null;
                  final v = int.tryParse(_rawInt(_ctrl.text));
                  if (v == null || v <= 0) {
                    return 'Masukkan nominal yang valid';
                  }
                  return null;
                }(),
              ),
            ),
            if (_isChanged && _isValid) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: const Color(0xFF90CAF9))),
                child: Row(children: [
                  const Icon(Icons.arrow_circle_up_rounded,
                      size: 15, color: Color(0xFF1976D2)),
                  const SizedBox(width: 8),
                  Text(
                      'Akan diperbarui ke ${_fmt.format(_parsedValue)}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1565C0),
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
            const SizedBox(height: 28),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF374151),
                    side: const BorderSide(
                        color: Color(0xFFD1D5DB), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                child: const Text('Batal',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (_isValid && _isChanged)
                        ? () {
                            Navigator.pop(context);
                            widget.onConfirm(_parsedValue!);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2196F3),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            const Color(0xFFE5E7EB),
                        elevation: 0,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Icon(Icons.check_rounded, size: 16),
                      SizedBox(width: 8),
                      Text('Simpan Perubahan',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ]),
                  )),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ─── Customer Name Sheet ──────────────────────────────────────────────────────
class _CustomerNameSheet extends StatefulWidget {
  final String currentName, customerNumber;
  final List<CustomerModel> allCustomers;
  final void Function(String) onConfirm;

  const _CustomerNameSheet(
      {required this.currentName,
      required this.customerNumber,
      required this.allCustomers,
      required this.onConfirm});

  @override
  State<_CustomerNameSheet> createState() => _CustomerNameSheetState();
}

class _CustomerNameSheetState extends State<_CustomerNameSheet> {
  late TextEditingController _ctrl;
  List<CustomerModel> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentName);
    _suggestions = widget.allCustomers;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onSearch(String q) => setState(() {
        _suggestions = q.isEmpty
            ? widget.allCustomers
            : widget.allCustomers
                .where((c) =>
                    c.name.toLowerCase().contains(q.toLowerCase()) ||
                    c.number.contains(q))
                .toList();
      });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // Batasi tinggi maksimal sheet agar tidak overflow
      constraints: BoxConstraints(
        maxHeight: screenHeight * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header & input field (tidak ikut scroll) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Nama Pelanggan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ketik nama baru atau pilih dari daftar.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  onChanged: _onSearch,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.person_outline),
                    labelText: 'Nama Pelanggan',
                    border: const OutlineInputBorder(),
                    suffixIcon: _ctrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _ctrl.clear();
                              _onSearch('');
                            },
                          )
                        : null,
                  ),
                ),
                if (_suggestions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _ctrl.text.isEmpty
                          ? 'Pelanggan terdaftar:'
                          : 'Hasil pencarian:',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),

          // ── Suggestions list (scrollable, tinggi dinamis) ──
          if (_suggestions.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(
                // Kurangi space untuk keyboard + header + tombol
                maxHeight: (screenHeight * 0.85) -
                    bottomInset -
                    280, // 280 = estimasi tinggi header + field + tombol
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = _suggestions[i];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.teal.withValues(alpha: 0.15),
                      child: Text(
                        c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Colors.teal,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    title: Text(
                      c.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    subtitle: Text(
                      c.number,
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () => setState(() {
                      _ctrl.text = c.name;
                      _onSearch(c.name);
                    }),
                  );
                },
              ),
            ),

          // ── Tombol simpan + padding keyboard ──
          Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _ctrl.text.trim().isEmpty
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.onConfirm(_ctrl.text.trim());
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                ),
                child: const Text('Simpan Nama Pelanggan'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Payment Method Sheet ─────────────────────────────────────────────────────
class _PaymentMethodSheet extends StatefulWidget {
  final String? currentKey, currentSubOption;
  final int? currentPartialAmount;
  final int totalAmount;
  final void Function(String?, String?, int?, bool isHutangPenuh)
      onConfirm;

  const _PaymentMethodSheet(
      {required this.currentKey,
      required this.currentSubOption,
      required this.currentPartialAmount,
      required this.totalAmount,
      required this.onConfirm});

  @override
  State<_PaymentMethodSheet> createState() =>
      _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends State<_PaymentMethodSheet> {
  late String? _selectedKey;
  late String? _selectedSubOption;
  bool _isHutangPenuh = false;
  final TextEditingController _paidCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedKey = widget.currentKey;
    _selectedSubOption = widget.currentSubOption;
    if (widget.currentPartialAmount != null) {
      final n = widget.currentPartialAmount!;
      _paidCtrl.text = NumberFormat('#,##0', 'id_ID')
          .format(n)
          .replaceAll(',', '.');
    }
  }

  @override
  void dispose() {
    _paidCtrl.dispose();
    super.dispose();
  }

  PaymentMethod? get _selectedDef =>
      _paymentMethods.where((m) => m.key == _selectedKey).firstOrNull;

  int get _paidAmount {
    final raw = _rawInt(_paidCtrl.text);
    if (raw.isEmpty) return widget.totalAmount;
    return int.tryParse(raw) ?? 0;
  }

  int get _sisaHutang {
    final sisa = widget.totalAmount - _paidAmount;
    return sisa > 0 ? sisa : 0;
  }

  bool get _isBayarSebagianMode =>
      _sisaHutang > 0 && _paidAmount > 0 && !_isHutangPenuh;

  bool get _isValid {
    if (_isHutangPenuh) return true;
    if (_selectedKey == null) return false;
    if (_selectedKey == 'E-Wallet' && _selectedSubOption == null) {
      return false;
    }
    return true;
  }

  void _setHutangPenuh() => setState(() {
        _isHutangPenuh = true;
        _selectedKey = null;
        _selectedSubOption = null;
        _paidCtrl.text = '0';
      });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            const Text('Metode & Jumlah Pembayaran',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: const Color(0xFF2196F3)
                          .withValues(alpha: 0.2))),
              child: Row(children: [
                const Icon(Icons.info_outline,
                    color: Color(0xFF2196F3), size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        'Kosongkan jika bayar penuh (${fmt.format(widget.totalAmount)}). Isi sebagian → sisa jadi hutang.',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF2196F3),
                            fontWeight: FontWeight.w500))),
              ]),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _paidCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [_ThousandSeparatorFormatter()],
              onChanged: (_) => setState(() =>
                  _isHutangPenuh =
                      _paidAmount == 0 && _paidCtrl.text.isNotEmpty),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: 'Jumlah Dibayar',
                hintText: 'Kosongkan = bayar penuh',
                prefixText: 'Rp ',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: Color(0xFF2196F3), width: 2)),
                errorText: () {
                  if (_paidCtrl.text.trim().isEmpty) return null;
                  final v =
                      int.tryParse(_rawInt(_paidCtrl.text)) ?? 0;
                  if (v < 0) return 'Jumlah tidak boleh negatif';
                  if (v > widget.totalAmount) {
                    return 'Melebihi total tagihan';
                  }
                  return null;
                }(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isHutangPenuh ? null : _setHutangPenuh,
                icon: Icon(Icons.pending_outlined,
                    size: 18,
                    color: _isHutangPenuh
                        ? Colors.grey
                        : const Color(0xFFF44336)),
                label: Text('Tandai sebagai Hutang Penuh',
                    style: TextStyle(
                        color: _isHutangPenuh
                            ? Colors.grey
                            : const Color(0xFFF44336),
                        fontWeight: FontWeight.w600)),
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
            if (_isHutangPenuh) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFF44336)
                        .withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFF44336)
                            .withValues(alpha: 0.3))),
                child: Row(children: [
                  const Icon(Icons.pending_outlined,
                      color: Color(0xFFF44336), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'Transaksi akan ditandai sebagai hutang penuh ${fmt.format(widget.totalAmount)}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFF44336),
                              fontWeight: FontWeight.w500))),
                ]),
              ),
            ] else if (_isBayarSebagianMode &&
                _paidCtrl.text.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFFF9800)
                        .withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFFF9800)
                            .withValues(alpha: 0.3))),
                child: Column(children: [
                  Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                    const Text('Dibayar',
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4CAF50),
                            fontWeight: FontWeight.w500)),
                    Text(fmt.format(_paidAmount),
                        style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF4CAF50),
                            fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 6),
                  Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                    const Text('Sisa hutang',
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFFFF9800),
                            fontWeight: FontWeight.w500)),
                    Text(fmt.format(_sisaHutang),
                        style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFFF9800),
                            fontWeight: FontWeight.bold)),
                  ]),
                ]),
              ),
            ],
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _isHutangPenuh ? 0.35 : 1.0,
              child: IgnorePointer(
                ignoring: _isHutangPenuh,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Metode Pembayaran',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 2.8,
                    children:
                        _paymentMethods.map(_buildMethodTile).toList(),
                  ),
                  if (_selectedKey == 'E-Wallet') ...[
                    const SizedBox(height: 16),
                    const Text('Pilih Platform',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: (_selectedDef?.subOptions ?? [])
                            .map((sub) => ChoiceChip(
                                  label: Text(sub,
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: _selectedSubOption ==
                                                  sub
                                              ? Colors.white
                                              : Colors.black)),
                                  selected: _selectedSubOption == sub,
                                  selectedColor:
                                      const Color(0xFFFF9800),
                                  onSelected: (_) => setState(
                                      () => _selectedSubOption = sub),
                                ))
                            .toList()),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isValid
                    ? () {
                        Navigator.pop(context);
                        final partial =
                            _isBayarSebagianMode ? _paidAmount : null;
                        widget.onConfirm(
                            _isHutangPenuh ? null : _selectedKey,
                            _selectedSubOption,
                            partial,
                            _isHutangPenuh);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _isHutangPenuh
                        ? const Color(0xFFF44336)
                        : const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: Text(
                    _isHutangPenuh
                        ? 'Simpan sebagai Hutang Penuh'
                        : 'Simpan Metode Pembayaran',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildMethodTile(PaymentMethod method) {
    final isSelected = _selectedKey == method.key;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedKey = method.key;
        _selectedSubOption = null;
        _isHutangPenuh = false;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: isSelected
                ? method.color.withValues(alpha: 0.12)
                : Colors.grey.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isSelected
                    ? method.color
                    : Colors.grey.withValues(alpha: 0.3),
                width: isSelected ? 2 : 1)),
        child: Row(children: [
          Icon(method.icon,
              color: isSelected ? method.color : Colors.grey,
              size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(method.label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected ? method.color : Colors.black87),
                  overflow: TextOverflow.ellipsis)),
          if (isSelected)
            Icon(Icons.check_circle, color: method.color, size: 14),
        ]),
      ),
    );
  }
}