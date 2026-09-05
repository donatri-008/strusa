import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
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

String _fmtThousand(dynamic value) {
  if (value == null) return '';
  final n = value is int ? value : int.tryParse(value.toString()) ?? 0;
  if (n == 0) return '';
  return NumberFormat('#,##0', 'id_ID').format(n).replaceAll(',', '.');
}

class EditProductScreen extends StatefulWidget {
  final String productId;
  final Map<String, dynamic> productData;

  const EditProductScreen({
    super.key,
    required this.productId,
    required this.productData,
  });

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey             = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _adminFeeController;
  late TextEditingController _costPriceController;

  late String _selectedCategory;
  late bool   _isActive;
  bool        _isLoading = false;

  final List<String> _categories = [
    'Pulsa', 'Paket Data', 'Token Listrik', 'Tagihan',
    'E-Wallet', 'Jasa Transfer', 'Lainnya',
  ];

  bool get _useAdminFee =>
      _selectedCategory == 'E-Wallet' ||
      _selectedCategory == 'Jasa Transfer' ||
      _selectedCategory == 'Tagihan';

  // ── Hitung laba real-time ─────────────────────────────────────────────────
  int get _hargaJual  => int.tryParse(_rawInt(_priceController.text))     ?? 0;
  int get _hargaBeli  => int.tryParse(_rawInt(_costPriceController.text)) ?? 0;
  int get _laba       => _hargaJual - _hargaBeli;
  bool get _showLaba  => !_useAdminFee && _hargaJual > 0 && _hargaBeli > 0;

  @override
  void initState() {
    super.initState();
    _nameController      = TextEditingController(text: widget.productData['name']);
    _priceController     = TextEditingController(text: _fmtThousand(widget.productData['price']));
    _adminFeeController  = TextEditingController(text: _fmtThousand(widget.productData['adminFee']));
    _costPriceController = TextEditingController(text: _fmtThousand(widget.productData['costPrice']));
    _selectedCategory    = widget.productData['category'] ?? 'Pulsa';
    _isActive            = widget.productData['isActive'] ?? true;

    _priceController.addListener(() => setState(() {}));
    _costPriceController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _adminFeeController.dispose();
    _costPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Produk')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Nama Produk ──────────────────────────────────────────────
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nama Produk',
                prefixIcon: Icon(Icons.label),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Nama produk harus diisi' : null,
            ),
            const SizedBox(height: 16),

            // ── Kategori ─────────────────────────────────────────────────
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Kategori',
                prefixIcon: Icon(Icons.category),
                border: OutlineInputBorder(),
              ),
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCategory = value!;
                  if (_useAdminFee) {
                    _priceController.clear();
                  } else {
                    _adminFeeController.clear();
                  }
                });
              },
            ),
            const SizedBox(height: 16),

            // ── Harga Beli (untuk non-admin-fee khusus) ──────────────────
            if (_selectedCategory != 'Jasa Transfer' &&
                _selectedCategory != 'E-Wallet' &&
                _selectedCategory != 'Tagihan') ...[
              TextFormField(
                controller: _costPriceController,
                keyboardType: TextInputType.number,
                inputFormatters: [_ThousandSeparatorFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Harga Beli (Opsional)',
                  hintText: 'Contoh: 8.000',
                  prefixIcon: Icon(Icons.shopping_cart),
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v != null && v.isNotEmpty &&
                      int.tryParse(_rawInt(v)) == null) {
                    return 'Harga beli harus berupa angka';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],

            // ── Info ─────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _useAdminFee
                        ? 'Kategori ini menggunakan sistem biaya admin. Nominal transaksi + biaya admin.'
                        : 'Kategori ini menggunakan harga jual tetap.',
                    style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // ── Conditional: Harga Jual atau Biaya Admin ─────────────────
            if (_useAdminFee) ...[
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                inputFormatters: [_ThousandSeparatorFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Nominal (Opsional)',
                  hintText: 'Kosongkan jika nominal dinamis',
                  prefixIcon: Icon(Icons.payments),
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(),
                  helperText: 'Kosongkan jika pelanggan input manual',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _adminFeeController,
                keyboardType: TextInputType.number,
                inputFormatters: [_ThousandSeparatorFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Biaya Admin',
                  hintText: 'Contoh: 1.500',
                  prefixIcon: Icon(Icons.receipt_long),
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Biaya admin harus diisi';
                  if (int.tryParse(_rawInt(v)) == null) return 'Biaya admin harus berupa angka';
                  return null;
                },
              ),
            ] else ...[
              // Harga Jual
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                inputFormatters: [_ThousandSeparatorFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Harga Jual',
                  hintText: 'Contoh: 12.000',
                  prefixIcon: Icon(Icons.sell),
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Harga jual harus diisi';
                  if (int.tryParse(_rawInt(v)) == null) return 'Harga jual harus berupa angka';
                  return null;
                },
              ),

              // ── Keterangan Laba ──────────────────────────────────────
              if (_showLaba) ...[
                const SizedBox(height: 10),
                _buildLabaInfo(fmt),
              ],
            ],

            const SizedBox(height: 16),

            // ── Status ───────────────────────────────────────────────────
            SwitchListTile(
              title: const Text('Status Produk'),
              subtitle: Text(_isActive ? 'Aktif' : 'Nonaktif'),
              value: _isActive,
              activeThumbColor: const Color(0xFF2196F3),
              onChanged: (v) => setState(() => _isActive = v),
            ),
            const SizedBox(height: 24),

            // ── Simpan ───────────────────────────────────────────────────
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _updateProduct,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Simpan Perubahan'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Widget keterangan laba ────────────────────────────────────────────────
  Widget _buildLabaInfo(NumberFormat fmt) {
    final isRugi  = _laba < 0;
    final isImpas = _laba == 0;
    final color   = isRugi  ? const Color(0xFFE53935)
                  : isImpas ? const Color(0xFFFF9800)
                  :           const Color(0xFF4CAF50);
    final label   = isRugi  ? 'Rugi' : isImpas ? 'Impas' : 'Laba';
    final nominal = isImpas ? 'Rp 0' : fmt.format(_laba.abs());

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        '$label: $nominal',
        style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _updateProduct() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;

      final int? price = _priceController.text.isNotEmpty
          ? int.tryParse(_rawInt(_priceController.text))
          : null;
      final int adminFee = _useAdminFee
          ? (int.tryParse(_rawInt(_adminFeeController.text)) ?? 0)
          : 0;

      await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.productId)
          .update({
        'name':      _nameController.text.trim(),
        'category':  _selectedCategory,
        'price':     price,
        'adminFee':  adminFee,
        if (_selectedCategory != 'Jasa Transfer' &&
            _selectedCategory != 'E-Wallet' &&
            _selectedCategory != 'Tagihan')
          'costPrice': int.tryParse(_rawInt(_costPriceController.text)) ?? 0,
        'isActive':  _isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId':      user?.uid,
        'userEmail':   user?.email,
        'action':      'update_product',
        'description': 'Mengupdate produk: ${_nameController.text}',
        'timestamp':   FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Get.back();
        AppNotification.updated('Produk "${_nameController.text.trim()}" berhasil diperbarui');
      }
    } catch (e) {
      AppNotification.saveFailed();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}