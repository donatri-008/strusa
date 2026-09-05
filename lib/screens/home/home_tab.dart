import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import '../product/product_list_screen.dart';
import '../debt/debt_list_screen.dart';
import '../transaction/transaction_detail_screen.dart';
import 'main_screen.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  static DateTime get _todayStart =>
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  static DateTime get _todayEnd => DateTime(DateTime.now().year,
      DateTime.now().month, DateTime.now().day, 23, 59, 59);

  void _goToTransaksi() {
    final ctrl = Get.put(MainScreenController(), permanent: true);
    ctrl.currentIndex.value = 1;
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    // ── FIX: Wrap dengan authStateChanges agar uid tidak null saat login baru
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        final user = authSnapshot.data;

        // Tampilkan loading sampai auth state tersedia
        if (authSnapshot.connectionState == ConnectionState.waiting ||
            user == null) {
          return const Scaffold(
            backgroundColor: Color(0xFFF5F7FA),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                await Future.delayed(const Duration(seconds: 1));
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header Section ────────────────────────────────────
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(30),
                          bottomRight: Radius.circular(30),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Selamat Datang',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 14),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      user.displayName ?? 'User',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // ── Summary Cards ───────────────────────────────
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('transactions')
                                  .where('userId', isEqualTo: user.uid)
                                  .where('date',
                                      isGreaterThanOrEqualTo: _todayStart)
                                  .where('date',
                                      isLessThanOrEqualTo: _todayEnd)
                                  .snapshots(),
                              builder: (context, snapTx) {
                                return StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('kas_keluar')
                                      .where('userId', isEqualTo: user.uid)
                                      .where('date',
                                          isGreaterThanOrEqualTo:
                                              Timestamp.fromDate(_todayStart))
                                      .where('date',
                                          isLessThanOrEqualTo:
                                              Timestamp.fromDate(_todayEnd))
                                      .snapshots(),
                                  builder: (context, snapKk) {
                                    if (snapTx.connectionState ==
                                            ConnectionState.waiting ||
                                        snapKk.connectionState ==
                                            ConnectionState.waiting) {
                                      return _buildShimmerCard();
                                    }

                                    double totalSales = 0;
                                    double profitKotor = 0;
                                    int totalTransactions =
                                        snapTx.data?.docs.length ?? 0;

                                    if (snapTx.hasData) {
                                      for (final doc in snapTx.data!.docs) {
                                        final data =
                                            doc.data() as Map<String, dynamic>;
                                        final totalAmount =
                                            (data['totalAmount'] ?? 0)
                                                .toDouble();
                                        final adminFee =
                                            (data['adminFee'] ?? 0).toDouble();
                                        final hargaBeli =
                                            (data['hargaBeli'] ?? 0).toDouble();
                                        final hargaJual =
                                            (data['nominal'] ?? 0).toDouble();

                                        totalSales += totalAmount;

                                        final selisih = hargaBeli > 0
                                            ? (hargaJual - hargaBeli)
                                            : 0.0;
                                        profitKotor += selisih + adminFee;
                                      }
                                    }

                                    double potonganLaba = 0;
                                    if (snapKk.hasData) {
                                      for (final doc in snapKk.data!.docs) {
                                        final data =
                                            doc.data() as Map<String, dynamic>;
                                        final kurangiLaba =
                                            data['kurangiLaba'] ?? true;
                                        if (kurangiLaba == true) {
                                          potonganLaba +=
                                              (data['amount'] ?? 0).toDouble();
                                        }
                                      }
                                    }

                                    final profitBersih =
                                        profitKotor - potonganLaba;

                                    return GridView.count(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      crossAxisCount:
                                          MediaQuery.of(context).size.width >
                                                  400
                                              ? 3
                                              : 2,
                                      crossAxisSpacing: 16,
                                      mainAxisSpacing: 16,
                                      childAspectRatio: 1.2,
                                      children: [
                                        _buildSummaryCard(
                                          'Transaksi',
                                          totalTransactions.toString(),
                                          Icons.receipt_long_rounded,
                                        ),
                                        _buildSummaryCard(
                                          'Penjualan',
                                          currencyFormat.format(totalSales),
                                          Icons.attach_money_rounded,
                                        ),
                                        _buildSummaryCard(
                                          'Profit',
                                          currencyFormat.format(profitBersih),
                                          profitBersih >= 0
                                              ? Icons.trending_up_rounded
                                              : Icons.trending_down_rounded,
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Quick Actions ──────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Menu Utama',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 16),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 3,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.7,
                            children: [
                              _buildMenuCard(
                                'Produk\nPPOB',
                                Icons.widgets_rounded,
                                const Color(0xFF4CAF50),
                                () => Get.to(() => const ProductListScreen()),
                              ),
                              _buildMenuCard(
                                'Riwayat\nTransaksi',
                                Icons.history_rounded,
                                const Color(0xFFFF9800),
                                _goToTransaksi,
                              ),
                              _buildMenuCard(
                                'Piutang\nPelanggan',
                                Icons.account_balance_wallet_rounded,
                                const Color(0xFFF44336),
                                () => Get.to(() => const DebtListScreen()),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Recent Transactions ────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Transaksi Terbaru',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                              TextButton(
                                onPressed: _goToTransaksi,
                                child: const Text('Lihat Semua'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('transactions')
                                .where('userId', isEqualTo: user.uid)
                                .orderBy('date', descending: true)
                                .limit(5)
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return _buildShimmerList();
                              }

                              if (!snapshot.hasData ||
                                  snapshot.data!.docs.isEmpty) {
                                return _buildEmptyState();
                              }

                              return ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: snapshot.data!.docs.length,
                                itemBuilder: (context, index) {
                                  final doc = snapshot.data!.docs[index];
                                  final data =
                                      doc.data() as Map<String, dynamic>;

                                  return _buildTransactionItem(
                                    docId: doc.id,
                                    rawData: data,
                                    productName:
                                        data['productName'] ?? 'Produk',
                                    customerName:
                                        data['customerName'] ?? '-',
                                    amount: currencyFormat
                                        .format(data['totalAmount'] ?? 0),
                                    isPaid: data['isPaid'] ?? false,
                                    isBayarSebagian:
                                        data['isBayarSebagian'] ?? false,
                                    date:
                                        (data['date'] as Timestamp).toDate(),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Widget Helpers (tidak berubah) ──────────────────────────────────────────

  Widget _buildSummaryCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 12),
          Text(title,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard(
      String title, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionItem({
    required String docId,
    required Map<String, dynamic> rawData,
    required String productName,
    required String customerName,
    required String amount,
    required bool isPaid,
    required bool isBayarSebagian,
    required DateTime date,
  }) {
    final statusIcon = isBayarSebagian && !isPaid
        ? Icons.money_off_rounded
        : isPaid
            ? Icons.check_circle
            : Icons.pending;

    final statusColor = isBayarSebagian && !isPaid
        ? const Color(0xFFF44336)
        : isPaid
            ? const Color(0xFF4CAF50)
            : const Color(0xFFFF9800);

    final statusLabel = isBayarSebagian && !isPaid
        ? 'Sebagian'
        : isPaid
            ? 'Lunas'
            : 'Belum Lunas';

    return GestureDetector(
      onTap: () => Get.to(() => TransactionDetailScreen(
            transactionId: docId,
            transactionData: rawData,
          )),
      child: Container(
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
            onTap: () => Get.to(() => TransactionDetailScreen(
                  transactionId: docId,
                  transactionData: rawData,
                )),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: Color(0xFF2196F3)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(productName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(customerName,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('dd MMM yyyy, HH:mm').format(date),
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(amount,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Color(0xFF2196F3),
                          )),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 12, color: statusColor),
                            const SizedBox(width: 4),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          size: 11, color: Colors.grey),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerCard() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.3),
      highlightColor: Colors.white.withValues(alpha: 0.5),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerList() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        itemBuilder: (context, index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 20),
          Text(
            'Belum ada transaksi',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }
}