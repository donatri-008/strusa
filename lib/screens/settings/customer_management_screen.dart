import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/customer_service.dart';
import '../../utils/app_notification.dart';

// ── Design tokens ─────────────────────────────────────────────────────────
const _blue        = Color(0xFF2563EB);
const _blueSoft    = Color(0xFFEFF6FF);
const _blueMid     = Color(0xFFBFDBFE);
const _red         = Color(0xFFDC2626);
const _redSoft     = Color(0xFFFEF2F2);
const _ink         = Color(0xFF0F172A);
const _inkMd       = Color(0xFF334155);
const _inkLt       = Color(0xFF64748B);
const _inkXLt      = Color(0xFF94A3B8);
const _bdr         = Color(0xFFE2E8F0);
const _bdrLight    = Color(0xFFF1F5F9);
const _surf        = Color(0xFFF8FAFC);
const _white       = Colors.white;

// ── Avatar palette (cycling) ───────────────────────────────────────────────
const _avatarPalette = [
  (bg: Color(0xFFEFF6FF), fg: Color(0xFF2563EB)),
  (bg: Color(0xFFF0FDF4), fg: Color(0xFF16A34A)),
  (bg: Color(0xFFFFF7ED), fg: Color(0xFFEA580C)),
  (bg: Color(0xFFFDF4FF), fg: Color(0xFF9333EA)),
  (bg: Color(0xFFFFF1F2), fg: Color(0xFFE11D48)),
  (bg: Color(0xFFF0FDFA), fg: Color(0xFF0D9488)),
];

({Color bg, Color fg}) _avatarColor(String name) {
  final idx = name.isEmpty ? 0 : name.codeUnitAt(0) % _avatarPalette.length;
  return _avatarPalette[idx];
}

String _getInitials(String name) {
  final words = name.trim().split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words[0][0].toUpperCase();
  return '${words[0][0]}${words[1][0]}'.toUpperCase();
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOMER MANAGEMENT SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({super.key});

  @override
  State<CustomerManagementScreen> createState() =>
      _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends State<CustomerManagementScreen>
    with SingleTickerProviderStateMixin {
  final _customerService = CustomerService();
  final _searchCtrl      = TextEditingController();
  final _scrollCtrl      = ScrollController();

  List<CustomerModel> _allCustomers = [];
  List<CustomerModel> _filtered     = [];
  bool   _isLoading        = true;
  String _query            = '';
  bool   _showScrollTop    = false;
  bool   _filterDebt       = false;
  bool   _filterMultiNumber = false;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _searchCtrl.addListener(_onSearch);
    _scrollCtrl.addListener(() {
      final show = _scrollCtrl.offset > 200;
      if (show != _showScrollTop) setState(() => _showScrollTop = show);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────

  Future<void> _loadCustomers() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final list = await _customerService.getAll();

      final debtSnap = await FirebaseFirestore.instance
          .collection('transactions')
          .where('userId', isEqualTo: user?.uid)
          .where('isPaid', isEqualTo: false)
          .get();

      final Map<String, double> debtByName   = {};
      final Map<String, double> debtByNumber = {};

      for (final doc in debtSnap.docs) {
        final data   = doc.data();
        final name   = (data['customerName']   ?? '').toString().trim();
        final number = (data['customerNumber'] ?? '').toString().trim();
        final amount = data['isBayarSebagian'] == true
            ? (data['remainingDebt'] ?? 0).toDouble()
            : (data['totalAmount']   ?? 0).toDouble();
        if (name.isNotEmpty)   debtByName[name]     = (debtByName[name]     ?? 0) + amount;
        if (number.isNotEmpty) debtByNumber[number] = (debtByNumber[number] ?? 0) + amount;
      }

      final tagged = list.map((c) {
        double debt = debtByName[c.name] ?? 0;
        if (debt == 0) {
          for (final n in c.numbers) {
            debt += debtByNumber[n] ?? 0;
          }
        }
        return c.copyWith(hasDebt: debt > 0, totalDebt: debt.toInt());
      }).toList();

      if (mounted) {
        setState(() {
          _allCustomers = tagged;
          _applyFilter();
        });
      }
    } catch (e) {
      AppNotification.loadFailed();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    final q = _query;
    var list = List<CustomerModel>.from(_allCustomers);
    if (_filterDebt)        list = list.where((c) => c.hasDebt).toList();
    if (_filterMultiNumber) list = list.where((c) => c.numbers.length > 1).toList();
    if (q.isNotEmpty) {
      list = list
          .where((c) =>
              c.name.toLowerCase().contains(q) ||
              c.numbers.any((n) => n.contains(q)))
          .toList();
    }
    _filtered = list;
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _query = q;
      _applyFilter();
    });
  }

  // ── CRUD ──────────────────────────────────────────────────────────────

  Future<void> _deleteCustomer(CustomerModel customer) async {
    final confirmed = await _showConfirmDeleteSheet(customer);
    if (confirmed != true) return;
    try {
      await _customerService.delete(customer.id);
      await _loadCustomers();
      AppNotification.customerDeleted(customer.name);
    } catch (e) {
      AppNotification.saveFailed();
    }
  }

  Future<void> _openAddOrEdit({CustomerModel? customer}) async {
    final isEdit = customer != null;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomerFormSheet(
        customer: customer,
        customerService: _customerService,
      ),
    );
    if (result == true) {
      await _loadCustomers();
      if (isEdit) {
        AppNotification.updated('Perubahan pada "${customer.name}" berhasil disimpan.');
      } else {
        AppNotification.customerSaved('Pelanggan baru');
      }
    }
  }

  // ── Delete Confirmation Sheet ─────────────────────────────────────────

  Future<bool?> _showConfirmDeleteSheet(CustomerModel customer) {
    final initials = _getInitials(customer.name);
    final colors   = _avatarColor(customer.name);

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 0, 24, MediaQuery.of(ctx).viewPadding.bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 14),
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: _bdr, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 4),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 82, height: 82,
                  decoration: BoxDecoration(
                    color: colors.bg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: colors.fg.withValues(alpha: 0.15), width: 1.5),
                  ),
                  child: Center(
                    child: Text(initials,
                        style: TextStyle(
                            color: colors.fg,
                            fontWeight: FontWeight.w800,
                            fontSize: 26,
                            letterSpacing: -0.5)),
                  ),
                ),
                Positioned(
                  bottom: -6, right: -6,
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: _red,
                      shape: BoxShape.circle,
                      border: Border.all(color: _white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                            color: _red.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: const Icon(Icons.delete_rounded, color: _white, size: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text('Hapus Pelanggan?',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    letterSpacing: -0.5)),
            const SizedBox(height: 8),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(fontSize: 14, color: _inkLt, height: 1.6),
                children: [
                  const TextSpan(text: 'Data '),
                  TextSpan(
                      text: customer.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
                  const TextSpan(
                      text: ' akan dihapus permanen\ndan tidak dapat dipulihkan.'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _redSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _red.withValues(alpha: 0.18)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                      color: _red.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.warning_amber_rounded, size: 15, color: _red),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    customer.numbers.isNotEmpty
                        ? '${customer.numbers.length} nomor tersimpan akan ikut terhapus'
                        : 'Riwayat transaksi terkait tidak akan ikut terhapus',
                    style: const TextStyle(
                        fontSize: 13, color: _red, fontWeight: FontWeight.w500, height: 1.4),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _inkMd,
                      side: const BorderSide(color: _bdr, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Batal',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.delete_rounded, size: 17),
                    label: const Text('Ya, Hapus',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      foregroundColor: _white,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
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

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surf,
      appBar: AppBar(
        title: const Text('Data Pelanggan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loadCustomers,
          ),
        ],
      ),
      floatingActionButton: _buildFab(),
      body: Column(
        children: [
          _buildSearchHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_showScrollTop) ...[
          FloatingActionButton.small(
            heroTag: 'scroll_top',
            onPressed: () => _scrollCtrl.animateTo(0,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic),
            backgroundColor: _white,
            foregroundColor: _blue,
            elevation: 2,
            child: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
          const SizedBox(height: 10),
        ],
        FloatingActionButton.extended(
          heroTag: 'add_customer',
          onPressed: () => _openAddOrEdit(),
          backgroundColor: _blue,
          foregroundColor: _white,
          elevation: 3,
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
          label: const Text('Tambah',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ],
    );
  }

  // ── Search Header ─────────────────────────────────────────────────────

  Widget _buildSearchHeader() {
    final debtCount        = _allCustomers.where((c) => c.hasDebt).length;
    final multiNumberCount = _allCustomers.where((c) => c.numbers.length > 1).length;
    final hasActive        = _query.isNotEmpty || _filterDebt || _filterMultiNumber;

    return Container(
      color: _white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 14, color: _ink),
              decoration: InputDecoration(
                hintText: 'Cari nama atau nomor pelanggan...',
                hintStyle: const TextStyle(color: _inkXLt, fontSize: 14),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 14, right: 10),
                  child: Icon(Icons.search_rounded, color: _inkLt, size: 20),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                suffixIcon: _query.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() { _query = ''; _applyFilter(); });
                        },
                        child: Container(
                          margin: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                              color: _bdrLight, shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, size: 16, color: _inkLt),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: _surf,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _bdr)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _bdr)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _blue, width: 1.5)),
              ),
            ),
          ),

          // Pills row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                // Total pelanggan
                _statPill(
                  icon: Icons.groups_rounded,
                  label: '${_allCustomers.length} Pelanggan',
                  bg: _blueSoft,
                  fg: _blue,
                ),
                const SizedBox(width: 8),

                // Debt filter chip
                _buildToggleChip(
                  icon: _filterDebt
                      ? Icons.filter_alt_rounded
                      : Icons.account_balance_wallet_outlined,
                  label: debtCount > 0 ? '$debtCount Berhutang' : 'Berhutang',
                  active: _filterDebt,
                  activeColor: _red,
                  activeBg: _redSoft,
                  inactiveBg: debtCount > 0 ? _redSoft : _bdrLight,
                  inactiveBorder: debtCount > 0
                      ? _red.withValues(alpha: 0.3)
                      : _bdr,
                  inactiveFg: debtCount > 0 ? _red : _inkLt,
                  onTap: () => setState(() {
                    _filterDebt = !_filterDebt;
                    _applyFilter();
                  }),
                ),
                const SizedBox(width: 8),

                // Multi-number filter chip
                _buildToggleChip(
                  icon: _filterMultiNumber
                      ? Icons.filter_alt_rounded
                      : Icons.sim_card_outlined,
                  label: multiNumberCount > 0
                      ? '$multiNumberCount Multi-Nomor'
                      : 'Multi-Nomor',
                  active: _filterMultiNumber,
                  activeColor: _blue,
                  activeBg: _blueSoft,
                  inactiveBg: multiNumberCount > 0 ? _blueSoft : _bdrLight,
                  inactiveBorder: multiNumberCount > 0
                      ? _blue.withValues(alpha: 0.3)
                      : _bdr,
                  inactiveFg: multiNumberCount > 0 ? _blue : _inkLt,
                  onTap: () => setState(() {
                    _filterMultiNumber = !_filterMultiNumber;
                    _applyFilter();
                  }),
                ),

                if (hasActive) ...[
                  const SizedBox(width: 8),
                  _statPill(
                    icon: Icons.filter_list_rounded,
                    label: '${_filtered.length} Ditampilkan',
                    bg: const Color(0xFFF5F3FF),
                    fg: const Color(0xFF7C3AED),
                  ),
                ],
              ]),
            ),
          ),

          Container(height: 1, color: _bdrLight),
        ],
      ),
    );
  }

  Widget _buildToggleChip({
    required IconData icon,
    required String label,
    required bool active,
    required Color activeColor,
    required Color activeBg,
    required Color inactiveBg,
    required Color inactiveBorder,
    required Color inactiveFg,
    required VoidCallback onTap,
  }) {
    final bg  = active ? activeColor : inactiveBg;
    final bdr = active ? activeColor : inactiveBorder;
    final fg  = active ? _white : inactiveFg;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: bdr),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: fg, fontWeight: FontWeight.w600)),
          if (active) ...[
            const SizedBox(width: 5),
            Container(
              width: 14, height: 14,
              decoration: BoxDecoration(
                  color: _white.withValues(alpha: 0.25), shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded, size: 9, color: _white),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _statPill({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: fg),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── Body ──────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_isLoading) return _buildSkeleton();
    if (_allCustomers.isEmpty) return _buildEmptyState();
    if (_filtered.isEmpty) return _buildNotFoundState();
    return _buildList();
  }

  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _SkeletonCard(delay: i * 80),
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      itemCount: _filtered.length,
      itemBuilder: (_, i) {
        final customer = _filtered[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _CustomerCard(
            customer: customer,
            index: i,
            onEdit:   () => _openAddOrEdit(customer: customer),
            onDelete: () => _deleteCustomer(customer),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 140, height: 140,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 140, height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _blueSoft,
                      border: Border.all(
                          color: _blueMid.withValues(alpha: 0.5), width: 1.5),
                    ),
                  ),
                  Container(
                    width: 100, height: 100,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Color(0xFFDCEAFE)),
                  ),
                  const Icon(Icons.people_alt_rounded, size: 52, color: _blue),
                  Positioned(top: 14, right: 20,
                    child: Container(width: 8, height: 8,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _blue.withValues(alpha: 0.25)))),
                  Positioned(bottom: 18, left: 16,
                    child: Container(width: 6, height: 6,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _blue.withValues(alpha: 0.2)))),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text('Belum Ada Pelanggan',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    letterSpacing: -0.4)),
            const SizedBox(height: 10),
            const Text(
              'Tambahkan pelanggan pertama Anda\ndengan menekan tombol di bawah.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _inkLt, height: 1.65),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _openAddOrEdit(),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Tambah Pelanggan Pertama',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: _white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotFoundState() {
    final isDebtOnly        = _filterDebt && !_filterMultiNumber && _query.isEmpty;
    final isMultiNumberOnly = _filterMultiNumber && !_filterDebt && _query.isEmpty;

    final IconData stateIcon;
    final Color stateColor;
    final String stateTitle;
    final String stateSubtitle;

    if (isDebtOnly) {
      stateIcon     = Icons.account_balance_wallet_outlined;
      stateColor    = _red;
      stateTitle    = 'Tidak ada pelanggan berhutang';
      stateSubtitle = 'Semua pelanggan sudah lunas 🎉';
    } else if (isMultiNumberOnly) {
      stateIcon     = Icons.sim_card_outlined;
      stateColor    = _blue;
      stateTitle    = 'Tidak ada pelanggan multi-nomor';
      stateSubtitle = 'Semua pelanggan hanya memiliki satu nomor';
    } else {
      stateIcon     = Icons.search_off_rounded;
      stateColor    = _inkXLt;
      stateTitle    = _query.isNotEmpty ? '"$_query"' : 'Tidak ada hasil';
      stateSubtitle = 'Tidak ditemukan dengan filter ini';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: stateColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(stateIcon, size: 36, color: stateColor),
            ),
            const SizedBox(height: 20),
            Text(
              stateTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  letterSpacing: -0.3),
            ),
            const SizedBox(height: 6),
            Text(
              stateSubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: _inkLt),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                _searchCtrl.clear();
                setState(() {
                  _query            = '';
                  _filterDebt       = false;
                  _filterMultiNumber = false;
                  _applyFilter();
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                    color: _blueSoft, borderRadius: BorderRadius.circular(20)),
                child: const Text(
                  'Tampilkan semua',
                  style: TextStyle(
                      fontSize: 13, color: _blue, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SKELETON CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _SkeletonCard extends StatefulWidget {
  final int delay;
  const _SkeletonCard({required this.delay});

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final op = 0.35 + 0.45 * _anim.value;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _bdr),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(children: [
            Opacity(
              opacity: op,
              child: Container(
                width: 54, height: 54,
                decoration: BoxDecoration(
                    color: _bdrLight,
                    borderRadius: BorderRadius.circular(15)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Opacity(
                  opacity: op,
                  child: Container(height: 13, width: 140,
                      decoration: BoxDecoration(
                          color: _bdrLight, borderRadius: BorderRadius.circular(7))),
                ),
                const SizedBox(height: 8),
                Opacity(
                  opacity: op * 0.65,
                  child: Container(height: 11, width: 90,
                      decoration: BoxDecoration(
                          color: _bdrLight, borderRadius: BorderRadius.circular(6))),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOMER CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _CustomerCard extends StatelessWidget {
  final CustomerModel customer;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CustomerCard({
    required this.customer,
    required this.index,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasDebt  = customer.hasDebt;
    final colors   = _avatarColor(customer.name);
    final initials = _getInitials(customer.name);
    final hasNums  = customer.numbers.isNotEmpty;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + index * 45),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child),
      ),
      child: Material(
        color: _white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(18),
          splashColor: _blue.withValues(alpha: 0.04),
          highlightColor: _blue.withValues(alpha: 0.02),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: hasDebt ? _red.withValues(alpha: 0.28) : _bdr,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: hasDebt
                      ? _red.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Main content
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar
                      Container(
                        width: 54, height: 54,
                        decoration: BoxDecoration(
                          color: colors.bg,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                              color: colors.fg.withValues(alpha: 0.15), width: 1),
                        ),
                        child: Center(
                          child: Text(initials,
                              style: TextStyle(
                                  color: colors.fg,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  letterSpacing: -0.3)),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    customer.name,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: _ink,
                                        letterSpacing: -0.2),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                // Debt badge
                                if (hasDebt) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _redSoft,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: _red.withValues(alpha: 0.2)),
                                    ),
                                    child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                              Icons.account_balance_wallet_outlined,
                                              size: 10,
                                              color: _red),
                                          SizedBox(width: 4),
                                          Text('Hutang',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: _red,
                                                  fontWeight: FontWeight.w700)),
                                        ]),
                                  ),
                                ],
                                // Multi-number badge
                                if (customer.numbers.length > 1) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _blueSoft,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: _blue.withValues(alpha: 0.2)),
                                    ),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.sim_card_outlined,
                                              size: 10, color: _blue),
                                          const SizedBox(width: 4),
                                          Text('${customer.numbers.length} Nomor',
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: _blue,
                                                  fontWeight: FontWeight.w700)),
                                        ]),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 7),

                            // Numbers
                            if (!hasNums)
                              const Row(children: [
                                Icon(Icons.phone_disabled_outlined,
                                    size: 12, color: _inkXLt),
                                SizedBox(width: 5),
                                Text('Tanpa nomor',
                                    style: TextStyle(fontSize: 12, color: _inkXLt)),
                              ])
                            else if (customer.numbers.length == 1)
                              Row(children: [
                                const Icon(Icons.smartphone_rounded,
                                    size: 12, color: _inkLt),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(customer.numbers.first,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: _inkMd,
                                          fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ])
                            else ...[
                              Row(children: [
                                const Icon(Icons.smartphone_rounded,
                                    size: 12, color: _inkLt),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(customer.numbers.first,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: _inkMd,
                                          fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ]),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6, runSpacing: 4,
                                children: customer.numbers
                                    .skip(1)
                                    .map((n) => Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: _blueSoft,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                                color: _blue.withValues(alpha: 0.15)),
                                          ),
                                          child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.tag_rounded,
                                                    size: 10, color: _blue),
                                                const SizedBox(width: 3),
                                                Text(n,
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color: _blue,
                                                        fontWeight: FontWeight.w600)),
                                              ]),
                                        ))
                                    .toList(),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Chevron
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.chevron_right_rounded,
                            color: _inkXLt, size: 20),
                      ),
                    ],
                  ),
                ),

                // Divider
                Container(height: 1, color: _bdrLight),

                // Action bar
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(17)),
                  child: Container(
                    color: _surf,
                    child: IntrinsicHeight(
                      child: Row(children: [
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.edit_rounded,
                            label: 'Edit',
                            color: _blue,
                            onTap: onEdit,
                            isLeft: true,
                          ),
                        ),
                        Container(width: 1, color: _bdrLight),
                        Expanded(
                          child: _ActionButton(
                            icon: Icons.delete_outline_rounded,
                            label: 'Hapus',
                            color: _red,
                            onTap: onDelete,
                            isLeft: false,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool isLeft;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.isLeft,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.only(
        bottomLeft: isLeft ? const Radius.circular(17) : Radius.zero,
        bottomRight: !isLeft ? const Radius.circular(17) : Radius.zero,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: color, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOMER FORM SHEET  (Add / Edit)
// ═══════════════════════════════════════════════════════════════════════════════

class _CustomerFormSheet extends StatefulWidget {
  final CustomerModel? customer;
  final CustomerService customerService;
  const _CustomerFormSheet({required this.customer, required this.customerService});

  @override
  State<_CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends State<_CustomerFormSheet> {
  final _formKey  = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final List<TextEditingController> _numberCtrls = [];

  bool _isSaving = false;
  bool get _isEdit => widget.customer != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _nameCtrl.text = widget.customer!.name;
      for (final n in widget.customer!.numbers) {
        _numberCtrls.add(TextEditingController(text: n));
      }
    }
    if (_numberCtrls.isEmpty) _numberCtrls.add(TextEditingController());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final c in _numberCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addNumberField() => setState(() => _numberCtrls.add(TextEditingController()));

  void _removeNumberField(int i) {
    if (_numberCtrls.length <= 1) return;
    setState(() { _numberCtrls[i].dispose(); _numberCtrls.removeAt(i); });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final name    = _nameCtrl.text.trim();
      final numbers = _numberCtrls
          .map((c) => c.text.trim())
          .where((n) => n.isNotEmpty)
          .toList();
      if (_isEdit) {
        await widget.customerService.updateCustomer(
            id: widget.customer!.id, name: name, numbers: numbers);
      } else {
        if (numbers.isNotEmpty) {
          for (final n in numbers) {
            await widget.customerService.upsert(number: n, name: name);
          }
        } else {
          await widget.customerService.upsertNameOnly(name: name);
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      AppNotification.saveFailed();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 14),
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: _bdr, borderRadius: BorderRadius.circular(2)),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color: _blue.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isEdit ? Icons.edit_rounded : Icons.person_add_alt_1_rounded,
                    color: _white, size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    _isEdit ? 'Edit Pelanggan' : 'Tambah Pelanggan',
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        letterSpacing: -0.3),
                  ),
                  Text(
                    _isEdit
                        ? 'Perbarui informasi pelanggan'
                        : 'Isi informasi pelanggan baru',
                    style: const TextStyle(fontSize: 12, color: _inkLt),
                  ),
                ]),
              ]),
            ),

            Container(height: 1, color: _bdrLight),

            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    20, 20, 20, MediaQuery.of(context).viewPadding.bottom + 12),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar preview
                      Center(child: _buildAvatarPreview()),
                      const SizedBox(height: 26),

                      _fieldLabel('Nama Pelanggan', required: true),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameCtrl,
                        autofocus: !_isEdit,
                        textCapitalization: TextCapitalization.words,
                        style: const TextStyle(
                            fontSize: 14, color: _ink, fontWeight: FontWeight.w500),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nama pelanggan harus diisi'
                            : null,
                        decoration: _inputDeco(
                          hint: 'Contoh: Budi Santoso',
                          icon: Icons.person_outline_rounded,
                        ),
                      ),
                      const SizedBox(height: 22),

                      Row(children: [
                        _fieldLabel('Nomor / ID Pelanggan'),
                        const Spacer(),
                        GestureDetector(
                          onTap: _addNumberField,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                                color: _blueSoft,
                                borderRadius: BorderRadius.circular(8)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.add_rounded, size: 14, color: _blue),
                              SizedBox(width: 4),
                              Text('Tambah',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: _blue,
                                      fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      const Text('Nomor HP, ID meter listrik, atau lainnya',
                          style: TextStyle(fontSize: 11, color: _inkXLt)),
                      const SizedBox(height: 10),

                      ...List.generate(_numberCtrls.length, (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          Expanded(
                            child: TextFormField(
                              controller: _numberCtrls[i],
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                  fontSize: 14,
                                  color: _ink,
                                  fontWeight: FontWeight.w500),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: _inputDeco(
                                hint: i == 0
                                    ? 'Contoh: 081234567890'
                                    : 'Nomor alternatif ${i + 1}',
                                icon: Icons.tag_rounded,
                              ),
                            ),
                          ),
                          if (_numberCtrls.length > 1) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _removeNumberField(i),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                    color: _redSoft,
                                    borderRadius: BorderRadius.circular(10)),
                                child: const Icon(Icons.remove_rounded,
                                    color: _red, size: 18),
                              ),
                            ),
                          ],
                        ]),
                      )),

                      const SizedBox(height: 26),

                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: _white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                      color: _white, strokeWidth: 2.5))
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _isEdit
                                          ? Icons.save_rounded
                                          : Icons.person_add_alt_1_rounded,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      _isEdit
                                          ? 'Simpan Perubahan'
                                          : 'Tambah Pelanggan',
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarPreview() {
    return AnimatedBuilder(
      animation: _nameCtrl,
      builder: (_, __) {
        final name     = _nameCtrl.text.trim();
        final initials = name.isEmpty ? '+' : _getInitials(name);
        final colors   = name.isEmpty ? (bg: _blueSoft, fg: _blue) : _avatarColor(name);

        return Column(children: [
          Container(
            width: 84, height: 84,
            decoration: BoxDecoration(
              color: colors.bg,
              shape: BoxShape.circle,
              border: Border.all(color: colors.fg.withValues(alpha: 0.2), width: 2),
              boxShadow: [
                BoxShadow(
                  color: colors.fg.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Center(
              child: Text(initials,
                  style: TextStyle(
                      color: colors.fg,
                      fontSize: name.isEmpty ? 28 : 25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5)),
            ),
          ),
          if (name.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(name,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                    letterSpacing: -0.2)),
          ],
        ]);
      },
    );
  }

  Widget _fieldLabel(String text, {bool required = false}) {
    return Row(children: [
      Text(text,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: _inkMd)),
      if (required) ...[
        const SizedBox(width: 3),
        const Text('*', style: TextStyle(color: _red, fontSize: 14)),
      ],
    ]);
  }

  InputDecoration _inputDeco({required String hint, required IconData icon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _inkXLt, fontSize: 14),
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 14, right: 10),
        child: Icon(icon, color: _blue, size: 18),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      filled: true,
      fillColor: _surf,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _bdr)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _bdr)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _blue, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _red, width: 1.5)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _red, width: 2)),
    );
  }
}