import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import '../transaction/transaction_detail_screen.dart';

class TransactionTab extends StatefulWidget {
  const TransactionTab({super.key});

  @override
  TransactionTabState createState() => TransactionTabState();
}

class TransactionTabState extends State<TransactionTab> {
  String _filterCategory = 'Semua';
  String _filterStatus = 'Semua';
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(); // ✅ FocusNode agar keyboard tidak tutup
  String _searchQuery = '';
  String? _userId; // ✅ Simpan userId di state, bukan dari StreamBuilder

  @override
  void initState() {
    super.initState();
    // ✅ Ambil userId sekali saja di initState, bukan di build
    _userId = FirebaseAuth.instance.currentUser?.uid;

    // ✅ Listen perubahan auth jika user login/logout
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted) {
        setState(() => _userId = user?.uid);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose(); // ✅ Dispose FocusNode
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
          colorScheme: const ColorScheme.light(primary: Color(0xFF2196F3)),
        ),
        child: child!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    // ✅ Tidak ada lagi StreamBuilder<User?> di sini — tidak akan rebuild dari awal
    if (_userId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          // ── Search Bar ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode, // ✅ Pasang FocusNode
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
                  onChanged: (v) =>
                      setState(() => _searchQuery = v.toLowerCase()),
                ),
                const SizedBox(height: 12),
                _buildDateRangeRow(),
                if (_filterStatus != 'Semua' ||
                    _filterCategory != 'Semua') ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        if (_filterStatus != 'Semua')
                          _activeFilterChip(
                            label: _filterStatus,
                            onDeleted: () =>
                                setState(() => _filterStatus = 'Semua'),
                          ),
                        if (_filterCategory != 'Semua')
                          _activeFilterChip(
                            label: _filterCategory,
                            onDeleted: () =>
                                setState(() => _filterCategory = 'Semua'),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Transaction List ──────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                setState(() {});
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: StreamBuilder<QuerySnapshot>(
                stream: _buildQuery(_userId!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildSkeletonList();
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height - 200,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Lottie.asset(
                                'assets/lottie/no_data.json',
                                width: 200,
                                height: 200,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Belum ada transaksi',
                                style: TextStyle(
                                    fontSize: 16, color: Colors.grey),
                              ),
                              if (_filterStatus != 'Semua' ||
                                  _filterCategory != 'Semua' ||
                                  _startDate != null ||
                                  _endDate != null) ...[
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _filterStatus = 'Semua';
                                      _filterCategory = 'Semua';
                                      _startDate = null;
                                      _endDate = null;
                                    });
                                  },
                                  icon: const Icon(Icons.clear),
                                  label: const Text('Reset Filter'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  var filteredDocs = snapshot.data!.docs.where((doc) {
                    if (_searchQuery.isEmpty) return true;
                    final data = doc.data() as Map<String, dynamic>;
                    final num = (data['customerNumber'] ?? '')
                        .toString()
                        .toLowerCase();
                    final name = (data['customerName'] ?? '')
                        .toString()
                        .toLowerCase();
                    final prod = (data['productName'] ?? '')
                        .toString()
                        .toLowerCase();
                    return num.contains(_searchQuery) ||
                        name.contains(_searchQuery) ||
                        prod.contains(_searchQuery);
                  }).toList();

                  if (filteredDocs.isEmpty) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height - 200,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Lottie.asset(
                                  'assets/lottie/no_data.json',
                                  width: 200,
                                  height: 200),
                              const SizedBox(height: 16),
                              const Text('Tidak ada hasil',
                                  style: TextStyle(
                                      fontSize: 16, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  final groupedItems = _groupByDate(filteredDocs);

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: groupedItems.length,
                    itemBuilder: (context, index) {
                      final item = groupedItems[index];
                      if (item is _DateHeader) {
                        return _buildDateHeader(
                            item.date, item.totalAmount, currencyFormat);
                      } else if (item is _TransactionItem) {
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildTransactionCard(
                            item.docId,
                            item.data,
                            currencyFormat,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Skeleton Loading ───────────────────────────────────────────────────────

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index == 0 || index == 3)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    _SkeletonBox(width: 160, height: 28, radius: 20),
                    SizedBox(width: 8),
                    Expanded(child: _SkeletonBox(height: 1, radius: 1)),
                    SizedBox(width: 8),
                    _SkeletonBox(width: 80, height: 26, radius: 16),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildSkeletonCard(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
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
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SkeletonBox(width: 38, height: 38, radius: 10),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonBox(width: 140, height: 14, radius: 6),
                    SizedBox(height: 6),
                    _SkeletonBox(width: 80, height: 11, radius: 6),
                  ],
                ),
              ),
              _SkeletonBox(width: 70, height: 24, radius: 8),
            ],
          ),
          SizedBox(height: 12),
          _SkeletonBox(width: double.infinity, height: 1, radius: 1),
          SizedBox(height: 12),
          _SkeletonBox(width: 60, height: 11, radius: 6),
          SizedBox(height: 8),
          _SkeletonBox(width: 120, height: 11, radius: 6),
          SizedBox(height: 8),
          _SkeletonBox(width: 100, height: 11, radius: 6),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SkeletonBox(width: 40, height: 13, radius: 6),
              _SkeletonBox(width: 100, height: 18, radius: 6),
            ],
          ),
        ],
      ),
    );
  }

  // ── Date Range Row ─────────────────────────────────────────────────────────

  Widget _buildDateRangeRow() {
    return Row(
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
                        color: hasDate
                            ? const Color(0xFF2196F3)
                            : Colors.grey)),
                const SizedBox(height: 2),
                Text(
                  hasDate
                      ? DateFormat('dd MMM yyyy').format(date)
                      : 'Pilih tanggal',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        hasDate ? FontWeight.w600 : FontWeight.normal,
                    color:
                        hasDate ? const Color(0xFF111827) : Colors.grey,
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
                  color:
                      const Color(0xFF2196F3).withValues(alpha: 0.7)),
            )
          else
            Icon(Icons.edit_calendar_rounded,
                size: 14, color: Colors.grey[400]),
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

  Widget _buildDateHeader(
      DateTime date, double totalAmount, NumberFormat currencyFormat) {
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    final isYesterday = DateUtils.isSameDay(
        date, DateTime.now().subtract(const Duration(days: 1)));

    final String label;
    if (isToday) {
      label =
          'Hari ini · ${DateFormat('dd MMMM yyyy', 'id_ID').format(date)}';
    } else if (isYesterday) {
      label =
          'Kemarin · ${DateFormat('dd MMMM yyyy', 'id_ID').format(date)}';
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
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
          ),
          child: Text(
            currencyFormat.format(totalAmount),
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

  // ── Firestore Query ────────────────────────────────────────────────────────

  Stream<QuerySnapshot> _buildQuery(String userId) {
    Query query = FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .orderBy('date', descending: true);

    if (_filterStatus == 'Lunas') {
      query = query.where('isPaid', isEqualTo: true);
    } else if (_filterStatus == 'Belum Lunas') {
      query = query.where('isPaid', isEqualTo: false);
    }

    if (_filterCategory != 'Semua') {
      query = query.where('category', isEqualTo: _filterCategory);
    }

    if (_startDate != null) {
      final startOfDay = DateTime(
          _startDate!.year, _startDate!.month, _startDate!.day, 0, 0, 0);
      query = query.where('date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay));
    }
    if (_endDate != null) {
      final endOfDay = DateTime(
          _endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
      query = query.where('date',
          isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));
    }

    return query.snapshots();
  }

  Widget _buildTransactionCard(
    String docId,
    Map<String, dynamic> data,
    NumberFormat currencyFormat,
  ) {
    final isPaid = data['isPaid'] ?? false;
    final isSebagian = data['isBayarSebagian'] ?? false;
    final date = (data['date'] as Timestamp).toDate();

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
          onTap: () {
            Get.to(() => TransactionDetailScreen(
                  transactionId: docId,
                  transactionData: data,
                ));
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color:
                            const Color(0xFF2196F3).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: Color(0xFF2196F3),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['productName'] ?? 'Produk',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            data['category'] ?? 'Kategori',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
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
                      child:
                          Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(statusIcon, color: statusColor, size: 11),
                        const SizedBox(width: 4),
                        Text(statusLabel,
                            style: TextStyle(
                                color: statusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Row(children: [
                  Icon(Icons.access_time_rounded,
                      size: 12, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('HH:mm', 'id_ID').format(date),
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[500]),
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
                    const Text(
                      'Total',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    Text(
                      currencyFormat.format(data['totalAmount'] ?? 0),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2196F3),
                      ),
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
                      color: const Color(0xFFF44336)
                          .withValues(alpha: 0.06),
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
                          currencyFormat
                              .format(data['remainingDebt'] ?? 0),
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

  // ── Filter Bottom Sheet ────────────────────────────────────────────────────

  void showFilterBottomSheet() {
    const primaryBlue = Color(0xFF2196F3);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          Widget sectionLabel(String text, IconData icon) => Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: primaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 14, color: primaryBlue),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827),
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              );

          Widget blueChip(
            String label,
            bool isSelected,
            VoidCallback onTap,
          ) =>
              GestureDetector(
                onTap: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primaryBlue
                        : primaryBlue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? primaryBlue
                          : primaryBlue.withValues(alpha: 0.25),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF374151),
                    ),
                  ),
                ),
              );

          const statusOptions = ['Semua', 'Lunas', 'Belum Lunas'];
          const categoryOptions = [
            'Semua',
            'Pulsa',
            'Paket Data',
            'Token Listrik',
            'Tagihan',
            'E-Wallet',
            'Jasa Transfer',
            'Lainnya',
          ];

          final bool hasActiveFilter =
              _filterStatus != 'Semua' || _filterCategory != 'Semua';

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 16, 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.tune_rounded,
                            color: primaryBlue, size: 18),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Filter Transaksi',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const Spacer(),
                      if (hasActiveFilter)
                        GestureDetector(
                          onTap: () {
                            setModalState(() {
                              _filterStatus = 'Semua';
                              _filterCategory = 'Semua';
                            });
                            setState(() {
                              _filterStatus = 'Semua';
                              _filterCategory = 'Semua';
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF44336)
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: const Color(0xFFF44336)
                                      .withValues(alpha: 0.25)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.refresh_rounded,
                                    size: 12, color: Color(0xFFF44336)),
                                SizedBox(width: 4),
                                Text(
                                  'Reset',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFF44336),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(height: 1, color: Colors.grey[100]),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sectionLabel(
                          'Status Pembayaran', Icons.payment_rounded),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: statusOptions
                            .map((s) => blueChip(
                                  s,
                                  _filterStatus == s,
                                  () {
                                    setModalState(
                                        () => _filterStatus = s);
                                    setState(() => _filterStatus = s);
                                  },
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 20),
                      Container(height: 1, color: Colors.grey[100]),
                      const SizedBox(height: 20),
                      sectionLabel(
                          'Kategori Produk', Icons.category_rounded),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: categoryOptions
                            .map((c) => blueChip(
                                  c,
                                  _filterCategory == c,
                                  () {
                                    setModalState(
                                        () => _filterCategory = c);
                                    setState(() => _filterCategory = c);
                                  },
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {});
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text(
                            'Terapkan Filter',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                    height: MediaQuery.of(context).padding.bottom + 12),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _activeFilterChip({
    required String label,
    required VoidCallback onDeleted,
  }) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF2196F3).withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2196F3),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onDeleted,
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Color(0xFF2196F3),
                ),
              ),
            ],
          ),
        ),
      );

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
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton Box Widget — shimmer animasi
// ─────────────────────────────────────────────────────────────────────────────

class _SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const _SkeletonBox({
    this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(widget.radius),
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