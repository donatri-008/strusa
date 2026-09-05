import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import '../../models/product_model.dart';
import 'add_product_screen.dart';
import 'product_detail_screen.dart';
import '../import/import_product_screen.dart';
import '../export/export_product_screen.dart';

// ── Design tokens ─────────────────────────────────────────────────────────
const _blue  = Color(0xFF2196F3);
const _green = Color(0xFF1B7F4A);

// ── Helper format ribuan ──────────────────────────────────────────────────
String _fmtRupiah(int value) =>
    NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0)
        .format(value);

// ── Custom menu entry model ───────────────────────────────────────────────
class _MenuEntry {
  final String value;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool isDividerAbove;

  const _MenuEntry({
    required this.value,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.isDividerAbove = false,
  });
}

class ProductListScreen extends StatefulWidget {
  final bool isSelectionMode;

  const ProductListScreen({
    super.key,
    this.isSelectionMode = false,
  });

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  String _selectedCategory = 'Semua';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  final List<String> _categories = [
    'Semua',
    'Pulsa',
    'Paket Data',
    'Token Listrik',
    'Tagihan',
    'E-Wallet',
    'Jasa Transfer',
    'Lainnya',
  ];

  // ── Menu entries ──────────────────────────────────────────────────────────
  static const _menuEntries = [
    _MenuEntry(
      value: 'add',
      icon: Icons.add_rounded,
      color: _blue,
      title: 'Tambah Produk',
      subtitle: 'Buat produk baru',
    ),
    _MenuEntry(
      value: 'import',
      icon: Icons.file_upload_outlined,
      color: _green,
      title: 'Import Produk',
      subtitle: 'Unggah file Excel/CSV',
      isDividerAbove: true,
    ),
    _MenuEntry(
      value: 'export',
      icon: Icons.file_download_outlined,
      color: _green,
      title: 'Ekspor Produk',
      subtitle: 'Unduh ke Excel/CSV',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Show custom popup menu ────────────────────────────────────────────────
  void _showCustomMenu(BuildContext context) async {
    // Find the AppBar's overflow button position
    final RenderBox button = context.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final result = await showMenu<String>(
      context: context,
      position: position,
      color: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 280),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _CustomMenuContent(
            entries: _menuEntries,
            onSelected: (val) => Navigator.of(context).pop(val),
          ),
        ),
      ],
    );

    if (result != null) _handleMenuAction(result);
  }

  void _handleMenuAction(String val) {
    switch (val) {
      case 'add':
        Get.to(() => const AddProductScreen());
        break;
      case 'import':
        Get.to(() => const ImportProductScreen());
        break;
      case 'export':
        Get.to(() => const ExportProductScreen());
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isSelectionMode ? 'Pilih Produk' : 'Produk PPOB'),
        actions: [
          if (!widget.isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: 'Import Produk',
              onPressed: () => Get.to(() => const ImportProductScreen()),
            ),
            // ── Custom menu button ──────────────────────────────────────
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.more_vert),
                tooltip: 'Lainnya',
                onPressed: () => _showCustomMenu(ctx),
              ),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // ── Search Bar ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Cari produk...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _searchQuery = '';
                        }),
                      )
                    : null,
              ),
              onChanged: (value) =>
                  setState(() => _searchQuery = value.toLowerCase()),
            ),
          ),

          // ── Category Filter ───────────────────────────────────────────
          Container(
            height: 46,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category  = _categories[index];
                final isSelected = _selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (_) =>
                        setState(() => _selectedCategory = category),
                    backgroundColor: Colors.white,
                    selectedColor: _blue,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Product List ──────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _buildQuery(user?.uid ?? ''),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Lottie.asset('assets/lottie/no_data.json',
                            width: 200, height: 200),
                        const SizedBox(height: 16),
                        const Text('Belum ada produk',
                            style: TextStyle(fontSize: 16, color: Colors.grey)),
                        if (!widget.isSelectionMode) ...[
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _ctaButton(
                                icon: Icons.add,
                                label: 'Tambah Produk',
                                color: _blue,
                                onTap: () =>
                                    Get.to(() => const AddProductScreen()),
                              ),
                              const SizedBox(width: 12),
                              _ctaButton(
                                icon: Icons.file_upload_outlined,
                                label: 'Import',
                                color: _green,
                                onTap: () =>
                                    Get.to(() => const ImportProductScreen()),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                }

                var filteredDocs = snapshot.data!.docs.where((doc) {
                  if (_searchQuery.isEmpty) return true;
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  return name.contains(_searchQuery);
                }).toList();

                if (filteredDocs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Lottie.asset('assets/lottie/no_data.json',
                            width: 200, height: 200),
                        const SizedBox(height: 16),
                        const Text('Tidak ada hasil',
                            style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final doc  = filteredDocs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final product = ProductModel.fromMap(doc.id, data);
                    return _buildProductCard(product);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: widget.isSelectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Get.to(() => const AddProductScreen()),
              backgroundColor: _blue,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Tambah',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
    );
  }

  // ── CTA Button ────────────────────────────────────────────────────────────

  Widget _ctaButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  Stream<QuerySnapshot> _buildQuery(String userId) {
    Query query = FirebaseFirestore.instance
        .collection('products')
        .where('userId', isEqualTo: userId)
        .where('isActive', isEqualTo: true)
        .orderBy('name');

    if (_selectedCategory != 'Semua') {
      query = query.where('category', isEqualTo: _selectedCategory);
    }

    return query.snapshots();
  }

  // ── Product Card ──────────────────────────────────────────────────────────

  Widget _buildProductCard(ProductModel product) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (widget.isSelectionMode) {
              Get.back(result: product);
            } else {
              Get.to(() => ProductDetailScreen(product: product));
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _getCategoryColor(product.category)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getCategoryIcon(product.category),
                    color: _getCategoryColor(product.category),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        product.category,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      ..._buildPriceInfo(product),
                    ],
                  ),
                ),
                Icon(
                  widget.isSelectionMode
                      ? Icons.arrow_forward_ios
                      : Icons.chevron_right,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPriceInfo(ProductModel product) {
    final cat = product.category;
    final rows = <Widget>[];
    final bool isAdminFeeCategory =
        cat == 'E-Wallet' || cat == 'Jasa Transfer' || cat == 'Tagihan';

    if (isAdminFeeCategory) {
      if (product.price > 0) {
        rows.add(_infoChip(
          icon: Icons.payments_outlined,
          label: 'Nominal',
          value: _fmtRupiah(product.price),
          color: const Color(0xFF2196F3),
        ));
      }
      if (product.adminFee > 0) {
        rows.add(_infoChip(
          icon: Icons.receipt_long_outlined,
          label: 'Biaya Admin',
          value: _fmtRupiah(product.adminFee),
          color: const Color(0xFF9C27B0),
        ));
      }
    } else {
      if (product.price > 0) {
        rows.add(_infoChip(
          icon: Icons.sell_outlined,
          label: 'Harga Jual',
          value: _fmtRupiah(product.price),
          color: const Color(0xFF4CAF50),
        ));
      }
      final costPrice = product.costPrice ?? 0;
      if (costPrice > 0) {
        rows.add(_infoChip(
          icon: Icons.shopping_cart_outlined,
          label: 'Harga Beli',
          value: _fmtRupiah(costPrice),
          color: const Color(0xFFFF9800),
        ));
      }
      if (product.price > 0 && costPrice > 0) {
        final laba = product.price - costPrice;
        rows.add(_infoChip(
          icon: laba >= 0
              ? Icons.trending_up_rounded
              : Icons.trending_down_rounded,
          label: 'Laba',
          value: _fmtRupiah(laba.abs()) + (laba < 0 ? ' (rugi)' : ''),
          color: laba >= 0
              ? const Color(0xFF1B7F4A)
              : const Color(0xFFE53935),
        ));
      }
    }

    if (rows.isEmpty) {
      rows.add(
        Text('Harga belum diatur',
            style: TextStyle(fontSize: 11, color: Colors.grey[400])),
      );
    }

    return rows;
  }

  Widget _infoChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text('$label: ',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500)),
          Text(value,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

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

// ── Custom Menu Content Widget ────────────────────────────────────────────────
//
// Widget terpisah agar state-nya bersih dan mudah dimodifikasi.

class _CustomMenuContent extends StatelessWidget {
  final List<_MenuEntry> entries;
  final ValueChanged<String> onSelected;

  const _CustomMenuContent({
    required this.entries,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header label ──────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'Kelola Produk',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2196F3),
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const Divider(height: 1, thickness: 0.5),

            // ── Menu items ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: entries.map((entry) {
                  return _buildMenuTile(context, entry);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTile(BuildContext context, _MenuEntry entry) {
    final isFirst = entries.first == entry;
    final bgColor = isFirst
        ? entry.color.withValues(alpha: 0.07)
        : Colors.transparent;
    final titleColor = isFirst ? entry.color : Colors.black87;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (entry.isDividerAbove) ...[
          const SizedBox(height: 4),
          Divider(height: 1, thickness: 0.5, color: Colors.grey[200]),
          const SizedBox(height: 4),
        ],
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelected(entry.value),
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  // ── Icon container ──────────────────────────────────
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: entry.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(entry.icon, color: entry.color, size: 18),
                  ),
                  const SizedBox(width: 12),

                  // ── Text ────────────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: titleColor,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Trailing chevron ─────────────────────────────────
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 12,
                    color: Colors.grey[350],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}