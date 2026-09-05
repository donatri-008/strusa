import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'transaction_detail_screen.dart';
import '../import/import_transaction_screen.dart';
import '../export/export_transaction_screen.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  String _filterStatus   = 'Semua';
  String _filterCategory = 'Semua';
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<DateTime?> _showDatePicker({
    required DateTime initial,
    required String helpText,
  }) async {
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: helpText,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme:
              const ColorScheme.light(primary: Color(0xFF2196F3)),
        ),
        child: child!,
      ),
    );
  }

  // ── More Bottom Sheet ──────────────────────────────────────────────────────

  void _showMoreBottomSheet() {
    showModalBottomSheet(
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
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Kelola Transaksi',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Pilih aksi yang ingin dilakukan',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
            _actionTile(
              icon: Icons.upload_file_rounded,
              iconBgColor: const Color(0xFFE3F2FD),
              iconColor: const Color(0xFF2196F3),
              title: 'Import Transaksi',
              subtitle: 'Unggah data dari file Excel atau CSV',
              onTap: () {
                Navigator.pop(context);
                Get.to(() => const ImportTransactionScreen());
              },
            ),
            const SizedBox(height: 12),
            _actionTile(
              icon: Icons.file_download_outlined,
              iconBgColor: const Color(0xFFE8F5E9),
              iconColor: const Color(0xFF4CAF50),
              title: 'Export Transaksi',
              subtitle: 'Unduh data transaksi ke file Excel',
              onTap: () {
                Navigator.pop(context);
                Get.to(() => const ExportTransactionScreen());
              },
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
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
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        )),
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final fmt  = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Transaksi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            tooltip: 'Filter',
            onPressed: _showFilterBottomSheet,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'Lainnya',
            onPressed: _showMoreBottomSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search Bar ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Cari nomor atau nama pelanggan...',
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
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: Color(0xFF2196F3), width: 2)),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            ),
          ),

          // ── Filter Date Picker Row ────────────────────────────────────────
          _buildDateRangeRow(),

          // ── Active Filter Chips ───────────────────────────────────────────
          if (_filterStatus != 'Semua' || _filterCategory != 'Semua')
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (_filterStatus != 'Semua')
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        label: Text(_filterStatus),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () =>
                            setState(() => _filterStatus = 'Semua'),
                      ),
                    ),
                  if (_filterCategory != 'Semua')
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        label: Text(_filterCategory),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () =>
                            setState(() => _filterCategory = 'Semua'),
                      ),
                    ),
                ],
              ),
            ),

          // ── Transaction List ──────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _buildQuery(user?.uid ?? ''),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _emptyState('Tidak ada transaksi');
                }

                var filteredDocs = snapshot.data!.docs.where((doc) {
                  if (_searchQuery.isEmpty) return true;
                  final data = doc.data() as Map<String, dynamic>;
                  final num  = (data['customerNumber'] ?? '').toString().toLowerCase();
                  final name = (data['customerName'] ?? '').toString().toLowerCase();
                  final prod = (data['productName'] ?? '').toString().toLowerCase();
                  return num.contains(_searchQuery) ||
                      name.contains(_searchQuery) ||
                      prod.contains(_searchQuery);
                }).toList();

                if (filteredDocs.isEmpty) {
                  return _emptyState('Tidak ada hasil');
                }

                final groupedItems = _groupByDate(filteredDocs);

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: groupedItems.length,
                  itemBuilder: (_, i) {
                    final item = groupedItems[i];
                    if (item is _DateHeader) {
                      return _buildDateHeader(item.date, item.totalAmount, fmt);
                    } else if (item is _TransactionItem) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildTransactionCard(
                            item.docId, item.data, fmt),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Grouping per tanggal ───────────────────────────────────────────────────

  List<dynamic> _groupByDate(List<QueryDocumentSnapshot> docs) {
    final result = <dynamic>[];
    DateTime? lastDate;
    double dateTotal = 0;
    int headerIndex = -1;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final rawDate = data['date'];
      final date = rawDate != null
          ? (rawDate as Timestamp).toDate()
          : DateTime.now();
      final dateOnly = DateTime(date.year, date.month, date.day);
      final amount = (data['totalAmount'] ?? 0).toDouble();

      if (lastDate == null || !DateUtils.isSameDay(lastDate, dateOnly)) {
        if (headerIndex >= 0) {
          result[headerIndex] = _DateHeader(
            (result[headerIndex] as _DateHeader).date,
            dateTotal,
          );
        }
        dateTotal = amount;
        headerIndex = result.length;
        result.add(_DateHeader(dateOnly, 0));
        lastDate = dateOnly;
      } else {
        dateTotal += amount;
      }
      result.add(_TransactionItem(doc.id, data));
    }

    if (headerIndex >= 0) {
      result[headerIndex] = _DateHeader(
        (result[headerIndex] as _DateHeader).date,
        dateTotal,
      );
    }

    return result;
  }

  // ── Date Header Widget ─────────────────────────────────────────────────────

  Widget _buildDateHeader(DateTime date, double totalAmount, NumberFormat fmt) {
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    final isYesterday = DateUtils.isSameDay(
        date, DateTime.now().subtract(const Duration(days: 1)));

    final String label;
    if (isToday) {
      label = 'Hari ini · ${DateFormat('dd MMMM yyyy', 'id_ID').format(date)}';
    } else if (isYesterday) {
      label = 'Kemarin · ${DateFormat('dd MMMM yyyy', 'id_ID').format(date)}';
    } else {
      label = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(date);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: const Color(0xFF2196F3).withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.calendar_today_rounded,
                size: 13, color: Color(0xFF2196F3)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2196F3),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            color: const Color(0xFF2196F3).withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
          ),
          child: Text(
            fmt.format(totalAmount),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4CAF50),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Date Range Row ─────────────────────────────────────────────────────────

  Widget _buildDateRangeRow() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final picked = await _showDatePicker(
                  initial: _startDate ?? DateTime.now(),
                  helpText: 'Dari Tanggal',
                );
                if (picked != null) setState(() => _startDate = picked);
              },
              child: _dateTile(
                label: 'Dari',
                date: _startDate,
                onClear: _startDate != null
                    ? () => setState(() => _startDate = null)
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final picked = await _showDatePicker(
                  initial: _endDate ?? (_startDate ?? DateTime.now()),
                  helpText: 'Sampai Tanggal',
                );
                if (picked != null) setState(() => _endDate = picked);
              },
              child: _dateTile(
                label: 'Sampai',
                date: _endDate,
                onClear: _endDate != null
                    ? () => setState(() => _endDate = null)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime? date,
    VoidCallback? onClear,
  }) {
    final hasDate = date != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: hasDate
            ? const Color(0xFF2196F3).withValues(alpha: 0.06)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasDate
              ? const Color(0xFF2196F3).withValues(alpha: 0.4)
              : Colors.grey[300]!,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today_rounded,
              size: 15,
              color: hasDate ? const Color(0xFF2196F3) : Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        color: hasDate ? const Color(0xFF2196F3) : Colors.grey)),
                const SizedBox(height: 2),
                Text(
                  hasDate
                      ? DateFormat('dd MMM yyyy').format(date)
                      : 'Pilih tanggal',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: hasDate ? FontWeight.w600 : FontWeight.normal,
                    color: hasDate ? const Color(0xFF111827) : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          if (onClear != null)
            GestureDetector(
              onTap: onClear,
              child: Icon(Icons.close,
                  size: 14,
                  color: const Color(0xFF2196F3).withValues(alpha: 0.7)),
            )
          else
            Icon(Icons.edit_calendar_rounded,
                size: 14, color: Colors.grey[400]),
        ],
      ),
    );
  }

  // ── Firestore Query ────────────────────────────────────────────────────────

  Stream<QuerySnapshot> _buildQuery(String userId) {
    Query q = FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .orderBy('date', descending: true);

    if (_filterStatus == 'Lunas') {
      q = q.where('isPaid', isEqualTo: true);
    } else if (_filterStatus == 'Belum Lunas') {
      q = q.where('isPaid', isEqualTo: false);
    }

    if (_filterCategory != 'Semua') {
      q = q.where('category', isEqualTo: _filterCategory);
    }

    if (_startDate != null) {
      final startOfDay = DateTime(
          _startDate!.year, _startDate!.month, _startDate!.day, 0, 0, 0);
      q = q.where('date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay));
    }
    if (_endDate != null) {
      final endOfDay = DateTime(
          _endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
      q = q.where('date',
          isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));
    }

    return q.snapshots();
  }

  // ── Transaction Card ───────────────────────────────────────────────────────

  Widget _buildTransactionCard(
      String docId, Map<String, dynamic> data, NumberFormat fmt) {
    final isPaid     = data['isPaid'] ?? false;
    final isSebagian = data['isBayarSebagian'] ?? false;
    final rawDate    = data['date'];
    final date       = rawDate != null
        ? (rawDate as Timestamp).toDate()
        : DateTime.now();

    final statusColor = isSebagian && !isPaid
        ? const Color(0xFFF44336)
        : isPaid
            ? const Color(0xFF4CAF50)
            : const Color(0xFFFF9800);
    final statusLabel = isSebagian && !isPaid
        ? 'Bayar Sebagian'
        : isPaid
            ? 'Lunas'
            : 'Belum Lunas';
    final statusIcon = isSebagian && !isPaid
        ? Icons.money_off_rounded
        : isPaid
            ? Icons.check_circle
            : Icons.pending;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
          onTap: () => Get.to(() => TransactionDetailScreen(
                transactionId:   docId,
                transactionData: data,
              )),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: Color(0xFF2196F3), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['productName'] ?? 'Produk',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(data['category'] ?? '',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(statusIcon, color: statusColor, size: 11),
                      const SizedBox(width: 4),
                      Text(statusLabel,
                          style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ]),

                const Divider(height: 16),

                Row(children: [
                  Icon(Icons.access_time_rounded,
                      size: 12, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('HH:mm', 'id_ID').format(date),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ]),
                const SizedBox(height: 4),

                if ((data['customerName'] ?? '').toString().isNotEmpty) ...[
                  _cardMeta(
                    icon: Icons.person_outline,
                    text: data['customerName'],
                  ),
                  const SizedBox(height: 4),
                ],
                if ((data['customerNumber'] ?? '').toString().isNotEmpty)
                  _cardMeta(
                    icon: Icons.numbers_rounded,
                    text: data['customerNumber'],
                  ),

                const SizedBox(height: 10),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey)),
                    Text(
                      fmt.format(data['totalAmount'] ?? 0),
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2196F3)),
                    ),
                  ],
                ),

                if (isSebagian &&
                    !isPaid &&
                    (data['remainingDebt'] ?? 0) > 0) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF44336).withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFF44336)
                              .withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Sisa hutang',
                            style: TextStyle(
                                fontSize: 11, color: Colors.red[700])),
                        Text(
                          fmt.format(data['remainingDebt'] ?? 0),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.red[700]),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardMeta({
    required IconData icon,
    required String text,
    Color color = Colors.grey,
  }) =>
      Row(children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
                fontSize: 12,
                color: color == Colors.grey ? Colors.black87 : color,
                fontWeight: color == Colors.grey
                    ? FontWeight.normal
                    : FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]);

  Widget _emptyState(String msg) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.asset('assets/lottie/no_data.json',
                width: 200, height: 200),
            const SizedBox(height: 16),
            Text(msg,
                style: const TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );

  // ── Filter Bottom Sheet ────────────────────────────────────────────────────

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Filter Transaksi',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Status Pembayaran',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['Semua', 'Lunas', 'Belum Lunas']
                          .map((s) => FilterChip(
                                label: Text(s),
                                selected: _filterStatus == s,
                                onSelected: (_) => setModal(
                                    () => setState(() => _filterStatus = s)),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Kategori Produk',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        'Semua', 'Pulsa', 'Paket Data',
                        'Token Listrik', 'Tagihan', 'E-Wallet',
                        'Jasa Transfer', 'Lainnya',
                      ]
                          .map((c) => FilterChip(
                                label: Text(c),
                                selected: _filterCategory == c,
                                onSelected: (_) => setModal(
                                    () => setState(
                                        () => _filterCategory = c)),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 24),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setModal(() => setState(() {
                                _filterStatus   = 'Semua';
                                _filterCategory = 'Semua';
                                _startDate      = null;
                                _endDate        = null;
                              })),
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Terapkan'),
                        ),
                      ),
                    ]),
                  ]),
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper classes untuk grouping
// ─────────────────────────────────────────────────────────────────────────────

class _DateHeader {
  final DateTime date;
  final double totalAmount;
  const _DateHeader(this.date, this.totalAmount);
}

class _TransactionItem {
  final String docId;
  final Map<String, dynamic> data;
  const _TransactionItem(this.docId, this.data);
}