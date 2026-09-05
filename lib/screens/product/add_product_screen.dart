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

class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey             = GlobalKey<FormState>();
  final _nameController      = TextEditingController();
  final _priceController     = TextEditingController();
  final _adminFeeController  = TextEditingController();
  final _costPriceController = TextEditingController();

  String _selectedCategory = 'Pulsa';
  bool   _isActive  = true;
  bool   _isLoading = false;

  final List<String> _categories = [
    'Pulsa', 'Paket Data', 'Token Listrik', 'Tagihan',
    'E-Wallet', 'Jasa Transfer', 'Lainnya',
  ];

  bool get _useAdminFee =>
      _selectedCategory == 'E-Wallet' ||
      _selectedCategory == 'Jasa Transfer' ||
      _selectedCategory == 'Tagihan';

  // ── Hitung laba real-time ─────────────────────────────────────────────────
  int get _hargaJual   => int.tryParse(_rawInt(_priceController.text))     ?? 0;
  int get _hargaBeli   => int.tryParse(_rawInt(_costPriceController.text)) ?? 0;
  int get _laba        => _hargaJual - _hargaBeli;
  bool get _showLaba   => _hargaJual > 0 && _hargaBeli > 0;

  @override
  void initState() {
    super.initState();
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
      appBar: AppBar(title: const Text('Tambah Produk')),
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
                hintText: 'Contoh: Pulsa Telkomsel 10.000',
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
                  _priceController.clear();
                  _adminFeeController.clear();
                  _costPriceController.clear();
                });
              },
            ),
            const SizedBox(height: 16),

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

            // ── Conditional fields ────────────────────────────────────────
            if (_useAdminFee) ...[
              // Nominal (opsional)
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

              // Biaya Admin
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
              const SizedBox(height: 16),

              // Harga Beli (hanya untuk non admin-fee khusus)
              if (_selectedCategory != 'Jasa Transfer' &&
                  _selectedCategory != 'E-Wallet' &&
                  _selectedCategory != 'Tagihan')
                TextFormField(
                  controller: _costPriceController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_ThousandSeparatorFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Harga Beli',
                    hintText: 'Contoh: 10.000',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                    prefixText: 'Rp ',
                    border: OutlineInputBorder(),
                  ),
                ),
            ] else ...[
              // Harga Beli (opsional) — di atas Harga Jual
              TextFormField(
                controller: _costPriceController,
                keyboardType: TextInputType.number,
                inputFormatters: [_ThousandSeparatorFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Harga Beli (Opsional)',
                  hintText: 'Contoh: 10.000',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

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
                const SizedBox(height: 8),
                _buildLabaInfo(fmt),
              ],
            ],

            // ── Status ───────────────────────────────────────────────────
            const SizedBox(height: 4),
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
                onPressed: _isLoading ? null : _saveProduct,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Simpan Produk'),
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

  Future<void> _saveProduct() async {
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

      await FirebaseFirestore.instance.collection('products').add({
        'userId':    user?.uid,
        'userEmail': user?.email,
        'name':      _nameController.text.trim(),
        'category':  _selectedCategory,
        'price':     price,
        if (_selectedCategory != 'Jasa Transfer' &&
            _selectedCategory != 'E-Wallet' &&
            _selectedCategory != 'Tagihan')
          'costPrice': int.tryParse(_rawInt(_costPriceController.text)) ?? 0,
        'adminFee':  adminFee,
        'isActive':  _isActive,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId':      user?.uid,
        'userEmail':   user?.email,
        'action':      'create_product',
        'description': 'Menambahkan produk: ${_nameController.text}',
        'timestamp':   FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Get.back();
        AppNotification.productSaved(_nameController.text.trim());
      }
    } catch (e) {
      AppNotification.saveFailed();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}