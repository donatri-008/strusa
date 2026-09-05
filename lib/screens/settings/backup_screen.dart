import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lottie/lottie.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sinkronisasi & Data'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Animation - selalu bergerak (animate default true)
          Center(
            child: Lottie.asset(
              'assets/lottie/uploading.json',
              width: 180,
              height: 180,
            ),
          ),

          const SizedBox(height: 8),

          // Judul & keterangan
          const Center(
            child: Text(
              'Data Tersimpan Otomatis',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Semua data tersinkronisasi secara real-time ke cloud. '
                'Data kamu aman dan selalu terbaru di semua perangkat.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Status Sinkronisasi
          Container(
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
                const Text(
                  'Status Cloud',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Status Sinkronisasi',
                      style: TextStyle(color: Colors.grey),
                    ),
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(FirebaseAuth.instance.currentUser?.uid)
                          .snapshots(),
                      builder: (context, snapshot) {
                        final isOnline = snapshot.connectionState ==
                            ConnectionState.active;
                        return Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: isOnline
                                    ? const Color(0xFF4CAF50)
                                    : Colors.orange,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isOnline ? 'Tersinkronisasi' : 'Menghubungkan...',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isOnline
                                    ? const Color(0xFF4CAF50)
                                    : Colors.orange,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Penyimpanan',
                      style: TextStyle(color: Colors.grey),
                    ),
                    Row(
                      children: [
                        Icon(Icons.cloud_done_rounded,
                            color: Color(0xFF2196F3), size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Cloud Terenkripsi',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Info keamanan data
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF2196F3).withValues(alpha: 0.2),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    color: Color(0xFF2196F3), size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Kamu bisa mengakses data dari perangkat manapun '
                    'selama login dengan akun yang sama.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF1565C0)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Statistik Data
          Container(
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
                const Text(
                  'Statistik Data',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Divider(height: 24),
                StreamBuilder<int>(
                  stream: _getTransactionCount(),
                  builder: (context, snapshot) {
                    return _buildStatRow(
                      'Total Transaksi',
                      snapshot.data?.toString() ?? '0',
                      Icons.receipt_long_rounded,
                    );
                  },
                ),
                const SizedBox(height: 12),
                StreamBuilder<int>(
                  stream: _getProductCount(),
                  builder: (context, snapshot) {
                    return _buildStatRow(
                      'Total Produk',
                      snapshot.data?.toString() ?? '0',
                      Icons.widgets_rounded,
                    );
                  },
                ),
                const SizedBox(height: 12),
                StreamBuilder<int>(
                  stream: _getDebtCount(),
                  builder: (context, snapshot) {
                    return _buildStatRow(
                      'Piutang Aktif',
                      snapshot.data?.toString() ?? '0',
                      Icons.account_balance_wallet_rounded,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF2196F3), size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }

  Stream<int> _getTransactionCount() {
    final user = FirebaseAuth.instance.currentUser;
    return FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: user?.uid)
        .snapshots()
        .map((s) => s.docs.length);
  }

  Stream<int> _getProductCount() {
    final user = FirebaseAuth.instance.currentUser;
    return FirebaseFirestore.instance
        .collection('products')
        .where('userId', isEqualTo: user?.uid)
        .snapshots()
        .map((s) => s.docs.length);
  }

  Stream<int> _getDebtCount() {
    final user = FirebaseAuth.instance.currentUser;
    return FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: user?.uid)
        .where('isPaid', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length);
  }
}