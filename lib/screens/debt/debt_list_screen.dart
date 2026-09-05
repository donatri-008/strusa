import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'debt_detail_screen.dart';

const _blue    = Color(0xFF2196F3);
const _blueDk  = Color(0xFF1976D2);
const _red     = Color(0xFFEF4444);
const _green   = Color(0xFF22C55E);
const _ink     = Color(0xFF111827);
const _inkLt   = Color(0xFF9CA3AF);
const _surf    = Color(0xFFF3F4F6);
const _bdr     = Color(0xFFE5E7EB);

double _effectiveDebt(Map<String, dynamic> data) {
  if (data['isBayarSebagian'] == true) {
    return (data['remainingDebt'] ?? 0).toDouble();
  }
  return (data['totalAmount'] ?? 0).toDouble();
}

// ─────────────────────────────────────────────────────────────────────────────
// groupKey: prioritaskan customerName sebagai primary key.
// Dengan begini, transaksi beda nomor tapi nama sama tetap digabung jadi 1 group.
// ─────────────────────────────────────────────────────────────────────────────
String _groupKey(String name, String number) {
  if (name.isNotEmpty) return 'name__$name';
  if (number.isNotEmpty) return 'num__$number';
  return '__unknown__';
}

class DebtListScreen extends StatefulWidget {
  const DebtListScreen({super.key});

  @override
  State<DebtListScreen> createState() => _DebtListScreenState();
}

class _DebtListScreenState extends State<DebtListScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  String _query = '';

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _surf,
        body: _buildBody(user, fmt),
      ),
    );
  }

  Widget _buildBody(User? user, NumberFormat fmt) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: user?.uid)
          .where('isPaid', isEqualTo: false)
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (ctx, snap) {
        final Map<String, List<QueryDocumentSnapshot>> grouped = {};
        if (snap.hasData) {
          for (var doc in snap.data!.docs) {
            final data   = doc.data() as Map<String, dynamic>;
            final number = (data['customerNumber'] ?? '').toString().trim();
            final name   = (data['customerName']   ?? '').toString().trim();

            // ✅ Nama jadi primary key: beda nomor tapi nama sama → 1 group
            final key = _groupKey(name, number);

            if (_query.isNotEmpty) {
              if (!name.toLowerCase().contains(_query) &&
                  !number.toLowerCase().contains(_query)) {
                continue;
              }
            }
            grouped.putIfAbsent(key, () => []).add(doc);
          }
        }

        // Summary stats — gunakan groupKey yang sama
        double totalPiutang   = 0;
        int    totalCustomers = 0;
        int    sebagianCount  = 0;
        if (snap.hasData) {
          final Map<String, double> byCustomer = {};
          for (var doc in snap.data!.docs) {
            final d      = doc.data() as Map<String, dynamic>;
            final number = (d['customerNumber'] ?? '').toString().trim();
            final name   = (d['customerName']   ?? '').toString().trim();
            final key    = _groupKey(name, number);
            byCustomer[key] = (byCustomer[key] ?? 0) + _effectiveDebt(d);
            if (d['isBayarSebagian'] == true) sebagianCount++;
          }
          totalPiutang   = byCustomer.values.fold(0, (s, v) => s + v);
          totalCustomers = byCustomer.length;
        }

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _buildHeader(
                user: user,
                fmt: fmt,
                total: totalPiutang,
                customers: totalCustomers,
                sebagian: sebagianCount,
                isLoading: snap.connectionState == ConnectionState.waiting,
              ),
            ),

            if (snap.connectionState == ConnectionState.waiting)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: _blue)),
              )
            else if (!snap.hasData || snap.data!.docs.isEmpty)
              SliverFillRemaining(
                child: _emptyState(
                  'Tidak ada piutang',
                  'Semua transaksi sudah lunas 🎉',
                  _green,
                  Icons.check_circle_outline_rounded,
                ),
              )
            else if (grouped.isEmpty)
              SliverFillRemaining(
                child: _emptyState(
                  'Tidak ada hasil',
                  'Coba kata kunci lain',
                  _inkLt,
                  Icons.search_off_rounded,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final txs = grouped.values.elementAt(i);

                      double debt            = 0;
                      int    txSebagianCount = 0;
                      for (var doc in txs) {
                        final d = doc.data() as Map<String, dynamic>;
                        debt += _effectiveDebt(d);
                        if (d['isBayarSebagian'] == true) txSebagianCount++;
                      }

                      final firstData = txs.first.data() as Map<String, dynamic>;
                      final name      = (firstData['customerName']   ?? '').toString().trim();
                      // Untuk display nomor: ambil dari transaksi pertama.
                      // Jika group berisi beda nomor, tampilkan tanda khusus.
                      final allNumbers = txs
                          .map((d) => (d.data() as Map<String, dynamic>)['customerNumber']?.toString().trim() ?? '')
                          .where((n) => n.isNotEmpty)
                          .toSet();
                      final displayNumber = allNumbers.length == 1
                          ? allNumbers.first
                          : allNumbers.isEmpty
                              ? ''
                              : '${allNumbers.length} nomor';

                      return _buildCustomerCard(
                        index:          i,
                        customerName:   name,
                        displayNumber:  displayNumber,
                        // Kirim semua nomor agar DebtDetailScreen bisa query semuanya
                        allNumbers:     allNumbers.toList(),
                        totalDebt:      debt,
                        txCount:        txs.length,
                        sebagianCount:  txSebagianCount,
                        fmt:            fmt,
                        transactions:   txs,
                      );
                    },
                    childCount: grouped.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader({
    required User? user,
    required NumberFormat fmt,
    required double total,
    required int customers,
    required int sebagian,
    required bool isLoading,
  }) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_blue, _blueDk],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 19),
                    onPressed: () => Get.back(),
                  ),
                  const Expanded(
                    child: Text('Piutang Pelanggan',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2)),
                  ),
                  const SizedBox(width: 38),
                ],
              ),
            ),

            FadeTransition(
              opacity: _fade,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.account_balance_wallet_outlined,
                              color: Colors.white, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Total Piutang',
                                  style: TextStyle(color: Colors.white70, fontSize: 12)),
                              const SizedBox(height: 3),
                              isLoading
                                  ? Container(
                                      height: 22, width: 120,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    )
                                  : Text(fmt.format(total),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      )),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(height: 1, color: Colors.white.withValues(alpha: 0.15)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _statItem(Icons.group_outlined, '$customers Pelanggan'),
                        if (sebagian > 0) ...[
                          Container(
                              width: 1, height: 18,
                              color: Colors.white.withValues(alpha: 0.2),
                              margin: const EdgeInsets.symmetric(horizontal: 16)),
                          _statItem(Icons.money_off_rounded,
                              '$sebagian Bayar Sebagian',
                              color: Colors.white),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.black45, fontSize: 14),
                  onChanged: (v) => setState(() => _query = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Cari nama atau nomor...',
                    hintStyle: const TextStyle(color: Colors.black45),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: Colors.black45, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white54, size: 18),
                            onPressed: () => setState(() {
                              _searchCtrl.clear();
                              _query = '';
                            }),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard({
    required int index,
    required String customerName,
    required String displayNumber,
    required List<String> allNumbers,
    required double totalDebt,
    required int txCount,
    required int sebagianCount,
    required NumberFormat fmt,
    required List<QueryDocumentSnapshot> transactions,
  }) {
    final displayName = customerName.isNotEmpty ? customerName : displayNumber;
    final initials = displayName
        .trim()
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();

    final avatarColor = sebagianCount > 0 ? _red : _blue;

    // Subtitle nomor: jika ada lebih dari 1 nomor berbeda, tunjukkan info
    final numberSubtitle = allNumbers.length > 1
        ? '${allNumbers.length} nomor berbeda'
        : displayNumber.isNotEmpty
            ? displayNumber
            : '-';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + index * 55),
      curve: Curves.easeOut,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _bdr),
          boxShadow: const [
            BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              await Get.to(() => DebtDetailScreen(
                    customerName:   customerName,
                    allNumbers:     allNumbers, // ← semua nomor dikirim
                    transactions:   transactions,
                  ));
              setState(() {});
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: avatarColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: avatarColor.withValues(alpha: 0.3)),
                        ),
                        child: Center(
                          child: Text(initials,
                              style: TextStyle(
                                  color: avatarColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customerName.isNotEmpty ? customerName : 'Pelanggan',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _ink),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  allNumbers.length > 1
                                      ? Icons.phone_in_talk_rounded
                                      : Icons.numbers_rounded,
                                  size: 12,
                                  color: _inkLt,
                                ),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    numberSubtitle,
                                    style: TextStyle(
                                      color: allNumbers.length > 1
                                          ? _blue
                                          : _inkLt,
                                      fontSize: 12,
                                      fontWeight: allNumbers.length > 1
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: _inkLt, size: 20),
                    ],
                  ),

                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 14),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Piutang',
                                style: TextStyle(fontSize: 11, color: _inkLt)),
                            const SizedBox(height: 3),
                            Text(
                              fmt.format(totalDebt),
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: avatarColor),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _badge('$txCount Transaksi', _blue, Icons.receipt_long_outlined),
                          if (sebagianCount > 0) ...[
                            const SizedBox(height: 6),
                            _badge('$sebagianCount Sebagian', _red, Icons.money_off_rounded),
                          ],
                        ],
                      ),
                    ],
                  ),

                  if (sebagianCount > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _red.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _red.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 13, color: _red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$sebagianCount transaksi dengan pembayaran sebagian',
                              style: const TextStyle(
                                  fontSize: 11, color: _red, fontWeight: FontWeight.w500),
                            ),
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
      ),
    );
  }

  Widget _emptyState(String title, String sub, Color color, IconData icon) {
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height * 0.35,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08), shape: BoxShape.circle),
                  child: Icon(icon, size: 52, color: color),
                ),
                const SizedBox(height: 20),
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: _ink)),
                const SizedBox(height: 6),
                Text(sub,
                    style: const TextStyle(fontSize: 13, color: _inkLt),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statItem(IconData icon, String label, {Color color = Colors.white}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _badge(String label, Color color, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}