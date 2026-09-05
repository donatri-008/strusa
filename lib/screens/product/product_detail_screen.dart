import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../models/product_model.dart';
import 'edit_product_screen.dart';

// ── Design tokens ─────────────────────────────────────────────────────────
const _red   = Color(0xFFE53935);
const _green = Color(0xFF1B7F4A);
const _blue  = Color(0xFF2196F3);
const _ink   = Color(0xFF111827);
const _inkLt = Color(0xFF6B7280);
const _surf  = Color(0xFFF8FAFC);
const _bdr   = Color(0xFFE2E8F0);

class ProductDetailScreen extends StatelessWidget {
  final ProductModel product;

  const ProductDetailScreen({
    super.key,
    required this.product,
  });

  // ── Kategori helpers ──────────────────────────────────────────────────────

  /// Kategori yang menggunakan sistem Biaya Admin (bukan harga jual tetap)
  bool get _isAdminFeeCategory =>
      product.category == 'E-Wallet' ||
      product.category == 'Jasa Transfer' ||
      product.category == 'Tagihan';

  /// Kategori yang punya harga beli (dan bisa dihitung laba)
  bool get _hasCostPrice => !_isAdminFeeCategory;

  /// Hitung laba: harga jual - harga beli
  int? get _profit {
    if (!_hasCostPrice) return null;
    if (product.costPrice == null || product.costPrice! <= 0) return null;
    if (product.price <= 0) return null;
    return product.price - product.costPrice!;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      backgroundColor: _surf,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: _bdr,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Detail Produk',
          style: TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: _blue, size: 20),
            tooltip: 'Edit',
            onPressed: () => Get.to(() => EditProductScreen(
                  productId: product.id,
                  productData: product.toMap(),
                )),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: _red, size: 20),
            tooltip: 'Hapus',
            onPressed: () => _showDeleteSheet(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Hero Card ─────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _bdr),
            ),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _getCategoryColor(product.category).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getCategoryIcon(product.category),
                  size: 52,
                  color: _getCategoryColor(product.category),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                product.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: _ink),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _getCategoryColor(product.category).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _getCategoryColor(product.category).withValues(alpha: 0.3)),
                ),
                child: Text(
                  product.category,
                  style: TextStyle(
                    color: _getCategoryColor(product.category),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: product.isActive
                      ? _green.withValues(alpha: 0.08)
                      : _red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    product.isActive
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    size: 13,
                    color: product.isActive ? _green : _red,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    product.isActive ? 'Aktif' : 'Tidak Aktif',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: product.isActive ? _green : _red),
                  ),
                ]),
              ),
            ]),
          ),

          const SizedBox(height: 16),

          // ── Informasi Produk ──────────────────────────────────────────────
          _sectionCard(
            icon: Icons.info_outline_rounded,
            iconColor: _blue,
            title: 'Informasi Produk',
            child: Column(children: [
              // Kategori — selalu tampil
              _infoRow(
                'Kategori',
                product.category,
                icon: Icons.category_rounded,
                iconColor: _getCategoryColor(product.category),
              ),
              _divider(),

              // ── Cabang berdasarkan kategori ───────────────────────────────
              if (_isAdminFeeCategory) ...[
                // ── E-Wallet / Jasa Transfer / Tagihan ──────────────────────
                // Nominal: tampil jika ada, atau label "Dinamis"
                _infoRow(
                  'Nominal',
                  product.price > 0
                      ? fmt.format(product.price)
                      : 'Dinamis (input saat transaksi)',
                  icon: Icons.payments_rounded,
                  iconColor: _blue,
                ),
                _divider(),
                // Biaya Admin: selalu tampil untuk kategori ini
                _infoRow(
                  'Biaya Admin',
                  product.adminFee > 0
                      ? fmt.format(product.adminFee)
                      : 'Belum diatur',
                  icon: Icons.receipt_long_rounded,
                  iconColor: const Color(0xFF9C27B0),
                  valueColor: product.adminFee > 0 ? null : _inkLt,
                ),
              ] else ...[
                // ── Pulsa / Paket Data / Token Listrik / Lainnya ─────────────
                // Harga Jual
                _infoRow(
                  'Harga Jual',
                  product.price > 0
                      ? fmt.format(product.price)
                      : 'Belum diatur',
                  icon: Icons.sell_rounded,
                  iconColor: const Color(0xFF4CAF50),
                  valueColor: product.price > 0 ? null : _inkLt,
                ),
                // Harga Beli
                _divider(),
                _infoRow(
                  'Harga Beli',
                  (product.costPrice != null && product.costPrice! > 0)
                      ? fmt.format(product.costPrice)
                      : 'Belum diatur',
                  icon: Icons.shopping_bag_outlined,
                  iconColor: const Color(0xFF7C3AED),
                  valueColor: (product.costPrice != null && product.costPrice! > 0)
                      ? null
                      : _inkLt,
                ),
                // Laba — hanya jika keduanya terisi
                if (_profit != null) ...[
                  _divider(),
                  _infoRow(
                    'Laba per Transaksi',
                    _profit! >= 0
                        ? fmt.format(_profit)
                        : '- ${fmt.format(_profit!.abs())} (rugi)',
                    icon: _profit! >= 0
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    iconColor: _profit! >= 0 ? _green : _red,
                    valueColor: _profit! >= 0 ? _green : _red,
                  ),
                ],
              ],
            ]),
          ),

          const SizedBox(height: 16),

          // ── Statistik Penjualan ───────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('transactions')
                .where('productId', isEqualTo: product.id)
                .snapshots(),
            builder: (context, snapshot) {
              int totalTransactions = 0;
              double totalRevenue   = 0;

              if (snapshot.hasData) {
                totalTransactions = snapshot.data!.docs.length;
                for (var doc in snapshot.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  totalRevenue += (data['totalAmount'] ?? 0).toDouble();
                }
              }

              return _sectionCard(
                icon: Icons.bar_chart_rounded,
                iconColor: _green,
                title: 'Statistik Penjualan',
                child: Row(children: [
                  Expanded(
                    child: _statTile(
                      label: 'Total Transaksi',
                      value: totalTransactions.toString(),
                      icon: Icons.receipt_long_rounded,
                      color: _blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _statTile(
                      label: 'Total Pendapatan',
                      value: NumberFormat.currency(
                              locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
                          .format(totalRevenue),
                      icon: Icons.attach_money_rounded,
                      color: _green,
                    ),
                  ),
                ]),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Section Card ──────────────────────────────────────────────────────────

  Widget _sectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _bdr),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: _ink)),
          ]),
        ),
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(height: 20)),
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: child),
      ]),
    );
  }

  // ── Info Row ──────────────────────────────────────────────────────────────

  Widget _infoRow(
    String label,
    String value, {
    required IconData icon,
    required Color iconColor,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(7)),
          child: Icon(icon, size: 14, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: const TextStyle(fontSize: 13, color: _inkLt)),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? _ink),
          ),
        ),
      ]),
    );
  }

  Widget _divider() => const Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Divider(height: 16, color: _bdr));

  // ── Stat Tile ─────────────────────────────────────────────────────────────

  Widget _statTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 11, color: _inkLt)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }

  // ── Delete Sheet ──────────────────────────────────────────────────────────

  void _showDeleteSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: _bdr, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 28),
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded, color: _red, size: 28),
            ),
            const SizedBox(height: 16),
            const Text(
              'Hapus Produk?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _red.withValues(alpha: 0.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_getCategoryIcon(product.category),
                    size: 14, color: _getCategoryColor(product.category)),
                const SizedBox(width: 7),
                Text(product.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
              ]),
            ),
            const SizedBox(height: 12),
            const Text(
              'Produk yang dihapus tidak dapat dikembalikan.\nRiwayat transaksi terkait tidak akan terpengaruh.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: _inkLt, height: 1.5),
            ),
            const SizedBox(height: 28),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _inkLt,
                      side: const BorderSide(color: _bdr),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Batal',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _deleteProduct(context);
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Hapus',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ── Delete Logic ──────────────────────────────────────────────────────────

  Future<void> _deleteProduct(BuildContext context) async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      await FirebaseFirestore.instance
          .collection('products')
          .doc(product.id)
          .delete();

      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId':      user?.uid,
        'userEmail':   user?.email,
        'action':      'delete_product',
        'description': 'Menghapus produk ${product.name}',
        'timestamp':   FieldValue.serverTimestamp(),
      });

      if (!context.mounted) return;
      Get.back();
      _showSnack(context, 'Produk Dihapus',
          '${product.name} berhasil dihapus', bg: _green);
    } catch (e) {
      _showSnack(context, 'Gagal Menghapus', e.toString(), bg: _red);
    }
  }

  // ── Snackbar ──────────────────────────────────────────────────────────────

  void _showSnack(BuildContext context, String title, String msg,
      {Color bg = const Color(0xFF00897B)}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            Text(msg,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
      duration: const Duration(seconds: 3),
    ));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Pulsa':         return Icons.phone_android;
      case 'Paket Data':    return Icons.wifi;
      case 'Token Listrik': return Icons.bolt;
      case 'Tagihan':       return Icons.receipt_long;
      case 'E-Wallet':      return Icons.account_balance_wallet;
      case 'Jasa Transfer': return Icons.swap_horiz;
      default:              return Icons.widgets;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Pulsa':         return const Color(0xFF4CAF50);
      case 'Paket Data':    return const Color(0xFF2196F3);
      case 'Token Listrik': return const Color(0xFFFF9800);
      case 'Tagihan':       return const Color(0xFFFF9800);
      case 'E-Wallet':      return const Color(0xFF4CAF50);
      case 'Jasa Transfer': return const Color(0xFF9C27B0);
      default:              return const Color(0xFF2196F3);
    }
  }
}