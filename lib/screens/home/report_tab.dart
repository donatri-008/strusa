import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class ReportTab extends StatefulWidget {
  const ReportTab({super.key});

  @override
  State<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends State<ReportTab> {
  DateTime _selectedDate = DateTime.now();
  String _reportType = 'Harian';

  // ── Rentang tanggal berdasarkan tipe laporan ──────────────────────────────
  DateTimeRange get _dateRange {
    if (_reportType == 'Harian') {
      final start = DateTime(
          _selectedDate.year, _selectedDate.month, _selectedDate.day);
      final end = DateTime(
          _selectedDate.year, _selectedDate.month, _selectedDate.day,
          23, 59, 59);
      return DateTimeRange(start: start, end: end);
    } else if (_reportType == 'Mingguan') {
      final daysFromSunday = _selectedDate.weekday % 7;
      final sunday   = _selectedDate.subtract(Duration(days: daysFromSunday));
      final start    = DateTime(sunday.year, sunday.month, sunday.day);
      final saturday = start.add(const Duration(days: 6)); // +6 hari = Sabtu
      final end      = DateTime(saturday.year, saturday.month, saturday.day, 23, 59, 59);
      return DateTimeRange(start: start, end: end);
    } else {
      // Bulanan
      final start = DateTime(_selectedDate.year, _selectedDate.month, 1);
      final end = DateTime(
          _selectedDate.year, _selectedDate.month + 1, 0, 23, 59, 59);
      return DateTimeRange(start: start, end: end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    // ── FIX: Wrap dengan authStateChanges agar uid tidak null saat login baru
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        final user = authSnapshot.data;

        if (authSnapshot.connectionState == ConnectionState.waiting ||
            user == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return SingleChildScrollView(
          child: Column(
            children: [
              // ── Tipe Laporan ──────────────────────────────────────────
              Container(
                margin: const EdgeInsets.all(16),
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
                child: Row(
                  children: [
                    Expanded(child: _buildTypeButton('Harian')),
                    Expanded(child: _buildTypeButton('Mingguan')),
                    Expanded(child: _buildTypeButton('Bulanan')),
                  ],
                ),
              ),

              // ── Pemilih Periode ───────────────────────────────────────
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
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
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _getDateText(),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _previousPeriod,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.calendar_today, size: 18),
                      onPressed: _selectDate,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _nextPeriod,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Data ──────────────────────────────────────────────────
              StreamBuilder<QuerySnapshot>(
                stream: _getTransactionsStream(user.uid), // ← uid dijamin tidak null
                builder: (context, snapTx) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: _getKasKeluarStream(user.uid), // ← uid dijamin tidak null
                    builder: (context, snapKk) {
                      if (snapTx.connectionState ==
                              ConnectionState.waiting ||
                          snapKk.connectionState ==
                              ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child:
                              Center(child: CircularProgressIndicator()),
                        );
                      }

                      double totalSales = 0;
                      double totalPaid = 0;
                      double totalUnpaid = 0;
                      double profitKotor = 0;
                      int totalTx = snapTx.data?.docs.length ?? 0;

                      if (snapTx.hasData) {
                        for (final doc in snapTx.data!.docs) {
                          final d =
                              doc.data() as Map<String, dynamic>;
                          final totalAmount =
                              (d['totalAmount'] ?? 0).toDouble();
                          final adminFee =
                              (d['adminFee'] ?? 0).toDouble();
                          final hargaBeli =
                              (d['hargaBeli'] ?? 0).toDouble();
                          final hargaJual =
                              (d['nominal'] ?? 0).toDouble();
                          final isPaid = d['isPaid'] ?? false;

                          final selisih = hargaBeli > 0
                              ? (hargaJual - hargaBeli)
                              : 0.0;
                          profitKotor += selisih + adminFee;
                          totalSales += totalAmount;
                          if (isPaid) {
                            totalPaid += totalAmount;
                          } else {
                            totalUnpaid += totalAmount;
                          }
                        }
                      }

                      double totalKasKeluar = 0;
                      double potonganLaba = 0;

                      if (snapKk.hasData) {
                        for (final doc in snapKk.data!.docs) {
                          final d =
                              doc.data() as Map<String, dynamic>;
                          final amount =
                              (d['amount'] ?? 0).toDouble();
                          final kurangiLaba =
                              d['kurangiLaba'] ?? true;

                          totalKasKeluar += amount;
                          if (kurangiLaba == true) {
                            potonganLaba += amount;
                          }
                        }
                      }

                      final totalKeuntunganBersih =
                          profitKotor - potonganLaba;

                      return Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16),
                            child: GridView.count(
                              shrinkWrap: true,
                              physics:
                                  const NeverScrollableScrollPhysics(),
                              crossAxisCount: 2,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 1.2,
                              children: [
                                _summaryCard('Total Transaksi',
                                    totalTx.toString(),
                                    Icons.receipt_long_rounded,
                                    const Color(0xFF2196F3)),
                                _summaryCard('Total Penjualan',
                                    fmt.format(totalSales),
                                    Icons.attach_money_rounded,
                                    const Color(0xFF4CAF50)),
                                _summaryCard('Lunas',
                                    fmt.format(totalPaid),
                                    Icons.check_circle_outline,
                                    const Color(0xFF00BCD4)),
                                _summaryCard('Piutang',
                                    fmt.format(totalUnpaid),
                                    Icons.pending_outlined,
                                    const Color(0xFFFF9800)),
                                _summaryCard('Kas Keluar',
                                    fmt.format(totalKasKeluar),
                                    Icons.arrow_upward_rounded,
                                    const Color(0xFFEF4444)),
                                _summaryCard(
                                    'Total Keuntungan',
                                    fmt.format(totalKeuntunganBersih),
                                    totalKeuntunganBersih >= 0
                                        ? Icons.trending_up_rounded
                                        : Icons.trending_down_rounded,
                                    totalKeuntunganBersih >= 0
                                        ? const Color(0xFF4CAF50)
                                        : const Color(0xFFEF4444)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (totalKasKeluar > potonganLaba)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6)
                                      .withValues(alpha: 0.08),
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  border: Border.all(
                                      color: const Color(0xFF8B5CF6)
                                          .withValues(alpha: 0.25)),
                                ),
                                child: Row(children: [
                                  const Icon(
                                      Icons.info_outline_rounded,
                                      color: Color(0xFF8B5CF6),
                                      size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${fmt.format(totalKasKeluar - potonganLaba)} kas keluar tidak mempengaruhi keuntungan/laba',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF8B5CF6),
                                          fontStyle: FontStyle.italic),
                                    ),
                                  ),
                                ]),
                              ),
                            ),
                          const SizedBox(height: 16),
                          if (snapTx.hasData &&
                              snapTx.data!.docs.isNotEmpty)
                            _buildChart(snapTx.data!.docs),
                        ],
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _buildTypeButton(String type) {
    final isSelected = _reportType == type;
    return InkWell(
      onTap: () => setState(() {
        _reportType = type;
        _selectedDate = DateTime.now();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2196F3) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          type,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _summaryCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChart(List<QueryDocumentSnapshot> docs) {
    final Map<String, double> categoryData = {};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final category = data['category'] ?? 'Lainnya';
      final amount = (data['totalAmount'] ?? 0).toDouble();
      categoryData[category] = (categoryData[category] ?? 0) + amount;
    }

    final colors = [
      const Color(0xFF2196F3),
      const Color(0xFF4CAF50),
      const Color(0xFFFF9800),
      const Color(0xFFF44336),
      const Color(0xFF9C27B0),
      const Color(0xFF00BCD4),
      const Color(0xFFFF5722),
    ];
    final total = categoryData.values.fold(0.0, (s, v) => s + v);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Penjualan per Kategori',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: categoryData.entries.map((entry) {
                  final idx =
                      categoryData.keys.toList().indexOf(entry.key);
                  return PieChartSectionData(
                    value: entry.value,
                    title: total > 0
                        ? '${((entry.value / total) * 100).toStringAsFixed(1)}%'
                        : '',
                    color: colors[idx % colors.length],
                    radius: 80,
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
                sectionsSpace: 2,
                centerSpaceRadius: 40,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: categoryData.entries.map((entry) {
              final idx =
                  categoryData.keys.toList().indexOf(entry.key);
              return Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: colors[idx % colors.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(entry.key,
                    style: const TextStyle(fontSize: 12)),
              ]);
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Stream helpers ─────────────────────────────────────────────────────────

  Stream<QuerySnapshot> _getTransactionsStream(String userId) {
    final range = _dateRange;
    return FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('date', isGreaterThanOrEqualTo: range.start)
        .where('date', isLessThanOrEqualTo: range.end)
        .snapshots();
  }

  Stream<QuerySnapshot> _getKasKeluarStream(String userId) {
    final range = _dateRange;
    return FirebaseFirestore.instance
        .collection('kas_keluar')
        .where('userId', isEqualTo: userId)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(range.end))
        .snapshots();
  }

  // ── Date helpers ───────────────────────────────────────────────────────────

  String _getDateText() {
    if (_reportType == 'Harian') {
      return DateFormat('dd MMMM yyyy', 'id_ID').format(_selectedDate);
    } else if (_reportType == 'Mingguan') {
      final range = _dateRange;
      final startFmt = DateFormat('dd MMM', 'id_ID').format(range.start);
      final endFmt   = DateFormat('dd MMM yyyy', 'id_ID').format(range.end);
      return '$startFmt – $endFmt';
    } else {
      return DateFormat('MMMM yyyy', 'id_ID').format(_selectedDate);
    }
  }

  void _previousPeriod() {
    setState(() {
      if (_reportType == 'Harian') {
        _selectedDate = _selectedDate.subtract(const Duration(days: 1));
      } else if (_reportType == 'Mingguan') {
        _selectedDate = _selectedDate.subtract(const Duration(days: 7));
      } else {
        _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1);
      }
    });
  }

  void _nextPeriod() {
    setState(() {
      if (_reportType == 'Harian') {
        _selectedDate = _selectedDate.add(const Duration(days: 1));
      } else if (_reportType == 'Mingguan') {
        _selectedDate = _selectedDate.add(const Duration(days: 7));
      } else {
        _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1);
      }
    });
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme:
                const ColorScheme.light(primary: Color(0xFF2196F3))),
        child: child!,
      ),
    );
    if (date != null) {
      setState(() {
        _selectedDate = _reportType == 'Bulanan'
            ? DateTime(date.year, date.month)
            : date;
      });
    }
  }
}