import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../utils/app_notification.dart';

class OutletManagementScreen extends StatefulWidget {
  const OutletManagementScreen({super.key});

  @override
  State<OutletManagementScreen> createState() => _OutletManagementScreenState();
}

class _OutletManagementScreenState extends State<OutletManagementScreen> {
  String? _activeOutletId;

  @override
  void initState() {
    super.initState();
    _loadActiveOutlet();
  }

  Future<void> _loadActiveOutlet() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (doc.exists && mounted) {
      setState(() => _activeOutletId = doc.data()?['activeOutletId']);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Outlet'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showOutletSheet(context),
        backgroundColor: const Color(0xFF2196F3),
        icon: const Icon(Icons.add_business_rounded, color: Colors.white),
        label: const Text('Tambah Outlet',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('outlets')
            .where('userId', isEqualTo: user?.uid)
            .orderBy('createdAt', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return _EmptyState(onAdd: () => _showOutletSheet(context));
          }

          final totalOutlets = docs.length;

          return Column(
            children: [
              // ── List ────────────────────────────────────────────────
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isActive = _activeOutletId == doc.id;
                    return _OutletCard(
                      outletId: doc.id,
                      data: data,
                      isActive: isActive,
                      totalOutlets: totalOutlets,
                      onActivate: () => _setActiveOutlet(doc.id, data['name'] ?? 'Outlet'),
                      onEdit: () => _showOutletSheet(context,
                          outletId: doc.id, existing: data),
                      onDelete: () => _deleteOutlet(doc.id, data['name'] ?? 'Outlet', isActive, totalOutlets),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showOutletSheet(BuildContext context,
      {String? outletId, Map<String, dynamic>? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OutletFormSheet(
        outletId: outletId,
        existing: existing,
        onSaved: (String name) {
          if (outletId == null) {
            AppNotification.outletSaved(name);
          } else {
            AppNotification.updated('Data outlet "$name" berhasil diperbarui.');
          }
        },
      ),
    );
  }

  Future<void> _setActiveOutlet(String outletId, String name) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user?.uid)
          .update({'activeOutletId': outletId});
      if (mounted) setState(() => _activeOutletId = outletId);
      AppNotification.outletSwitched(name);
    } catch (e) {
      AppNotification.unexpectedError('Gagal mengaktifkan outlet: $e');
    }
  }

  Future<void> _deleteOutlet(String outletId, String name, bool isActive, int totalOutlets) async {
    if (isActive) {
      AppNotification.warning(
        'Tidak Bisa Dihapus',
        'Nonaktifkan outlet ini terlebih dahulu sebelum menghapus.',
        customIcon: Icons.store_mall_directory_outlined,
      );
      return;
    }

    // Jika hanya tersisa 1 outlet, tampilkan dialog peringatan khusus
    if (totalOutlets <= 1) {
      await _showCannotDeleteDialog();
      return;
    }

    final confirm = await _showDeleteConfirmDialog();
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('outlets')
          .doc(outletId)
          .delete();
      AppNotification.outletDeleted(name);
    } catch (e) {
      AppNotification.saveFailed();
    }
  }

  /// Dialog: tidak bisa hapus karena hanya 1 outlet
  Future<void> _showCannotDeleteDialog() async {
    await Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFA000).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.store_rounded,
                        color: Color(0xFFFFA000), size: 32),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Outlet Tidak Bisa Dihapus',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ]),
              ),

              // ── Body ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFE082)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            color: Color(0xFFFFA000), size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Aplikasi membutuhkan minimal 1 outlet agar header struk dapat ditampilkan dengan benar.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF795548),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Tambahkan outlet baru terlebih dahulu sebelum menghapus outlet ini.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      height: 1.5,
                    ),
                  ),
                ]),
              ),

              // ── Actions ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Get.back(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2196F3),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Mengerti',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Dialog: konfirmasi hapus outlet
  Future<bool?> _showDeleteConfirmDialog() async {
    return await Get.dialog<bool>(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──────────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF44336).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: Color(0xFFF44336), size: 32),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Hapus Outlet?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ]),
              ),

              // ── Body ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFEF9A9A)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFF44336), size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tindakan ini tidak dapat dibatalkan. Semua data outlet akan dihapus secara permanen.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFFC62828),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Apakah Anda yakin ingin menghapus outlet ini?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      height: 1.5,
                    ),
                  ),
                ]),
              ),

              // ── Actions ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => Get.back(result: false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A1A2E),
                          side: const BorderSide(color: Color(0xFFDDE3F0)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Batal',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Get.back(result: true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF44336),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Hapus',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper: render logo dari Base64 atau URL
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildLogoImage(String logoUrl,
    {BoxFit fit = BoxFit.cover, double? height}) {
  if (logoUrl.startsWith('data:image')) {
    try {
      final base64Data = logoUrl.split(',').last;
      final bytes = base64Decode(base64Data);
      return Image.memory(bytes,
          fit: fit,
          height: height,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.store_rounded, color: Color(0xFF90A4AE), size: 26));
    } catch (_) {
      return const Icon(Icons.store_rounded, color: Color(0xFF90A4AE), size: 26);
    }
  } else {
    return Image.network(logoUrl,
        fit: fit,
        height: height,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.store_rounded, color: Color(0xFF90A4AE), size: 26));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card Outlet
// ─────────────────────────────────────────────────────────────────────────────

class _OutletCard extends StatelessWidget {
  final String outletId;
  final Map<String, dynamic> data;
  final bool isActive;
  final int totalOutlets;
  final VoidCallback onActivate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _OutletCard({
    required this.outletId,
    required this.data,
    required this.isActive,
    required this.totalOutlets,
    required this.onActivate,
    required this.onEdit,
    required this.onDelete,
  });

  void _showActionSheet(BuildContext context) {
    final isLastOutlet = totalOutlets <= 1;

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

            // Header outlet info
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDDE3F0)),
                ),
                clipBehavior: Clip.antiAlias,
                child: (data['logoUrl'] ?? '').toString().isNotEmpty
                    ? _buildLogoImage(data['logoUrl'], fit: BoxFit.cover)
                    : const Icon(Icons.store_rounded,
                        color: Color(0xFF90A4AE), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['name'] ?? 'Outlet',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    if (isActive)
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Outlet Aktif',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF2196F3),
                              fontWeight: FontWeight.w600),
                        ),
                      )
                    else
                      Text(
                        (data['address'] ?? '').toString().isNotEmpty
                            ? data['address']
                            : 'Tidak ada alamat',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 20),
            Container(height: 1, color: const Color(0xFFF0F0F0)),
            const SizedBox(height: 12),

            // Actions
            if (!isActive)
              _actionTile(
                context: context,
                icon: Icons.radio_button_checked_rounded,
                iconBgColor: const Color(0xFFE3F2FD),
                iconColor: const Color(0xFF2196F3),
                title: 'Aktifkan Outlet',
                subtitle: 'Gunakan outlet ini sebagai header struk',
                onTap: () {
                  Navigator.pop(context);
                  onActivate();
                },
              ),

            if (!isActive) const SizedBox(height: 10),

            _actionTile(
              context: context,
              icon: Icons.edit_outlined,
              iconBgColor: const Color(0xFFFFF8E1),
              iconColor: const Color(0xFFFFA000),
              title: 'Edit Outlet',
              subtitle: 'Ubah nama, logo, atau info outlet',
              onTap: () {
                Navigator.pop(context);
                onEdit();
              },
            ),

            const SizedBox(height: 10),

            // Hapus — tampilkan badge "Minimal 1" jika ini outlet terakhir
            _actionTile(
              context: context,
              icon: Icons.delete_outline_rounded,
              iconBgColor: const Color(0xFFFFEBEE),
              iconColor: isLastOutlet
                  ? const Color(0xFFBDBDBD)
                  : const Color(0xFFF44336),
              title: 'Hapus Outlet',
              subtitle: isActive
                  ? 'Nonaktifkan outlet terlebih dahulu'
                  : isLastOutlet
                      ? 'Minimal 1 outlet harus tersedia'
                      : 'Hapus outlet secara permanen',
              titleColor: isLastOutlet
                  ? const Color(0xFFBDBDBD)
                  : const Color(0xFFF44336),
              trailing: isLastOutlet
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFFE082)),
                      ),
                      child: const Text(
                        'Minimal 1',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFFA000),
                        ),
                      ),
                    )
                  : null,
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),

            SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required BuildContext context,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
    Color titleColor = const Color(0xFF111827),
    Widget? trailing,
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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              trailing ??
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 13, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logoUrl = data['logoUrl'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? const Color(0xFF2196F3) : Colors.transparent,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: isActive
                ? const Color(0xFF2196F3).withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: isActive ? 16 : 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          if (isActive)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xFF2196F3),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 13, color: Colors.white),
                  SizedBox(width: 5),
                  Text('OUTLET AKTIF',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              // ── Logo ──────────────────────────────────────────────
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: const Color(0xFFDDE3F0), width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: logoUrl.isNotEmpty
                    ? _buildLogoImage(logoUrl, fit: BoxFit.cover)
                    : const Icon(Icons.store_rounded,
                        color: Color(0xFF90A4AE), size: 26),
              ),

              const SizedBox(width: 12),

              // ── Info ──────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data['name'] ?? 'Outlet',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A2E))),
                    if ((data['tagline'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(data['tagline'],
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF2196F3),
                              fontStyle: FontStyle.italic)),
                    ],
                    if ((data['address'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.location_on_outlined,
                            size: 11, color: Color(0xFF90A4AE)),
                        const SizedBox(width: 3),
                        Expanded(
                            child: Text(data['address'],
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF90A4AE)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                      ]),
                    ],
                    if ((data['phone'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        const Icon(Icons.phone_outlined,
                            size: 11, color: Color(0xFF90A4AE)),
                        const SizedBox(width: 3),
                        Text(data['phone'],
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF90A4AE))),
                      ]),
                    ],
                  ],
                ),
              ),

              // ── Menu Button ────────────────────────────────────────
              GestureDetector(
                onTap: () => _showActionSheet(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                  ),
                  child: const Icon(Icons.more_horiz_rounded,
                      color: Color(0xFF90A4AE), size: 20),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Form Sheet — Tambah & Edit Outlet
// ─────────────────────────────────────────────────────────────────────────────

class _OutletFormSheet extends StatefulWidget {
  final String? outletId;
  final Map<String, dynamic>? existing;
  final void Function(String name) onSaved;

  const _OutletFormSheet({this.outletId, this.existing, required this.onSaved});

  @override
  State<_OutletFormSheet> createState() => _OutletFormSheetState();
}

class _OutletFormSheetState extends State<_OutletFormSheet> {
  final _nameCtrl = TextEditingController();
  final _taglineCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String? _logoUrl;
  File? _logoFile;
  bool _saving = false;

  bool get _isEdit => widget.outletId != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameCtrl.text = widget.existing!['name'] ?? '';
      _taglineCtrl.text = widget.existing!['tagline'] ?? '';
      _addressCtrl.text = widget.existing!['address'] ?? '';
      _phoneCtrl.text = widget.existing!['phone'] ?? '';
      _logoUrl = widget.existing!['logoUrl'];
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _taglineCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      final picker = ImagePicker();
      final picked =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (picked == null) return;
      setState(() => _logoFile = File(picked.path));
    } on PlatformException catch (e) {
      AppNotification.error(
        'Gagal Membuka Galeri',
        e.message ?? 'Terjadi kesalahan saat membuka galeri.',
        customIcon: Icons.photo_library_outlined,
      );
    } catch (e) {
      AppNotification.unexpectedError(e.toString());
    }
  }

  Future<String?> _uploadLogo() async {
    if (_logoFile == null) return _logoUrl;
    try {
      final bytes = await _logoFile!.readAsBytes();
      if (bytes.length > 500 * 1024) {
        AppNotification.warning(
          'Gambar Terlalu Besar',
          'Gunakan gambar di bawah 500KB untuk performa terbaik.',
          customIcon: Icons.image_outlined,
        );
      }
      final base64String = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      return base64String;
    } catch (e) {
      AppNotification.error(
        'Gagal Proses Logo',
        'Tidak dapat memproses gambar logo. Coba gambar lain.',
        customIcon: Icons.broken_image_outlined,
      );
      return _logoUrl;
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      AppNotification.invalidInput('Nama Outlet');
      return;
    }

    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final uploadUrl = await _uploadLogo();
      final name = _nameCtrl.text.trim();

      final payload = <String, dynamic>{
        'userId': user?.uid,
        'name': name,
        'tagline': _taglineCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'logoUrl': uploadUrl ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_isEdit) {
        await FirebaseFirestore.instance
            .collection('outlets')
            .doc(widget.outletId)
            .update(payload);
      } else {
        payload['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('outlets').add(payload);
      }

      if (mounted) Navigator.pop(context);
      widget.onSaved(name);
    } catch (e) {
      AppNotification.saveFailed();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildPreviewLogo() {
    if (_logoFile != null) {
      return Stack(children: [
        Center(
            child: Image.file(_logoFile!, fit: BoxFit.contain, height: 110)),
        _gantiLabel(),
      ]);
    }

    if (_logoUrl != null && _logoUrl!.isNotEmpty) {
      return Stack(children: [
        Center(
          child: _logoUrl!.startsWith('data:image')
              ? () {
                  try {
                    final bytes = base64Decode(_logoUrl!.split(',').last);
                    return Image.memory(bytes,
                        fit: BoxFit.contain,
                        height: 110,
                        errorBuilder: (_, __, ___) => _logoEmpty());
                  } catch (_) {
                    return _logoEmpty();
                  }
                }()
              : Image.network(_logoUrl!,
                  fit: BoxFit.contain,
                  height: 110,
                  errorBuilder: (_, __, ___) => _logoEmpty()),
        ),
        _gantiLabel(),
      ]);
    }

    return _logoEmpty();
  }

  Widget _gantiLabel() => Positioned(
        bottom: 6,
        right: 6,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text('Ganti',
              style: TextStyle(color: Colors.white, fontSize: 11)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
      ),
      child: SingleChildScrollView(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),

          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _isEdit ? Icons.edit_outlined : Icons.add_business_rounded,
                color: const Color(0xFF2196F3),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_isEdit ? 'Edit Outlet' : 'Tambah Outlet Baru',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('Data outlet tampil di header struk',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ]),
            ),
          ]),

          const SizedBox(height: 24),

          _label('Logo Outlet'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickLogo,
            child: Container(
              height: 110,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: const Color(0xFFDDE3F0), width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildPreviewLogo(),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.info_outline_rounded,
                size: 12, color: Colors.grey),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Gunakan gambar < 500KB.',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          _label('Nama Outlet *'),
          const SizedBox(height: 8),
          _field(_nameCtrl, 'Contoh: Toko Jaya Abadi', Icons.store_rounded),

          const SizedBox(height: 16),

          _label('Tagline / Slogan'),
          const SizedBox(height: 8),
          _field(_taglineCtrl, 'Contoh: Melayani dengan Sepenuh Hati',
              Icons.format_quote_rounded),

          const SizedBox(height: 16),

          _label('Alamat'),
          const SizedBox(height: 8),
          _field(_addressCtrl, 'Jl. Contoh No.1, Kota',
              Icons.location_on_outlined,
              maxLines: 2),

          const SizedBox(height: 16),

          _label('No. Telepon / WhatsApp'),
          const SizedBox(height: 8),
          _field(_phoneCtrl, '08xxxxxxxxxx', Icons.phone_outlined,
              keyboardType: TextInputType.phone),

          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text(
                      _isEdit ? 'Simpan Perubahan' : 'Tambah Outlet',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _logoEmpty() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 34, color: Colors.grey[400]),
          const SizedBox(height: 6),
          Text('Ketuk untuk pilih logo',
              style: TextStyle(fontSize: 12, color: Colors.grey[400])),
        ],
      );

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF444444)));

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) =>
      TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
          prefixIcon: Icon(icon, size: 18, color: const Color(0xFF90A4AE)),
          filled: true,
          fillColor: const Color(0xFFF5F7FA),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE3F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE3F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: Color(0xFF2196F3), width: 1.5),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.store_outlined,
                size: 52, color: Color(0xFF2196F3)),
          ),
          const SizedBox(height: 24),
          const Text('Belum Ada Outlet',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E))),
          const SizedBox(height: 8),
          Text(
            'Tambahkan outlet untuk menampilkan\nnama & logo toko di header struk',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13, color: Colors.grey[500], height: 1.5),
          ),
          const SizedBox(height: 28),
        ]),
      ),
    );
  }
}