import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../models/product_model.dart';
import '../../services/customer_service.dart';
import '../product/product_list_screen.dart';
import 'payment_screen.dart';
import '../../utils/app_notification.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// FORMATTERS & ENUMS
// ═══════════════════════════════════════════════════════════════════════════════

class _ThousandSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
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

enum ProdCat {
  pulsa,
  paketData,
  tokenListrik,
  tagihan,
  eWallet,
  jasaTransfer,
  lainnya
}

ProdCat _resolveCategory(String? raw) {
  switch (raw?.toLowerCase().trim()) {
    case 'pulsa':
      return ProdCat.pulsa;
    case 'paket data':
      return ProdCat.paketData;
    case 'token listrik':
      return ProdCat.tokenListrik;
    case 'tagihan':
      return ProdCat.tagihan;
    case 'e-wallet':
    case 'ewallet':
      return ProdCat.eWallet;
    case 'jasa transfer':
      return ProdCat.jasaTransfer;
    default:
      return ProdCat.lainnya;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═══════════════════════════════════════════════════════════════════════════════

const _kPrimary = Color(0xFF2196F3);
const _kSuccess = Color(0xFF4CAF50);
const _kDanger = Color(0xFFE53935);
const _kWarning = Color(0xFFFF9800);
const _kTextDark = Color(0xFF111827);
const _kTextMid = Color(0xFF374151);

// ═══════════════════════════════════════════════════════════════════════════════
// CART ITEM MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class CartItem {
  final String id;
  final ProductModel product;
  int quantity;
  int hargaJual;
  int hargaBeli;
  String customerNumber;
  String atasNama;
  String nominal;
  String adminFee;

  CartItem({
    required this.id,
    required this.product,
    this.quantity = 1,
    required this.hargaJual,
    required this.hargaBeli,
    this.customerNumber = '',
    this.atasNama = '',
    this.nominal = '',
    this.adminFee = '',
  });

  ProdCat get category => _resolveCategory(product.category);

  int get subtotalJual => hargaJual * quantity;
  int get subtotalBeli => hargaBeli * quantity;
  int get subtotalLaba => subtotalJual - subtotalBeli;

  int get nominalInt => int.tryParse(nominal.replaceAll('.', '')) ?? 0;
  int get adminFeeInt =>
      int.tryParse(adminFee.replaceAll('.', '')) ?? product.adminFee;

  CartItem copyWith({
    int? quantity,
    int? hargaJual,
    int? hargaBeli,
    String? customerNumber,
    String? atasNama,
    String? nominal,
    String? adminFee,
  }) =>
      CartItem(
        id: id,
        product: product,
        quantity: quantity ?? this.quantity,
        hargaJual: hargaJual ?? this.hargaJual,
        hargaBeli: hargaBeli ?? this.hargaBeli,
        customerNumber: customerNumber ?? this.customerNumber,
        atasNama: atasNama ?? this.atasNama,
        nominal: nominal ?? this.nominal,
        adminFee: adminFee ?? this.adminFee,
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// DIALOG HELPER
// ═══════════════════════════════════════════════════════════════════════════════

Future<bool?> _showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required IconData icon,
  required Color iconColor,
  String cancelLabel = 'Batal',
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.08),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: iconColor.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(icon, color: iconColor, size: 28),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _kTextDark,
                    letterSpacing: -0.3,
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                      side: BorderSide(color: Colors.grey[300]!),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(cancelLabel,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: iconColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(confirmLabel,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
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

// ═══════════════════════════════════════════════════════════════════════════════
// ENUM: Pilihan saat produk duplikat
// ═══════════════════════════════════════════════════════════════════════════════

enum _DuplicateChoice { addQty, addSeparate, cancel }

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class NewTransactionScreen extends StatefulWidget {
  const NewTransactionScreen({super.key});

  @override
  State<NewTransactionScreen> createState() => _NewTransactionScreenState();
}

class _NewTransactionScreenState extends State<NewTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerIdCtrl = TextEditingController();
  final _scrollController = ScrollController();
  final _customerService = CustomerService();

  final List<CartItem> _cartItems = [];
  int _cartIdCounter = 0;

  bool _isLoading = false;
  CustomerModel? _selectedCustomer;
  String? _selectedNumber;
  DateTime _selectedDate = DateTime.now();

  List<CustomerModel> _allCustomers = [];
  bool _isLoadingCustomers = false;

  // ── Computed ───────────────────────────────────────────────────────────────

  int get _grandTotal => _cartItems.fold(0, (s, i) => s + i.subtotalJual);
  int get _totalBeli => _cartItems.fold(0, (s, i) => s + i.subtotalBeli);
  int get _totalLaba => _grandTotal - _totalBeli;
  int get _totalQty => _cartItems.fold(0, (s, i) => s + i.quantity);

  String _fmt(int value) =>
      NumberFormat('#,##0', 'id_ID').format(value).replaceAll(',', '.');

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _refreshCustomers();
  }

  @override
  void dispose() {
    _customerIdCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshCustomers() async {
    if (_isLoadingCustomers) return;
    if (mounted) setState(() => _isLoadingCustomers = true);
    try {
      final list = await _customerService.getAll();
      if (mounted) setState(() => _allCustomers = list);
    } finally {
      if (mounted) setState(() => _isLoadingCustomers = false);
    }
  }

  // ── Cart Operations ────────────────────────────────────────────────────────

  CartItem _makeCartItem(ProductModel p) {
    final cat = _resolveCategory(p.category);
    final isBillType = cat == ProdCat.tagihan ||
        cat == ProdCat.eWallet ||
        cat == ProdCat.jasaTransfer;
    // Untuk tagihan & jasa transfer: tidak auto-fill nomor karena tiap item
    // punya nomor sendiri (PLN, BPJS, Indihome berbeda).
    // Untuk e-wallet & lainnya: auto-fill dari customer aktif.
    final autoCustomerNumber =
        (cat == ProdCat.tagihan || cat == ProdCat.jasaTransfer)
            ? ''
            : (_selectedNumber ?? '');
    return CartItem(
      id: '${_cartIdCounter++}',
      product: p,
      quantity: 1,
      hargaJual: p.price,
      hargaBeli: p.costPrice ?? 0,
      adminFee: p.adminFee > 0 ? _fmt(p.adminFee) : '',
      nominal: p.price > 0 && isBillType ? _fmt(p.price) : '',
      customerNumber: autoCustomerNumber,
    );
  }

  Future<void> _addProduct(ProductModel p) async {
    final cat = _resolveCategory(p.category);

    // FIX 1: Tagihan & Jasa Transfer selalu item terpisah (nomor berbeda-beda).
    // E-Wallet TIDAK termasuk — e-wallet bisa tambah qty seperti pulsa.
    final alwaysSeparate =
        cat == ProdCat.tagihan || cat == ProdCat.jasaTransfer;

    if (alwaysSeparate) {
      setState(() => _cartItems.add(_makeCartItem(p)));
      _showSnackbar('Ditambahkan', '${p.name} masuk ke keranjang',
          isSuccess: true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      return;
    }

    // Cek duplikat untuk semua kategori lainnya (termasuk e-wallet)
    final existingIndices = _cartItems
        .asMap()
        .entries
        .where((e) => e.value.product.id == p.id)
        .map((e) => e.key)
        .toList();

    if (existingIndices.isEmpty) {
      setState(() => _cartItems.add(_makeCartItem(p)));
      _showSnackbar('Ditambahkan', '${p.name} masuk ke keranjang',
          isSuccess: true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      return;
    }

    // Produk sudah ada → tanya user mau apa
    final choice = await _showDuplicateProductSheet(p, existingIndices.length);

    if (!mounted || choice == null || choice == _DuplicateChoice.cancel) return;

    if (choice == _DuplicateChoice.addQty) {
      final idx = existingIndices.first;
      setState(() {
        _cartItems[idx] = _cartItems[idx].copyWith(
          quantity: _cartItems[idx].quantity + 1,
        );
      });
      _showSnackbar('Qty Ditambah', '${p.name} +1', isSuccess: true);
    } else if (choice == _DuplicateChoice.addSeparate) {
      setState(() => _cartItems.add(_makeCartItem(p)));
      _showSnackbar('Ditambahkan', '${p.name} ditambah sebagai item baru',
          isSuccess: true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  Future<_DuplicateChoice?> _showDuplicateProductSheet(
      ProductModel p, int existingCount) {
    return showModalBottomSheet<_DuplicateChoice>(
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
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kWarning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add_shopping_cart_rounded,
                    color: _kWarning, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Produk Sudah di Keranjang',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _kTextDark),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p.name,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _kPrimary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kPrimary.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    size: 15, color: _kPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sudah ada $existingCount item "${p.name}" di keranjang. '
                    'Pilih aksi yang diinginkan.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            _choiceTile(
              icon: Icons.add_circle_rounded,
              iconColor: _kPrimary,
              title: 'Tambah Qty (+1)',
              subtitle: 'Jumlah item yang sama bertambah satu',
              onTap: () => Navigator.pop(context, _DuplicateChoice.addQty),
            ),
            const SizedBox(height: 10),
            _choiceTile(
              icon: Icons.playlist_add_rounded,
              iconColor: _kSuccess,
              title: 'Tambah sebagai Item Baru',
              subtitle:
                  'Harga beli, harga jual, dan nomor pelanggan bisa diatur berbeda',
              onTap: () => Navigator.pop(context, _DuplicateChoice.addSeparate),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () =>
                    Navigator.pop(context, _DuplicateChoice.cancel),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[600],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Batal',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  Widget _choiceTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? badge,
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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _kTextDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: _kSuccess.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge,
                              style: const TextStyle(
                                fontSize: 10,
                                color: _kSuccess,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
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

  void _showSnackbar(String title, String message, {required bool isSuccess}) {
    if (isSuccess) {
      AppNotification.success(title, message, duration: const Duration(seconds: 2));
    } else {
      AppNotification.error(title, message, duration: const Duration(seconds: 2));
    }
  }

  void _removeItem(String itemId) {
    setState(() => _cartItems.removeWhere((i) => i.id == itemId));
  }

  void _updateItemQty(String itemId, int delta) {
    final idx = _cartItems.indexWhere((i) => i.id == itemId);
    if (idx < 0) return;
    final newQty = _cartItems[idx].quantity + delta;
    if (newQty <= 0) {
      _confirmRemove(itemId, _cartItems[idx].product.name);
    } else {
      setState(() {
        _cartItems[idx] = _cartItems[idx].copyWith(quantity: newQty);
      });
    }
  }

  Future<void> _confirmRemove(String itemId, String name) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Hapus Produk?',
      message: '"$name" akan dihapus dari keranjang.',
      confirmLabel: 'Hapus',
      icon: Icons.delete_outline_rounded,
      iconColor: _kDanger,
    );
    if (confirmed == true) _removeItem(itemId);
  }

  Future<void> _confirmClearCart() async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Kosongkan Keranjang?',
      message: 'Semua ${_cartItems.length} produk di keranjang akan dihapus.',
      confirmLabel: 'Kosongkan',
      icon: Icons.delete_sweep_rounded,
      iconColor: _kDanger,
    );
    if (confirmed == true) setState(() => _cartItems.clear());
  }

  // ── Date & Customer ────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Tanggal Transaksi',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _kPrimary),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _selectedDate = picked);
  }

  Future<void> _openCustomerPicker() async {
    await _refreshCustomers();
    if (!mounted) return;

    final result = await showModalBottomSheet<_CustomerPickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomerPickerSheet(
        allCustomers: _allCustomers,
        selectedCustomer: _selectedCustomer,
        selectedNumber: _selectedNumber,
        customerService: _customerService,
        onCustomerSaved: (_) async => await _refreshCustomers(),
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      if (result.clearSelection) {
        _selectedCustomer = null;
        _selectedNumber = null;
        _customerIdCtrl.clear();
        for (int i = 0; i < _cartItems.length; i++) {
          _cartItems[i] = _cartItems[i].copyWith(customerNumber: '');
        }
      } else if (result.customer != null) {
        _selectedCustomer = result.customer;
        _selectedNumber = result.selectedNumber;
        final autoNum = result.selectedNumber ?? '';
        if (autoNum.isNotEmpty) {
          _customerIdCtrl.text = autoNum;
        } else {
          _customerIdCtrl.clear();
        }
        // FIX 2: Auto-fill hanya untuk item yang bukan tagihan/jasaTransfer
        // karena mereka punya nomor berbeda-beda (PLN, BPJS, Indihome, dll).
        for (int i = 0; i < _cartItems.length; i++) {
          final cat = _cartItems[i].category;
          final isBillSeparate =
              cat == ProdCat.tagihan || cat == ProdCat.jasaTransfer;
          if (!isBillSeparate && _cartItems[i].customerNumber.isEmpty) {
            _cartItems[i] = _cartItems[i].copyWith(customerNumber: autoNum);
          }
        }
      }
    });
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  // ── Process Transaction ────────────────────────────────────────────────────

  Future<void> _processTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_cartItems.isEmpty) {
      AppNotification.warning('Keranjang Kosong', 'Tambahkan produk terlebih dahulu.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final customerId = _selectedNumber ??
          (_customerIdCtrl.text.trim().isNotEmpty
              ? _customerIdCtrl.text.trim()
              : '');
      final customerName = _selectedCustomer?.name ?? '';

      if (customerName.isNotEmpty && customerId.isNotEmpty) {
        await _customerService.upsert(number: customerId, name: customerName);
      } else if (customerName.isNotEmpty && customerId.isEmpty) {
        await _customerService.upsertNameOnly(name: customerName);
      }

      final updatedItems = _cartItems.map((item) {
        final cat = item.category;
        final isBillSeparate =
            cat == ProdCat.tagihan || cat == ProdCat.jasaTransfer;
        // Jangan timpa nomor item tagihan yang sudah diisi manual
        if (!isBillSeparate &&
            item.customerNumber.isEmpty &&
            customerId.isNotEmpty) {
          return item.copyWith(customerNumber: customerId);
        }
        return item;
      }).toList();

      Get.to(() => PaymentScreen(
            cartItems: updatedItems,
            customerNumber: customerId,
            customerName: customerName,
            atasNama: _cartItems.isNotEmpty ? _cartItems.first.atasNama : '',
            transactionDate: _selectedDate,
          ));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaksi Baru'),
        actions: [
          if (_cartItems.isNotEmpty) _buildCartBadge(),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          children: [
            _buildDatePicker(),
            const SizedBox(height: 16),
            _buildCustomerSection(),
            const SizedBox(height: 16),
            _buildAddProductButton(),
            const SizedBox(height: 16),
            if (_cartItems.isNotEmpty) ...[
              _buildCartList(),
              const SizedBox(height: 16),
              _buildOrderSummary(),
              const SizedBox(height: 24),
              _buildCheckoutButton(),
              const SizedBox(height: 32),
            ] else
              _buildEmptyCart(),
          ],
        ),
      ),
    );
  }

  Widget _buildCartBadge() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.shopping_cart_rounded),
            onPressed: _scrollToBottom,
            tooltip: 'Lihat Keranjang',
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                  color: _kDanger, shape: BoxShape.circle),
              child: Center(
                child: Text('$_totalQty',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker() {
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    return GestureDetector(
      onTap: _pickDate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: _kPrimary.withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          _iconBox(Icons.calendar_today_rounded, _kPrimary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tanggal Transaksi',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  const SizedBox(height: 3),
                  Text(
                    DateFormat('EEEE, dd MMMM yyyy', 'id_ID')
                        .format(_selectedDate),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _kTextDark),
                  ),
                ]),
          ),
          if (isToday)
            _pill('Hari ini', _kPrimary)
          else
            const Icon(Icons.edit_calendar_rounded, color: _kPrimary, size: 18),
        ]),
      ),
    );
  }

  Widget _buildCustomerSection() {
    final hasCustomer = _selectedCustomer != null;
    final displayNum =
        _selectedNumber ?? _selectedCustomer?.number ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Pelanggan', _kPrimary),
        const SizedBox(height: 10),
        _selectorTile(
          icon: Icons.person_rounded,
          label: hasCustomer ? _selectedCustomer!.name : 'Pilih Pelanggan',
          subtitle: hasCustomer
              ? (displayNum.isNotEmpty ? 'No: $displayNum' : 'Tanpa nomor')
              : 'Opsional — ketuk untuk memilih',
          hasValue: hasCustomer,
          onTap: _openCustomerPicker,
          trailing: hasCustomer
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  if (_selectedCustomer!.hasDebt) ...[
                    _debtBadge(),
                    const SizedBox(width: 6),
                  ],
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ])
              : const Icon(Icons.chevron_right, color: Colors.grey),
        ),
        if (hasCustomer && _selectedCustomer!.numbers.length > 1) ...[
          const SizedBox(height: 6),
          _buildNumberChips(),
        ],
        if (hasCustomer && _selectedCustomer!.hasDebt) ...[
          const SizedBox(height: 6),
          _buildDebtWarning(),
        ],
        if (!hasCustomer) ...[
          const SizedBox(height: 10),
          _buildCustomerNumberField(),
        ],
      ],
    );
  }

  Widget _buildNumberChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kPrimary.withValues(alpha: 0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.numbers_rounded, size: 15, color: _kPrimary),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _selectedCustomer!.numbers.map((numStr) {
              final isSelected = numStr == _selectedNumber;
              return GestureDetector(
                onTap: () => setState(() {
                  _selectedNumber = numStr;
                  _customerIdCtrl.text = numStr;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? _kPrimary : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? _kPrimary
                          : Colors.grey.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(numStr,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              isSelected ? Colors.white : Colors.black87)),
                ),
              );
            }).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _buildDebtWarning() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _kDanger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kDanger.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: _kDanger, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${_selectedCustomer!.name} masih memiliki hutang.',
            style: const TextStyle(
                fontSize: 12,
                color: _kDanger,
                fontWeight: FontWeight.w500),
          ),
        ),
      ]),
    );
  }

  Widget _buildCustomerNumberField() {
    return TextFormField(
      controller: _customerIdCtrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(
        labelText: 'Nomor Pelanggan (Opsional)',
        hintText: 'Masukkan nomor HP pelanggan',
        prefixIcon: Icon(Icons.tag),
      ),
    );
  }

  Widget _buildAddProductButton() {
    return Column(
      children: [
        if (_cartItems.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _kPrimary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kPrimary.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: _kPrimary, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Produk yang sama dapat ditambah qty atau dijadikan item baru dengan harga berbeda.',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ),
            ]),
          ),
        ],
        GestureDetector(
          onTap: () async {
            final result = await Get.to(
                () => const ProductListScreen(isSelectionMode: true));
            if (result is ProductModel) _addProduct(result);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: _kPrimary,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: _kPrimary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_shopping_cart_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  _cartItems.isEmpty ? 'Pilih Produk' : 'Tambah Produk Lain',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCart() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: _kPrimary.withValues(alpha: 0.07),
                shape: BoxShape.circle),
            child: const Icon(Icons.shopping_cart_outlined,
                size: 48, color: _kPrimary),
          ),
          const SizedBox(height: 16),
          const Text('Keranjang Kosong',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kTextMid)),
          const SizedBox(height: 6),
          Text('Tambahkan produk untuk memulai transaksi',
              style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kWarning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kWarning.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  color: _kWarning, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Kamu bisa menambahkan lebih dari satu produk dalam satu transaksi!',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildCartList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _sectionHeader('Keranjang ($_totalQty item)', _kPrimary),
          const Spacer(),
          if (_cartItems.length > 1)
            GestureDetector(
              onTap: _confirmClearCart,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _kDanger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: _kDanger.withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.delete_sweep_rounded,
                      size: 14, color: Colors.red[700]),
                  const SizedBox(width: 4),
                  Text('Kosongkan',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.red[700],
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        // FIX 2: Teruskan selectedCustomer ke setiap CartItemCard
        ..._cartItems.asMap().entries.map((entry) => _CartItemCard(
              key: ValueKey(entry.value.id),
              item: entry.value,
              index: entry.key,
              selectedCustomer: _selectedCustomer,
              onRemove: () =>
                  _confirmRemove(entry.value.id, entry.value.product.name),
              onQtyChange: (delta) =>
                  _updateItemQty(entry.value.id, delta),
              onItemChanged: (updated) => setState(() {
                final idx =
                    _cartItems.indexWhere((i) => i.id == entry.value.id);
                if (idx >= 0) _cartItems[idx] = updated;
              }),
              formatThousand: _fmt,
            )),
      ],
    );
  }

  Widget _buildOrderSummary() {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final hasHargaBeli = _cartItems.any((i) => i.hargaBeli > 0);
    final isProfit = _totalLaba >= 0;

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
        _sectionHeader('Ringkasan Order', _kSuccess),
        const SizedBox(height: 14),
        ..._cartItems.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Expanded(
                child: Text(
                  '${item.product.name}'
                  '${item.quantity > 1 ? ' ×${item.quantity}' : ''}',
                  style: const TextStyle(fontSize: 13, color: _kTextMid),
                ),
              ),
              Text(
                fmt.format(item.subtotalJual),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _kTextDark),
              ),
            ]),
          ),
        ),
        const Divider(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('TOTAL',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kPrimary)),
          Text(fmt.format(_grandTotal),
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _kPrimary)),
        ]),
        if (hasHargaBeli) ...[
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isProfit
                  ? _kSuccess.withValues(alpha: 0.07)
                  : _kDanger.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isProfit
                    ? _kSuccess.withValues(alpha: 0.3)
                    : _kDanger.withValues(alpha: 0.3),
              ),
            ),
            child: Row(children: [
              Icon(
                isProfit
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                size: 16,
                color: isProfit ? Colors.green[700] : Colors.red[700],
              ),
              const SizedBox(width: 8),
              Text(
                'Estimasi Laba: ${fmt.format(_totalLaba.abs())}'
                '${_totalLaba < 0 ? ' (rugi)' : ''}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isProfit
                        ? Colors.green[700]
                        : Colors.red[700]),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildCheckoutButton() {
    final fmtCurrency = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _processTransaction,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kSuccess,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Lanjut ke Pembayaran (${fmtCurrency.format(_grandTotal)})',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, Color color) {
    return Row(children: [
      Container(
        width: 4,
        height: 18,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 8),
      Text(title,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _debtBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _kDanger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kDanger.withValues(alpha: 0.4)),
      ),
      child: Text('Ada hutang',
          style: TextStyle(
              fontSize: 10,
              color: Colors.red[700],
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _selectorTile({
    required IconData icon,
    required String label,
    String? subtitle,
    required bool hasValue,
    required VoidCallback onTap,
    Color? iconColor,
    Widget? trailing,
  }) {
    final color = iconColor ?? _kPrimary;
    return Container(
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
      child: ListTile(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: _iconBox(icon, color),
        title: Text(label,
            style: TextStyle(
                fontWeight:
                    hasValue ? FontWeight.w600 : FontWeight.normal,
                color: hasValue ? Colors.black : Colors.grey)),
        subtitle: subtitle != null
            ? Text(subtitle, style: const TextStyle(fontSize: 12))
            : null,
        trailing:
            trailing ?? const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CART ITEM CARD
// FIX 1: Tambah selectedCustomer parameter
// FIX 2: Pisahkan logika allowMultiQty — e-wallet boleh qty, tagihan tidak
// FIX 3: Untuk item tagihan/jasaTransfer, tampilkan chip semua nomor pelanggan
//         agar user bisa pilih nomor berbeda per item (PLN, BPJS, Indihome)
// ═══════════════════════════════════════════════════════════════════════════════

class _CartItemCard extends StatefulWidget {
  final CartItem item;
  final int index;
  final CustomerModel? selectedCustomer; // ← BARU: untuk picker nomor per item
  final VoidCallback onRemove;
  final void Function(int delta) onQtyChange;
  final void Function(CartItem updated) onItemChanged;
  final String Function(int) formatThousand;

  const _CartItemCard({
    super.key,
    required this.item,
    required this.index,
    this.selectedCustomer,
    required this.onRemove,
    required this.onQtyChange,
    required this.onItemChanged,
    required this.formatThousand,
  });

  @override
  State<_CartItemCard> createState() => _CartItemCardState();
}

class _CartItemCardState extends State<_CartItemCard> {
  late TextEditingController _hargaJualCtrl;
  late TextEditingController _hargaBeliCtrl;
  late TextEditingController _nominalCtrl;
  late TextEditingController _adminFeeCtrl;
  late TextEditingController _customerNumberCtrl;
  late TextEditingController _atasNamaCtrl;

  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _initControllers(widget.item);
    _addListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onChanged();
    });
  }

  void _initControllers(CartItem item) {
    _hargaJualCtrl = TextEditingController(
        text:
            item.hargaJual > 0 ? widget.formatThousand(item.hargaJual) : '');
    _hargaBeliCtrl = TextEditingController(
        text:
            item.hargaBeli > 0 ? widget.formatThousand(item.hargaBeli) : '');
    _nominalCtrl = TextEditingController(
        text: item.nominal.isNotEmpty ? item.nominal : '');
    _adminFeeCtrl = TextEditingController(
        text: item.adminFee.isNotEmpty ? item.adminFee : '');
    _customerNumberCtrl =
        TextEditingController(text: item.customerNumber);
    _atasNamaCtrl = TextEditingController(text: item.atasNama);
  }

  void _addListeners() {
    for (final ctrl in _allControllers) {
      ctrl.addListener(_onChanged);
    }
  }

  void _removeListeners() {
    for (final ctrl in _allControllers) {
      ctrl.removeListener(_onChanged);
    }
  }

  List<TextEditingController> get _allControllers => [
        _hargaJualCtrl,
        _hargaBeliCtrl,
        _nominalCtrl,
        _adminFeeCtrl,
        _customerNumberCtrl,
        _atasNamaCtrl,
      ];

  @override
  void didUpdateWidget(_CartItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _removeListeners();
      for (final ctrl in _allControllers) {
        ctrl.dispose();
      }
      _initControllers(widget.item);
      _addListeners();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onChanged();
      });
    } else if (oldWidget.item.customerNumber != widget.item.customerNumber) {
      _removeListeners();
      _customerNumberCtrl.text = widget.item.customerNumber;
      _addListeners();
    }
  }

  @override
  void dispose() {
    _removeListeners();
    for (final ctrl in _allControllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    int rawInt(String s) => int.tryParse(s.replaceAll('.', '')) ?? 0;

    final nominal = rawInt(_nominalCtrl.text);
    final adminFee = rawInt(_adminFeeCtrl.text);
    final isBillType = widget.item.category == ProdCat.tagihan ||
        widget.item.category == ProdCat.eWallet ||
        widget.item.category == ProdCat.jasaTransfer;

    final int computedHargaJual;
    final int computedHargaBeli;

    if (isBillType) {
      computedHargaJual = nominal + adminFee;
      computedHargaBeli = nominal;
    } else {
      computedHargaJual = rawInt(_hargaJualCtrl.text);
      computedHargaBeli = rawInt(_hargaBeliCtrl.text);
    }

    widget.onItemChanged(widget.item.copyWith(
      hargaJual: computedHargaJual,
      hargaBeli: computedHargaBeli,
      nominal: _nominalCtrl.text,
      adminFee: _adminFeeCtrl.text,
      customerNumber: _customerNumberCtrl.text.trim(),
      atasNama: _atasNamaCtrl.text.trim(),
    ));
  }

  String get _categoryLabel {
    switch (widget.item.category) {
      case ProdCat.pulsa:
        return 'Pulsa';
      case ProdCat.paketData:
        return 'Paket Data';
      case ProdCat.tokenListrik:
        return 'Token Listrik';
      case ProdCat.tagihan:
        return 'Tagihan';
      case ProdCat.eWallet:
        return 'E-Wallet';
      case ProdCat.jasaTransfer:
        return 'Jasa Transfer';
      case ProdCat.lainnya:
        return widget.item.product.category;
    }
  }

  bool get _showHargaBeli {
    final cat = widget.item.category;
    return cat == ProdCat.pulsa ||
        cat == ProdCat.paketData ||
        cat == ProdCat.tokenListrik ||
        cat == ProdCat.lainnya;
  }

  bool get _showNominalAdminFee {
    final cat = widget.item.category;
    return cat == ProdCat.tagihan ||
        cat == ProdCat.eWallet ||
        cat == ProdCat.jasaTransfer;
  }

  bool get _showAtasNama {
    final cat = widget.item.category;
    return cat == ProdCat.tokenListrik || cat == ProdCat.tagihan;
  }

  // FIX 1: E-Wallet sekarang boleh multi qty — hanya tagihan & jasa transfer
  // yang tidak boleh karena setiap transaksi punya nomor tujuan berbeda.
  bool get _allowMultiQty {
    final cat = widget.item.category;
    return cat != ProdCat.tagihan && cat != ProdCat.jasaTransfer;
  }

  int get _laba {
    final cat = widget.item.category;
    if (cat == ProdCat.tagihan ||
        cat == ProdCat.eWallet ||
        cat == ProdCat.jasaTransfer) {
      return int.tryParse(_adminFeeCtrl.text.replaceAll('.', '')) ??
          widget.item.product.adminFee;
    }
    final jual =
        int.tryParse(_hargaJualCtrl.text.replaceAll('.', '')) ?? 0;
    final beli =
        int.tryParse(_hargaBeliCtrl.text.replaceAll('.', '')) ?? 0;
    return jual - beli;
  }

  String get _customerFieldLabel {
    final cat = widget.item.category;
    return (cat == ProdCat.tokenListrik || cat == ProdCat.tagihan)
        ? 'ID Pelanggan (Opsional)'
        : 'Nomor Pelanggan (Opsional)';
  }

  String get _customerFieldHint {
    final cat = widget.item.category;
    return (cat == ProdCat.tokenListrik || cat == ProdCat.tagihan)
        ? 'Masukkan ID / nomor meter'
        : 'Masukkan nomor HP';
  }

  // FIX 2: Chip picker untuk memilih nomor pelanggan per item tagihan.
  // Menampilkan semua nomor dari CustomerModel sehingga tagihan listrik,
  // BPJS, dan Indihome bisa dipilih dari nomor yang berbeda-beda.
  Widget _buildCustomerNumberChips() {
    final customer = widget.selectedCustomer;
    if (customer == null || customer.numbers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.person_pin_rounded, size: 13, color: _kPrimary),
          const SizedBox(width: 5),
          Text(
            'Pilih nomor dari "${customer.name}":',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: customer.numbers.asMap().entries.map((entry) {
            final idx = entry.key;
            final numStr = entry.value;
            final isSelected = _customerNumberCtrl.text == numStr;
            return GestureDetector(
              onTap: () {
                _removeListeners();
                _customerNumberCtrl.text = numStr;
                _addListeners();
                _onChanged();
                setState(() {});
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected ? _kPrimary : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? _kPrimary
                        : Colors.grey.withValues(alpha: 0.4),
                    width: isSelected ? 1.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                              color: _kPrimary.withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2))
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      idx == 0 ? 'Utama' : 'No. ${idx + 1}',
                      style: TextStyle(
                        fontSize: 9,
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.8)
                            : Colors.grey[500],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      numStr,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final item = widget.item;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kPrimary.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Row(children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                      color: _kPrimary,
                      borderRadius: BorderRadius.circular(8)),
                  child: Center(
                    child: Text('${widget.index + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.product.name,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        Text(_categoryLabel,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500])),
                      ]),
                ),
                Text(fmt.format(item.subtotalJual),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _kPrimary)),
                const SizedBox(width: 8),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Colors.grey,
                  size: 20,
                ),
              ]),
            ),
          ),

          // ── Qty Row ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(children: [
              Text('Qty:',
                  style:
                      TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(width: 10),
              _QtyControl(
                quantity: item.quantity,
                allowMultiQty: _allowMultiQty,
                onMinus: () => widget.onQtyChange(-1),
                onPlus:
                    _allowMultiQty ? () => widget.onQtyChange(1) : null,
              ),
              if (!_allowMultiQty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Setiap tagihan punya nomor berbeda',
                    style:
                        TextStyle(fontSize: 10, color: Colors.grey[400]),
                  ),
                ),
              ] else
                const Spacer(),
              GestureDetector(
                onTap: widget.onRemove,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: _kDanger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.delete_outline_rounded,
                      color: _kDanger, size: 18),
                ),
              ),
            ]),
          ),

          // ── Expanded Fields ──────────────────────────────────────────────
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // FIX 2: Tampilkan chip nomor pelanggan untuk semua kategori
                  // yang punya data customer — tapi khususnya sangat berguna
                  // untuk tagihan (PLN, BPJS, Indihome bisa beda nomor).
                  if (widget.selectedCustomer != null &&
                      (widget.selectedCustomer!.numbers.isNotEmpty)) ...[
                    _buildCustomerNumberChips(),
                  ],
                  _buildField(
                    ctrl: _customerNumberCtrl,
                    label: _customerFieldLabel,
                    hint: _customerFieldHint,
                    icon: Icons.tag,
                    isNumeric: true,
                  ),
                  if (_showAtasNama) ...[
                    const SizedBox(height: 10),
                    _buildField(
                      ctrl: _atasNamaCtrl,
                      label: 'Atas Nama (Opsional)',
                      hint: 'Nama pemilik rekening / meter',
                      icon: Icons.badge_outlined,
                    ),
                  ],
                  if (_showNominalAdminFee) ...[
                    const SizedBox(height: 10),
                    _buildCurrencyField(
                      ctrl: _nominalCtrl,
                      label: 'Nominal (Opsional)',
                      icon: Icons.payments_outlined,
                    ),
                    const SizedBox(height: 10),
                    _buildCurrencyField(
                      ctrl: _adminFeeCtrl,
                      label: 'Biaya Admin',
                      icon: Icons.receipt_long_outlined,
                      required: true,
                    ),
                  ],
                  if (_showHargaBeli) ...[
                    const SizedBox(height: 10),
                    _buildCurrencyField(
                      ctrl: _hargaBeliCtrl,
                      label: 'Harga Beli',
                      icon: Icons.shopping_cart_outlined,
                      required: true,
                    ),
                    const SizedBox(height: 10),
                    _buildCurrencyField(
                      ctrl: _hargaJualCtrl,
                      label: 'Harga Jual',
                      icon: Icons.sell_outlined,
                      required: true,
                    ),
                    const SizedBox(height: 8),
                    _buildLabaIndicator(fmt, item),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLabaIndicator(NumberFormat fmt, CartItem item) {
    return AnimatedBuilder(
      animation: Listenable.merge(
          [_hargaBeliCtrl, _hargaJualCtrl, _adminFeeCtrl]),
      builder: (_, __) {
        final laba = _laba;
        final isProfit = laba >= 0;
        final color = laba > 0
            ? Colors.green[700]!
            : laba < 0
                ? Colors.red[700]!
                : Colors.grey[600]!;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isProfit
                ? _kSuccess.withValues(alpha: 0.07)
                : _kDanger.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isProfit
                  ? _kSuccess.withValues(alpha: 0.3)
                  : _kDanger.withValues(alpha: 0.3),
            ),
          ),
          child: Row(children: [
            Icon(
              isProfit
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              'Laba/item: ${fmt.format(laba.abs())}${laba < 0 ? ' (rugi)' : ''}',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color),
            ),
            const Spacer(),
            if (item.quantity > 1)
              Text(
                '×${item.quantity} = ${fmt.format(laba.abs() * item.quantity)}',
                style:
                    TextStyle(fontSize: 10, color: Colors.grey[500]),
              ),
          ]),
        );
      },
    );
  }

  Widget _buildField({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    required IconData icon,
    bool isNumeric = false,
    bool required = false,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType:
          isNumeric ? TextInputType.number : TextInputType.text,
      inputFormatters:
          isNumeric ? [FilteringTextInputFormatter.digitsOnly] : [],
      textCapitalization: isNumeric
          ? TextCapitalization.none
          : TextCapitalization.words,
      validator: required
          ? (v) => (v == null || v.trim().isEmpty)
              ? '$label harus diisi'
              : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kPrimary, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildCurrencyField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    bool required = false,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [_ThousandSeparatorFormatter()],
      validator: required
          ? (v) => (v == null || v.trim().isEmpty)
              ? '$label harus diisi'
              : null
          : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        prefixText: 'Rp ',
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _kPrimary, width: 1.5),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// QTY CONTROL WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

class _QtyControl extends StatelessWidget {
  final int quantity;
  final bool allowMultiQty;
  final VoidCallback onMinus;
  final VoidCallback? onPlus;

  const _QtyControl({
    required this.quantity,
    required this.allowMultiQty,
    required this.onMinus,
    this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kPrimary.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _btn(Icons.remove_rounded, onMinus,
            color: quantity <= 1 ? _kDanger : _kPrimary),
        SizedBox(
          width: 36,
          child: Center(
            child: Text('$quantity',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _kTextDark)),
          ),
        ),
        _btn(Icons.add_rounded, onPlus,
            color: allowMultiQty
                ? _kPrimary
                : Colors.grey.withValues(alpha: 0.4)),
      ]),
    );
  }

  Widget _btn(IconData icon, VoidCallback? onTap, {required Color color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color:
              color.withValues(alpha: onTap == null ? 0.05 : 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon,
            size: 16,
            color: onTap == null
                ? Colors.grey.withValues(alpha: 0.4)
                : color),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOMER PICKER — RESULT MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class _CustomerPickResult {
  final CustomerModel? customer;
  final String? selectedNumber;
  final bool clearSelection;

  const _CustomerPickResult({
    this.customer,
    this.selectedNumber,
    this.clearSelection = false,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOMER PICKER BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _CustomerPickerSheet extends StatefulWidget {
  final List<CustomerModel> allCustomers;
  final CustomerModel? selectedCustomer;
  final String? selectedNumber;
  final CustomerService customerService;
  final Future<void> Function(CustomerModel) onCustomerSaved;

  const _CustomerPickerSheet({
    required this.allCustomers,
    required this.selectedCustomer,
    required this.selectedNumber,
    required this.customerService,
    required this.onCustomerSaved,
  });

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final _searchCtrl = TextEditingController();
  final _addNameCtrl = TextEditingController();
  final _addNumberCtrl = TextEditingController();
  final _addFormKey = GlobalKey<FormState>();

  late List<CustomerModel> _filtered;
  String _query = '';

  bool _showAddForm = false;
  bool _showNumPicker = false;
  bool _isSaving = false;
  CustomerModel? _pendingCustomer;

  @override
  void initState() {
    super.initState();
    _filtered = List.from(widget.allCustomers);
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _addNameCtrl.dispose();
    _addNumberCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _query = q;
      _filtered = q.isEmpty
          ? List.from(widget.allCustomers)
          : widget.allCustomers
              .where((c) =>
                  c.name.toLowerCase().contains(q) ||
                  c.numbers.any((n) => n.contains(q)))
              .toList();
    });
  }

  void _onCustomerTap(CustomerModel c) {
    if (c.numbers.isEmpty) {
      Navigator.pop(
          context, _CustomerPickResult(customer: c, selectedNumber: null));
    } else {
      setState(() {
        _pendingCustomer = c;
        _showNumPicker = true;
      });
    }
  }

  Future<void> _saveNewCustomer() async {
    if (!_addFormKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final name = _addNameCtrl.text.trim();
      final number = _addNumberCtrl.text.trim();
      if (number.isNotEmpty) {
        await widget.customerService.upsert(number: number, name: name);
      } else {
        await widget.customerService.upsertNameOnly(name: name);
      }
      final newCustomer = CustomerModel(
          id: '',
          numbers: number.isNotEmpty ? [number] : [],
          name: name);
      await widget.onCustomerSaved(newCustomer);
      if (mounted) {
        Navigator.pop(
            context,
            _CustomerPickResult(
              customer: newCustomer,
              selectedNumber: number.isNotEmpty ? number : null,
            ));
      }
    } catch (e) {
      if (mounted) {
        AppNotification.unexpectedError('Gagal menyimpan pelanggan: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height =
        _showAddForm ? 0.68 : _showNumPicker ? 0.5 : 0.88;
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      child: Container(
        height: MediaQuery.of(context).size.height * height,
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: _showNumPicker && _pendingCustomer != null
            ? _buildNumberPicker(_pendingCustomer!)
            : _showAddForm
                ? _buildAddForm()
                : _buildPickerList(),
      ),
    );
  }

  Widget _handleBar() => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2)),
        ),
      );

  Widget _buildNumberPicker(CustomerModel c) {
    return Column(children: [
      _handleBar(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Row(children: [
          _backButton(() => setState(() {
                _showNumPicker = false;
                _pendingCustomer = null;
              })),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  Text('Pilih nomor utama atau lanjut tanpa nomor',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[500])),
                ]),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: c.numbers.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: 16, endIndent: 16),
          itemBuilder: (_, i) {
            final num = c.numbers[i];
            final isSelected = num == widget.selectedNumber;
            return ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _kPrimary.withValues(alpha: 0.12)
                      : Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.tag_rounded,
                    color: isSelected ? _kPrimary : Colors.grey,
                    size: 20),
              ),
              title: Text(num,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? _kPrimary : Colors.black)),
              subtitle: Text(
                  i == 0 ? 'Nomor utama' : 'Nomor alternatif $i',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey[500])),
              trailing: isSelected
                  ? const Icon(Icons.check_circle_rounded,
                      color: _kPrimary)
                  : const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () => Navigator.pop(context,
                  _CustomerPickResult(customer: c, selectedNumber: num)),
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context,
                _CustomerPickResult(customer: c, selectedNumber: null)),
            icon: const Icon(Icons.person_off_outlined, size: 18),
            label: const Text('Lanjut Tanpa Nomor',
                style: TextStyle(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[700],
              side: BorderSide(color: Colors.grey[300]!),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _buildPickerList() {
    return Column(children: [
      _handleBar(),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 16, 16),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: _kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.people_alt_rounded,
                color: _kPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pilih Pelanggan',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  Text('Ketuk nama untuk memilih',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
          ),
          _addButton(() => setState(() {
                _showAddForm = true;
                _addNameCtrl.text = _query;
              })),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: _buildSearchField(),
      ),
      if (widget.allCustomers.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _query.isEmpty
                  ? '${widget.allCustomers.length} pelanggan terdaftar'
                  : '${_filtered.length} hasil untuk "$_query"',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ),
        ),
      const Divider(height: 1, thickness: 1),
      Expanded(child: _buildCustomerListContent()),
    ]);
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        hintText: 'Cari nama atau nomor...',
        prefixIcon:
            const Icon(Icons.search_rounded, color: Colors.grey),
        suffixIcon: _query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() {
                    _query = '';
                    _filtered = List.from(widget.allCustomers);
                  });
                })
            : null,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: _kPrimary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(
            vertical: 12, horizontal: 16),
      ),
    );
  }

  Widget _buildCustomerListContent() {
    if (widget.allCustomers.isEmpty) return _buildEmptyState();
    if (_filtered.isEmpty) return _buildNotFoundState();
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 32, top: 4),
      itemCount: _filtered.length + 1,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 72, endIndent: 16),
      itemBuilder: (_, i) => i == 0
          ? _buildNoPelangganItem()
          : _buildCustomerItem(_filtered[i - 1]),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: _kPrimary.withValues(alpha: 0.08),
                  shape: BoxShape.circle),
              child: const Icon(Icons.people_outline_rounded,
                  size: 48, color: _kPrimary),
            ),
            const SizedBox(height: 16),
            const Text('Belum ada pelanggan',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Tambahkan pelanggan pertamamu',
                style:
                    TextStyle(fontSize: 13, color: Colors.grey[500])),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () =>
                  setState(() => _showAddForm = true),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tambah Pelanggan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
    );
  }

  Widget _buildNotFoundState() {
    return Center(
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded,
                size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text('Tidak ditemukan untuk "$_query"',
                style: TextStyle(
                    fontSize: 14, color: Colors.grey[600])),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _showAddForm = true;
                _addNameCtrl.text = _query;
              }),
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label:
                  Text('Tambah "$_query" sebagai pelanggan baru'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kPrimary,
                side: const BorderSide(color: _kPrimary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
    );
  }

  Widget _buildNoPelangganItem() {
    final isSelected = widget.selectedCustomer == null;
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: const Icon(Icons.person_off_outlined,
            color: Colors.grey, size: 22),
      ),
      title: const Text('Tanpa Pelanggan',
          style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: const Text('Transaksi tanpa nama pelanggan',
          style: TextStyle(fontSize: 12)),
      trailing: isSelected
          ? const Icon(Icons.check_circle_rounded,
              color: _kPrimary, size: 22)
          : const Icon(Icons.chevron_right,
              color: Colors.grey, size: 20),
      onTap: () => Navigator.pop(
          context, const _CustomerPickResult(clearSelection: true)),
    );
  }

  Widget _buildCustomerItem(CustomerModel c) {
    final isSelected = widget.selectedCustomer?.id == c.id;
    final initials = c.name
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();
    final hasMultiNum = c.numbers.length > 1;

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: isSelected
              ? _kPrimary.withValues(alpha: 0.15)
              : _kPrimary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected
                  ? _kPrimary.withValues(alpha: 0.5)
                  : Colors.transparent),
        ),
        child: Center(
          child: Text(initials.isNotEmpty ? initials : '?',
              style: const TextStyle(
                  color: _kPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
        ),
      ),
      title: Text(c.name,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: isSelected ? _kPrimary : Colors.black)),
      subtitle: hasMultiNum
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  Text(c.numbersDisplay,
                      style: TextStyle(
                          fontSize: 11,
                          color: isSelected
                              ? _kPrimary.withValues(alpha: 0.7)
                              : Colors.grey)),
                  const Text('→ ketuk untuk pilih nomor utama',
                      style: TextStyle(
                          fontSize: 10, color: _kPrimary)),
                ])
          : Text(
              c.numbers.isNotEmpty ? c.numbers.first : 'Tanpa nomor',
              style: TextStyle(
                  fontSize: 12,
                  color: isSelected
                      ? _kPrimary.withValues(alpha: 0.7)
                      : Colors.grey)),
      isThreeLine: hasMultiNum,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (c.hasDebt) ...[
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _kDanger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: _kDanger.withValues(alpha: 0.4)),
            ),
            child: Text('Ada hutang',
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.red[700],
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
        if (isSelected && !hasMultiNum)
          const Icon(Icons.check_circle_rounded,
              color: _kPrimary, size: 22)
        else
          const Icon(Icons.chevron_right,
              color: Colors.grey, size: 20),
      ]),
      onTap: () => _onCustomerTap(c),
    );
  }

  Widget _buildAddForm() {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(children: [
        _handleBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Row(children: [
            _backButton(() => setState(() {
                  _showAddForm = false;
                  _addNameCtrl.clear();
                  _addNumberCtrl.clear();
                })),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tambah Pelanggan',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                    Text('Isi informasi pelanggan baru',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[500])),
                  ]),
            ),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Form(
              key: _addFormKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: _buildAvatarPreview()),
                    const SizedBox(height: 24),
                    _formLabel('Nama Pelanggan', required: true),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _addNameCtrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty)
                              ? 'Nama pelanggan harus diisi'
                              : null,
                      decoration: _inputDeco(
                          hint: 'Contoh: Budi Santoso',
                          icon: Icons.person_outline_rounded),
                    ),
                    const SizedBox(height: 18),
                    _formLabel('Nomor / ID Pelanggan'),
                    const SizedBox(height: 2),
                    Text(
                      'Nomor telepon, ID meter, atau ID lainnya',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _addNumberCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: _inputDeco(
                          hint: 'Contoh: 081234567890 (opsional)',
                          icon: Icons.tag_rounded),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed:
                            _isSaving ? null : _saveNewCustomer,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(14)),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5))
                            : const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(
                                      Icons
                                          .person_add_alt_1_rounded,
                                      size: 20),
                                  SizedBox(width: 10),
                                  Text('Simpan Pelanggan',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight:
                                              FontWeight.w700)),
                                ],
                              ),
                      ),
                    ),
                  ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildAvatarPreview() {
    return AnimatedBuilder(
      animation: _addNameCtrl,
      builder: (_, __) {
        final name = _addNameCtrl.text.trim();
        final initials = name.isEmpty
            ? '+'
            : name
                .split(' ')
                .where((w) => w.isNotEmpty)
                .map((w) => w[0])
                .take(2)
                .join()
                .toUpperCase();
        return Column(children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _kPrimary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                  color: _kPrimary.withValues(alpha: 0.35), width: 2),
            ),
            child: Center(
              child: Text(initials,
                  style: TextStyle(
                      color: _kPrimary,
                      fontSize: name.isEmpty ? 28 : 24,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          if (name.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(name,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ]);
      },
    );
  }

  Widget _backButton(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.arrow_back_rounded,
            size: 20, color: Colors.black87),
      ),
    );
  }

  Widget _addButton(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: _kPrimary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: _kPrimary.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 3))
          ],
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add_rounded, color: Colors.white, size: 18),
          SizedBox(width: 5),
          Text('Baru',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _formLabel(String text, {bool required = false}) {
    return Row(children: [
      Text(text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _kTextMid)),
      if (required) ...[
        const SizedBox(width: 4),
        const Text('*',
            style: TextStyle(color: Colors.red, fontSize: 14)),
      ],
    ]);
  }

  InputDecoration _inputDeco(
      {required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          TextStyle(color: Colors.grey[400], fontSize: 14),
      prefixIcon: Icon(icon, color: _kPrimary, size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: _kPrimary, width: 2)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: _kDanger, width: 1.5)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: _kDanger, width: 2)),
    );
  }
}