import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Design tokens ─────────────────────────────────────────────────────────
const _blue  = Color(0xFF2196F3);
const _green = Color(0xFF1B7F4A);
const _red   = Color(0xFFE53935);
const _ink   = Color(0xFF111827);
const _inkLt = Color(0xFF6B7280);
const _surf  = Color(0xFFF8FAFC);
const _bdr   = Color(0xFFE2E8F0);

// ── Enum aksi avatar ──────────────────────────────────────────────────────
enum _AvatarAction { camera, gallery, remove }

// ── Key SharedPreferences per user ────────────────────────────────────────
String _avatarKey(String uid) => 'avatar_path_$uid';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey         = GlobalKey<FormState>();
  final _nameController  = TextEditingController();
  final _emailController = TextEditingController();
  final _picker          = ImagePicker();

  bool  _isLoading      = false;
  File? _avatarFile;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadSavedAvatar();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // ── Load data Firebase Auth ───────────────────────────────────────────
  void _loadUserData() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _nameController.text  = user.displayName ?? '';
      _emailController.text = user.email ?? '';
    }
  }

  // ── Load foto dari SharedPreferences ─────────────────────────────────
  Future<void> _loadSavedAvatar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final path  = prefs.getString(_avatarKey(user.uid));
    if (path != null && File(path).existsSync()) {
      if (mounted) {
        setState(() {
          _avatarFile      = File(path);
        });
      }
    }
  }

  // ── Simpan path ke SharedPreferences ─────────────────────────────────
  Future<void> _saveAvatarPath(String path) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_avatarKey(user.uid), path);
  }

  // ── Hapus foto ────────────────────────────────────────────────────────
  Future<void> _removeAvatar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_avatarKey(user.uid));
    if (mounted) {
      setState(() {
        _avatarFile      = null;
      });
    }
  }

  // ── Pick gambar ───────────────────────────────────────────────────────
  Future<void> _pickAvatar() async {
    final action = await showModalBottomSheet<_AvatarAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AvatarSourceSheet(hasPhoto: _avatarFile != null),
    );

    if (action == null) return;

    if (action == _AvatarAction.remove) {
      await _removeAvatar();
      return;
    }

    final picked = await _picker.pickImage(
      source      : action == _AvatarAction.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 85,
      maxWidth    : 512,
      maxHeight   : 512,
    );

    if (picked == null || !mounted) return;
    await _saveAvatarPath(picked.path);
    setState(() => _avatarFile = File(picked.path));
  }

  // ── Update profil ─────────────────────────────────────────────────────
  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.updateDisplayName(_nameController.text.trim());
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user?.uid)
          .update({
        'name'     : _nameController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        _showSnack('Profil Diperbarui', 'Perubahan berhasil disimpan',
            bg: _green);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Gagal', 'Gagal mengupdate profil: $e', bg: _red);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Profil'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          children: [

            // ── Avatar ──────────────────────────────────────────────
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    Container(
                      width : 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color : _blue.withValues(alpha: 0.1),
                        shape : BoxShape.circle,
                        border: Border.all(
                            color: _blue.withValues(alpha: 0.3), width: 2),
                      ),
                      child: ClipOval(
                        child: _avatarFile != null
                            ? Image.file(
                                _avatarFile!,
                                fit   : BoxFit.cover,
                                width : 96,
                                height: 96,
                              )
                            : const Icon(Icons.person, size: 48, color: _blue),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right : 0,
                      child: Container(
                        padding   : const EdgeInsets.all(7),
                        decoration: const BoxDecoration(
                            color: _blue, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),
            Center(
              child: Text(
                _avatarFile != null
                    ? 'Ketuk untuk ganti foto'
                    : 'Ketuk untuk tambah foto',
                style: const TextStyle(fontSize: 12, color: _inkLt),
              ),
            ),

            const SizedBox(height: 32),

            // ── Form Card ────────────────────────────────────────────
            Container(
              padding   : const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color       : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border      : Border.all(color: _bdr),
              ),
              child: Column(children: [
                Row(children: [
                  Container(
                    padding   : const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                        color       : _blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(9)),
                    child: const Icon(Icons.person_outline,
                        color: _blue, size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Text('Informasi Akun',
                      style: TextStyle(
                          fontSize  : 13,
                          fontWeight: FontWeight.w800,
                          color     : _ink)),
                ]),
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child  : Divider(height: 1)),

                // Nama
                TextFormField(
                  controller        : _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText : 'Nama Lengkap',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    filled    : true,
                    fillColor : _surf,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide  : const BorderSide(color: _bdr)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide  : const BorderSide(color: _bdr)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide  : const BorderSide(
                            color: _blue, width: 1.5)),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Nama harus diisi' : null,
                ),

                const SizedBox(height: 14),

                // Email (read-only)
                TextFormField(
                  controller: _emailController,
                  enabled   : false,
                  decoration: InputDecoration(
                    labelText : 'Email',
                    prefixIcon: const Icon(Icons.email_outlined),
                    helperText: 'Email tidak dapat diubah',
                    filled    : true,
                    fillColor : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide  : const BorderSide(color: _bdr)),
                    disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide  : const BorderSide(color: _bdr)),
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 24),

            // ── Tombol Simpan ────────────────────────────────────────
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _updateProfile,
                icon : _isLoading
                    ? const SizedBox(
                        width : 18,
                        height: 18,
                        child : CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(
                    _isLoading ? 'Menyimpan...' : 'Simpan Perubahan',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  shape    : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── Tombol Ubah Password ─────────────────────────────────
            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () => _showChangePasswordSheet(context),
                icon : const Icon(Icons.lock_outline_rounded, size: 18),
                label: const Text('Ubah Password',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  side : const BorderSide(color: _bdr),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // CHANGE PASSWORD SHEET
  // ══════════════════════════════════════════════════════════════════════
  void _showChangePasswordSheet(BuildContext context) {
    final currentCtrl   = TextEditingController();
    final newCtrl       = TextEditingController();
    final confirmCtrl   = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew     = true;
    bool obscureConfirm = true;
    bool isSaving       = false;

    showModalBottomSheet(
      context           : context,
      isScrollControlled: true,
      backgroundColor   : Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color       : Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize      : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                          color       : _bdr,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Header
                  Row(children: [
                    Container(
                      padding   : const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color       : _blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.lock_outline_rounded,
                          color: _blue, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ubah Password',
                            style: TextStyle(
                                fontSize  : 17,
                                fontWeight: FontWeight.w800,
                                color     : _ink)),
                        Text('Pastikan password baru cukup kuat',
                            style: TextStyle(fontSize: 12, color: _inkLt)),
                      ],
                    ),
                  ]),
                  const SizedBox(height: 20),

                  _passwordField(
                    controller: currentCtrl,
                    label     : 'Password Lama',
                    icon      : Icons.lock_outline,
                    obscure   : obscureCurrent,
                    onToggle  : () =>
                        setSheet(() => obscureCurrent = !obscureCurrent),
                  ),
                  const SizedBox(height: 14),
                  _passwordField(
                    controller: newCtrl,
                    label     : 'Password Baru',
                    icon      : Icons.lock_reset_rounded,
                    obscure   : obscureNew,
                    onToggle  : () =>
                        setSheet(() => obscureNew = !obscureNew),
                  ),
                  const SizedBox(height: 14),
                  _passwordField(
                    controller: confirmCtrl,
                    label     : 'Konfirmasi Password Baru',
                    icon      : Icons.lock_outline,
                    obscure   : obscureConfirm,
                    onToggle  : () =>
                        setSheet(() => obscureConfirm = !obscureConfirm),
                  ),
                  const SizedBox(height: 20),

                  // Info
                  Container(
                    padding   : const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color       : _blue.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border      : Border.all(
                          color: _blue.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            color: _blue, size: 15),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Gunakan minimal 8 karakter dengan '
                            'kombinasi huruf dan angka.',
                            style: TextStyle(fontSize: 12, color: _blue),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tombol
                  Row(children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetCtx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _inkLt,
                            side : const BorderSide(color: _bdr),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Batal',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  if (newCtrl.text != confirmCtrl.text) {
                                    _showSnack(
                                        'Password Tidak Cocok',
                                        'Konfirmasi password tidak sesuai',
                                        bg: _red);
                                    return;
                                  }
                                  if (newCtrl.text.length < 8) {
                                    _showSnack(
                                        'Password Terlalu Pendek',
                                        'Gunakan minimal 8 karakter',
                                        bg: _red);
                                    return;
                                  }
                                  setSheet(() => isSaving = true);
                                  try {
                                    final user =
                                        FirebaseAuth.instance.currentUser;
                                    final cred =
                                        EmailAuthProvider.credential(
                                      email   : user!.email!,
                                      password: currentCtrl.text,
                                    );
                                    await user
                                        .reauthenticateWithCredential(cred);
                                    await user.updatePassword(newCtrl.text);
                                    if (!sheetCtx.mounted) return;
                                    Navigator.pop(sheetCtx);
                                    _showSnack(
                                        'Password Diubah',
                                        'Password berhasil diperbarui',
                                        bg: _green);
                                  } catch (e) {
                                    _showSnack(
                                        'Gagal',
                                        'Password lama tidak tepat atau '
                                        'terjadi kesalahan',
                                        bg: _red);
                                  } finally {
                                    if (sheetCtx.mounted) {
                                      setSheet(() => isSaving = false);
                                    }
                                  }
                                },
                          icon : isSaving
                              ? const SizedBox(
                                  width : 16,
                                  height: 16,
                                  child : CircularProgressIndicator(
                                      color    : Colors.white,
                                      strokeWidth: 2))
                              : const Icon(Icons.check_rounded, size: 18),
                          label: Text(
                              isSaving
                                  ? 'Menyimpan...'
                                  : 'Ubah Password',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            shape    : RoundedRectangleBorder(
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
          ),
        ),
      ),
    );
  }

  // ── Password Field ────────────────────────────────────────────────────
  Widget _passwordField({
    required TextEditingController controller,
    required String    label,
    required IconData  icon,
    required bool      obscure,
    required VoidCallback onToggle,
  }) {
    return TextFormField(
      controller : controller,
      obscureText: obscure,
      decoration : InputDecoration(
        labelText : label,
        prefixIcon: Icon(icon),
        suffixIcon: IconButton(
          icon: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 20),
          onPressed: onToggle,
        ),
        filled      : true,
        fillColor   : _surf,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide  : const BorderSide(color: _bdr)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide  : const BorderSide(color: _bdr)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide  : const BorderSide(color: _blue, width: 1.5)),
      ),
    );
  }

  // ── Snackbar ──────────────────────────────────────────────────────────
  void _showSnack(String title, String msg, {Color bg = _green}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.transparent,
      elevation      : 0,
      padding        : const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: Container(
        padding   : const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(14)),
        child: Column(
          mainAxisSize      : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color     : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize  : 13)),
            Text(msg,
                style: const TextStyle(
                    color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
      duration: const Duration(seconds: 3),
    ));
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Bottom Sheet: Pilih Sumber Foto
// ══════════════════════════════════════════════════════════════════════════════
class _AvatarSourceSheet extends StatelessWidget {
  final bool hasPhoto;
  const _AvatarSourceSheet({required this.hasPhoto});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color       : Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color       : _bdr,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Foto Profil',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),

          _tile(
            context,
            icon : Icons.camera_alt_rounded,
            color: _blue,
            label: 'Ambil Foto dari Kamera',
            onTap: () => Navigator.pop(context, _AvatarAction.camera),
          ),
          const SizedBox(height: 10),

          _tile(
            context,
            icon : Icons.photo_library_rounded,
            color: _blue,
            label: 'Pilih dari Galeri',
            onTap: () => Navigator.pop(context, _AvatarAction.gallery),
          ),

          if (hasPhoto) ...[
            const SizedBox(height: 10),
            _tile(
              context,
              icon : Icons.delete_outline_rounded,
              color: _red,
              label: 'Hapus Foto',
              onTap: () => Navigator.pop(context, _AvatarAction.remove),
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData     icon,
    required Color        color,
    required String       label,
    required VoidCallback onTap,
  }) {
    return Material(
      color       : _surf,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap       : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize  : 14,
                    color     : color == _red ? _red : _ink)),
          ]),
        ),
      ),
    );
  }
}