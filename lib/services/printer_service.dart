import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image/image.dart' as img;
import 'package:open_settings_plus/open_settings_plus.dart';
import '../utils/app_notification.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model data outlet
// ─────────────────────────────────────────────────────────────────────────────

class OutletInfo {
  final String name;
  final String tagline;
  final String address;
  final String phone;
  final String logoUrl;
  final Uint8List? logoBytes;

  const OutletInfo({
    this.name = '',
    this.tagline = '',
    this.address = '',
    this.phone = '',
    this.logoUrl = '',
    this.logoBytes,
  });

  bool get hasLogo => logoBytes != null && logoBytes!.isNotEmpty;
  bool get isEmpty => name.isEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// ReceiptItem
// ─────────────────────────────────────────────────────────────────────────────

class ReceiptItem {
  final String productName;
  final int quantity;
  final int hargaJual;
  final int subtotal;
  final String customerNumber;
  final int nominal;
  final int adminFee;
  final String atasNama;
  final String category;

  const ReceiptItem({
    required this.productName,
    required this.quantity,
    required this.hargaJual,
    required this.subtotal,
    this.customerNumber = '',
    this.nominal = 0,
    this.adminFee = 0,
    this.atasNama = '',
    this.category = '',
  });

  bool get hasNominalFee =>
      category == 'Tagihan' ||
      category == 'E-Wallet' ||
      category == 'Jasa Transfer';

  bool get showAtasNama =>
      atasNama.trim().isNotEmpty &&
      category != 'Pulsa' &&
      category != 'Paket Data' &&
      category != 'E-Wallet' &&
      category != 'Jasa Transfer' &&
      category != 'Lainnya';

  bool get showAdminFee =>
      adminFee > 0 &&
      category != 'Pulsa' &&
      category != 'Paket Data' &&
      category != 'Token Listrik' &&
      category != 'Lainnya';
}

// ─────────────────────────────────────────────────────────────────────────────
// ReceiptData
// ─────────────────────────────────────────────────────────────────────────────

class ReceiptData {
  final String transactionId;
  final String productName;
  final String customerNumber;
  final String customerName;
  final String atasNama;
  final int totalAmount;
  final int nominal;
  final int adminFee;
  final String paymentMethod;
  final bool isPaid;
  final bool isBayarSebagian;
  final int? partialAmount;
  final int remainingDebt;
  final DateTime transactionDate;
  final String? token;
  final String? kwh;
  final String category;
  final List<ReceiptItem> items;
  final int kembalian;
  final int? paidAmount;

  const ReceiptData({
    required this.transactionId,
    required this.productName,
    required this.customerNumber,
    this.customerName = '',
    this.atasNama = '',
    required this.totalAmount,
    this.nominal = 0,
    this.adminFee = 0,
    required this.paymentMethod,
    required this.isPaid,
    this.isBayarSebagian = false,
    this.partialAmount,
    this.remainingDebt = 0,
    required this.transactionDate,
    this.token,
    this.kwh,
    this.category = '',
    this.items = const [],
    this.kembalian = 0,
    this.paidAmount,
  });

  bool get isMultiItem => items.length > 1;
  bool get hasKembalian => kembalian > 0;
  bool get isHutangPenuh => !isPaid && !isBayarSebagian;

  int get _effectiveNominal =>
      items.isNotEmpty ? items.first.nominal : nominal;
  int get _effectiveAdminFee =>
      items.isNotEmpty ? items.first.adminFee : adminFee;
  String get _effectiveAtasNama =>
      items.isNotEmpty ? items.first.atasNama : atasNama;
  bool get _effectiveShowAtasNama =>
      items.isNotEmpty ? items.first.showAtasNama : _rootShowAtasNama;
  bool get _effectiveShowAdminFee =>
      items.isNotEmpty ? items.first.showAdminFee : _rootShowAdminFee;
  bool get _effectiveHasNominalFee =>
      items.isNotEmpty ? items.first.hasNominalFee : _rootHasNominalFee;

  bool get _rootHasNominalFee =>
      category == 'Tagihan' ||
      category == 'E-Wallet' ||
      category == 'Jasa Transfer';

  bool get _rootShowAtasNama =>
      atasNama.trim().isNotEmpty &&
      category != 'Pulsa' &&
      category != 'Paket Data' &&
      category != 'E-Wallet' &&
      category != 'Jasa Transfer' &&
      category != 'Lainnya';

  bool get _rootShowAdminFee =>
      adminFee > 0 &&
      category != 'Pulsa' &&
      category != 'Paket Data' &&
      category != 'Token Listrik' &&
      category != 'Lainnya';
}

// ─────────────────────────────────────────────────────────────────────────────
// Model baris struk
// ─────────────────────────────────────────────────────────────────────────────

enum _LineType {
  separator,
  divider,
  centerBig,
  centerBold,
  center,
  keyValue,
  totalRow,
  splitRow,
  blank,
  logo,
  itemHeader,
  itemDetail,
  itemPrice,
  kembalianRow,
}

class _Line {
  final _LineType type;
  final String label;
  final String value;
  final Color? color;
  final Uint8List? imageData;

  const _Line({
    required this.type,
    this.label = '',
    this.value = '',
    this.color,
    this.imageData,
  });

  factory _Line.separator() => const _Line(type: _LineType.separator);
  factory _Line.divider() => const _Line(type: _LineType.divider);
  factory _Line.centerBig(String v) => _Line(type: _LineType.centerBig, value: v);
  factory _Line.centerBold(String v, {Color? color}) =>
      _Line(type: _LineType.centerBold, value: v, color: color);
  factory _Line.center(String v) => _Line(type: _LineType.center, value: v);
  factory _Line.kv(String l, String v) =>
      _Line(type: _LineType.keyValue, label: l, value: v);
  factory _Line.total(String l, String v) =>
      _Line(type: _LineType.totalRow, label: l, value: v);
  factory _Line.split(String l, String v) =>
      _Line(type: _LineType.splitRow, label: l, value: v);
  factory _Line.logo(Uint8List bytes) =>
      _Line(type: _LineType.logo, imageData: bytes);
  factory _Line.itemHeader(String name, String index) =>
      _Line(type: _LineType.itemHeader, label: index, value: name);
  factory _Line.itemDetail(String l, String v) =>
      _Line(type: _LineType.itemDetail, label: l, value: v);
  factory _Line.itemPrice(String qty, String subtotal) =>
      _Line(type: _LineType.itemPrice, label: qty, value: subtotal);
  factory _Line.kembalian(String l, String v) =>
      _Line(type: _LineType.kembalianRow, label: l, value: v);
}

// ─────────────────────────────────────────────────────────────────────────────
// PrinterService
// ─────────────────────────────────────────────────────────────────────────────

class PrinterService {
  // ── Build baris struk ─────────────────────────────────────────────────────

  static List<_Line> _buildReceiptLines(ReceiptData d, {OutletInfo? outlet}) {
    final fmt =
        NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    final statusLabel = d.isPaid
        ? 'LUNAS'
        : d.isBayarSebagian
            ? 'BAYAR SEBAGIAN'
            : 'HUTANG';

    final statusColor = d.isPaid
        ? (d.hasKembalian
            ? const Color(0xFF00BCD4)
            : const Color(0xFF4CAF50))
        : d.isBayarSebagian
            ? const Color(0xFFF44336)
            : const Color(0xFFFF9800);

    final headerName =
        (outlet != null && outlet.name.isNotEmpty) ? outlet.name : 'STRUSA POS';
    final headerTagline = (outlet != null && outlet.tagline.isNotEmpty)
        ? outlet.tagline
        : 'Aplikasi Kasir & PPOB';

    return [
      if (outlet != null && outlet.hasLogo) _Line.logo(outlet.logoBytes!),
      _Line.centerBig(headerName.toUpperCase()),
      _Line.center(headerTagline),
      if (outlet != null && outlet.address.isNotEmpty)
        _Line.center(outlet.address),
      if (outlet != null && outlet.phone.isNotEmpty)
        _Line.center('Telp: ${outlet.phone}'),
      _Line.separator(),
      _Line.kv('Tgl',
          DateFormat('dd/MM/yy HH:mm', 'id_ID').format(d.transactionDate)),
      _Line.kv('No. Trx',
          '#${d.transactionId.substring(0, 12).toUpperCase()}'),
      _Line.separator(),
      if (d.customerName.isNotEmpty) ...[
        _Line.centerBig(d.customerName.toUpperCase()),
        _Line.divider(),
      ],
      if (d.isMultiItem) ...[
        _Line.centerBold('${d.items.length} PRODUK TRANSAKSI'),
        _Line.divider(),
        for (int i = 0; i < d.items.length; i++) ...[
          _Line.itemHeader(d.items[i].productName, '${i + 1}.'),
          if (d.items[i].customerNumber.isNotEmpty)
            _Line.itemDetail('No', d.items[i].customerNumber),
          if (d.items[i].showAtasNama)
            _Line.itemDetail('Atas Nama', d.items[i].atasNama.trim()),
          if (d.items[i].hasNominalFee && d.items[i].nominal > 0)
            _Line.itemDetail('Nominal', fmt.format(d.items[i].nominal)),
          if (d.items[i].showAdminFee)
            _Line.itemDetail('Biaya Admin', fmt.format(d.items[i].adminFee)),
          _Line.itemPrice(
            d.items[i].quantity > 1
                ? '${d.items[i].quantity}x ${fmt.format(d.items[i].hargaJual)}'
                : '',
            fmt.format(d.items[i].subtotal),
          ),
          if (i < d.items.length - 1) _Line.divider(),
        ],
        _Line.separator(),
      ] else ...[
        _Line.centerBold(d.productName.toUpperCase()),
        _Line.divider(),
        if (d.customerNumber.isNotEmpty)
          _Line.kv('No.Pelanggan', d.customerNumber)
        else if (d.items.isNotEmpty &&
            d.items.first.customerNumber.isNotEmpty)
          _Line.kv('No.Pelanggan', d.items.first.customerNumber),
        if (d._effectiveShowAtasNama)
          _Line.kv('Atas Nama', d._effectiveAtasNama.trim()),
        if (d.token != null && d.token!.isNotEmpty) ...[
          _Line.divider(),
          _Line.kv('TOKEN', d.token!),
          if (d.kwh != null && d.kwh!.isNotEmpty) _Line.kv('KWH', d.kwh!),
        ],
        _Line.divider(),
        if (d._effectiveHasNominalFee && d._effectiveNominal > 0)
          _Line.kv('Nominal', fmt.format(d._effectiveNominal)),
        if (d._effectiveShowAdminFee)
          _Line.kv('Biaya Admin', fmt.format(d._effectiveAdminFee)),
        if (d._effectiveHasNominalFee || d._effectiveShowAdminFee)
          _Line.divider(),
      ],
      _Line.total('TOTAL', fmt.format(d.totalAmount)),
      if (d.isBayarSebagian &&
          d.partialAmount != null &&
          d.remainingDebt > 0) ...[
        _Line.divider(),
        _Line.split('Dibayar', fmt.format(d.partialAmount)),
        _Line.split('Sisa Hutang', fmt.format(d.remainingDebt)),
      ],
      if (d.hasKembalian) ...[
        _Line.separator(),
        if (d.paidAmount != null)
          _Line.split('Uang Diterima', fmt.format(d.paidAmount)),
        _Line.kembalian('Kembalian', fmt.format(d.kembalian)),
      ],
      _Line.separator(),
      if (!d.isHutangPenuh &&
          d.paymentMethod.isNotEmpty &&
          d.paymentMethod != '-' &&
          d.paymentMethod != 'Hutang')
        _Line.kv('Metode', d.paymentMethod),
      _Line.centerBold('Status: $statusLabel', color: statusColor),
      _Line.separator(),
      _Line.centerBold('Terima Kasih!'),
      _Line.center('Simpan struk ini sebagai'),
      _Line.center('bukti pembayaran'),
    ];
  }

  // ── Load outlet aktif ──────────────────────────────────────────────────────

  Future<OutletInfo?> _loadActiveOutlet() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final activeId = userDoc.data()?['activeOutletId'] as String?;
      if (activeId == null || activeId.isEmpty) return null;

      final outletDoc = await FirebaseFirestore.instance
          .collection('outlets')
          .doc(activeId)
          .get();
      if (!outletDoc.exists) return null;

      final data = outletDoc.data();
      if (data == null) return null;

      final logoUrl = data['logoUrl'] as String? ?? '';
      Uint8List? logoBytes;

      if (logoUrl.isNotEmpty) {
        if (logoUrl.startsWith('data:image')) {
          try {
            logoBytes = base64Decode(logoUrl.split(',').last);
          } catch (e) {
            debugPrint('Gagal decode Base64 logo: $e');
          }
        } else {
          try {
            final resp = await HttpClient()
                .getUrl(Uri.parse(logoUrl))
                .then((req) => req.close())
                .timeout(const Duration(seconds: 5));
            final chunks = <List<int>>[];
            await for (final chunk in resp) {
              chunks.add(chunk);
            }
            logoBytes =
                Uint8List.fromList(chunks.expand((e) => e).toList());
          } catch (e) {
            debugPrint('Gagal download logo URL: $e');
          }
        }
      }

      return OutletInfo(
        name: data['name'] ?? '',
        tagline: data['tagline'] ?? '',
        address: data['address'] ?? '',
        phone: data['phone'] ?? '',
        logoUrl: logoUrl,
        logoBytes: logoBytes,
      );
    } catch (e) {
      debugPrint('loadActiveOutlet error: $e');
      return null;
    }
  }

  // ── PUBLIC: Tampilkan preview struk ───────────────────────────────────────

  Future<void> showReceiptPreview(
      BuildContext context, ReceiptData data) async {
    final receiptKey = GlobalKey();
    final outlet = await _loadActiveOutlet();

    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.92,
        decoration: const BoxDecoration(
          color: Color(0xFFF1F5F9),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_long_rounded,
                    color: Color(0xFF2196F3), size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Preview Struk',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      Text('Tampilan struk sebelum dicetak',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(ctx),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Center(
                child: RepaintBoundary(
                  key: receiptKey,
                  child:
                      _ReceiptPreviewWidget(data: data, outlet: outlet),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _handlePrint(context, data, outlet: outlet);
                  },
                  icon: const Icon(Icons.print_rounded, size: 20),
                  label: const Text('Cetak Struk'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      final pngBytes = await _captureWidget(receiptKey);
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _shareReceiptImageOnly(pngBytes, data);
                    } catch (e) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      AppNotification.shareError();
                    }
                  },
                  icon: const Icon(Icons.share_rounded, size: 20),
                  label: const Text('Bagikan Struk'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<Uint8List> _captureWidget(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) throw Exception('Widget struk tidak ditemukan');
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('Gagal mengkonversi render ke PNG');
    }
    return byteData.buffer.asUint8List();
  }

  Future<void> _shareReceiptImageOnly(
      Uint8List pngBytes, ReceiptData data) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'struk_${data.transactionId.substring(0, 8)}'
          '_${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = '${tempDir.path}/$fileName';
      await File(filePath).writeAsBytes(pngBytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(filePath, mimeType: 'image/png', name: fileName)
          ],
        ),
      );
    } catch (e) {
      debugPrint('_shareReceiptImageOnly error: $e');
      AppNotification.shareError();
    }
  }

  // ── Cek Bluetooth ─────────────────────────────────────────────────────────

  Future<bool> _checkBluetoothOn() async {
    try {
      final state = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 3));
      if (state == BluetoothAdapterState.on) return true;
    } catch (_) {}

    // Dialog Bluetooth mati — tetap pakai Dialog supaya blocking
    await Get.dialog(
      Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header orange
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF8F00),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.bluetooth_disabled_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Bluetooth Mati',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ]),
              ),
              // Body
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFFF8F00)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline_rounded,
                          color: Color(0xFFFF8F00), size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Bluetooth perlu dinyalakan untuk mencetak struk via printer thermal.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF7B4F00),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Get.back(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6B7280),
                          side: const BorderSide(
                              color: Color(0xFFD1D5DB)),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Batal',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Get.back();
                          switch (OpenSettingsPlus.shared) {
                            case OpenSettingsPlusAndroid settings:
                              settings.bluetooth();
                            case OpenSettingsPlusIOS settings:
                              settings.bluetooth();
                            default:
                              if (Platform.isAndroid) {
                                FlutterBluePlus.turnOn();
                              }
                          }
                        },
                        icon: const Icon(Icons.bluetooth_rounded,
                            size: 18),
                        label: const Text('Nyalakan',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8F00),
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                ]),
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: true,
    );
    return false;
  }

  Future<void> _handlePrint(BuildContext context, ReceiptData data,
      {OutletInfo? outlet}) async {
    final btOk = await _checkBluetoothOn();
    if (!btOk) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('printerAddress') ?? '';
    if (saved.isEmpty) {
      await _autoPickPrinterAndPrint(data, outlet: outlet);
    } else {
      await _executePrint(data, outlet: outlet);
    }
  }

  Future<void> _autoPickPrinterAndPrint(ReceiptData data,
      {OutletInfo? outlet}) async {
    List<BluetoothDevice> devices = [];
    try {
      devices = await FlutterBluePlus.systemDevices([]);
    } catch (e) {
      debugPrint('systemDevices error: $e');
    }

    if (devices.isEmpty) {
      AppNotification.warning(
        'Printer Tidak Ditemukan',
        'Tidak ada perangkat Bluetooth yang terpasang. Pair printer di pengaturan Bluetooth terlebih dahulu.',
        duration: const Duration(seconds: 5),
        customIcon: Icons.print_disabled_rounded,
      );
      return;
    }

    if (devices.length == 1) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'printerAddress', devices.first.remoteId.toString());
      await _executePrint(data, outlet: outlet);
      return;
    }

    await Get.dialog(AlertDialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.print_rounded,
              color: Color(0xFF2196F3), size: 20),
        ),
        const SizedBox(width: 12),
        const Expanded(
            child: Text('Pilih Printer',
                style: TextStyle(fontSize: 16))),
      ]),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pilih printer yang akan digunakan:',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 12),
            ...devices.map((device) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3)
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bluetooth_rounded,
                        color: Color(0xFF2196F3), size: 20),
                  ),
                  title: Text(
                    device.platformName.isNotEmpty
                        ? device.platformName
                        : 'Unknown Device',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(device.remoteId.toString(),
                      style: const TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: Colors.grey),
                  onTap: () async {
                    Get.back();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString(
                        'printerAddress', device.remoteId.toString());
                    await _executePrint(data, outlet: outlet);
                  },
                )),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(), child: const Text('Batal')),
      ],
    ));
  }

  // ── _executePrint — pakai AppNotification.showPrintLoading (Lottie) ───────

  Future<void> _executePrint(ReceiptData data,
      {OutletInfo? outlet}) async {
    // Tampilkan dialog loading dengan Lottie
    AppNotification.showPrintLoading();

    try {
      await printReceipt(data, outlet: outlet);
      AppNotification.hidePrintLoading();
      AppNotification.printSuccess();
    } catch (e) {
      AppNotification.hidePrintLoading();
      final msg = e.toString();

      if (msg.contains('tidak ditemukan') ||
          msg.contains('belum diatur') ||
          msg.contains('not found')) {
        // Reset printer & coba pilih ulang
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('printerAddress');
        await _autoPickPrinterAndPrint(data, outlet: outlet);
      } else {
        AppNotification.printError(
          msg,
          onRetry: () => _executePrint(data, outlet: outlet),
        );
      }
    }
  }

  Future<void> printReceipt(ReceiptData data, {OutletInfo? outlet}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final printerAddress = prefs.getString('printerAddress');
      if (printerAddress == null || printerAddress.isEmpty) {
        throw Exception(
            'Printer belum diatur. Silakan setting printer terlebih dahulu.');
      }

      BluetoothDevice? targetDevice;

      try {
        for (var d in await FlutterBluePlus.systemDevices([])) {
          final id = d.remoteId.toString();
          if (id == printerAddress ||
              d.platformName == printerAddress ||
              id.toLowerCase() == printerAddress.toLowerCase()) {
            targetDevice = d;
            break;
          }
        }
      } catch (_) {}

      if (targetDevice == null) {
        try {
          for (var d in FlutterBluePlus.connectedDevices) {
            final id = d.remoteId.toString();
            if (id == printerAddress ||
                d.platformName == printerAddress ||
                id.toLowerCase() == printerAddress.toLowerCase()) {
              targetDevice = d;
              break;
            }
          }
        } catch (_) {}
      }

      if (targetDevice == null) {
        try {
          if (printerAddress.contains(':') ||
              printerAddress.contains('-')) {
            targetDevice = BluetoothDevice.fromId(
                printerAddress.replaceAll('-', ':').toUpperCase());
          }
        } catch (_) {}
      }

      if (targetDevice == null) {
        throw Exception(
            'Printer tidak ditemukan.\nPrinter tersimpan: $printerAddress');
      }

      final isConnected = FlutterBluePlus.connectedDevices
          .any((d) => d.remoteId == targetDevice!.remoteId);
      if (!isConnected) {
        await targetDevice.connect(
            timeout: const Duration(seconds: 15), autoConnect: false);
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final services = await targetDevice.discoverServices();
      BluetoothCharacteristic? writeChar;
      for (var s in services) {
        for (var c in s.characteristics) {
          if (c.properties.write || c.properties.writeWithoutResponse) {
            writeChar = c;
            break;
          }
        }
        if (writeChar != null) break;
      }
      if (writeChar == null) {
        await targetDevice.disconnect();
        throw Exception(
            'Printer tidak mendukung perintah print');
      }

      final bytes = await _generateEscPos(data, outlet: outlet);
      const chunkSize = 20;
      for (var i = 0; i < bytes.length; i += chunkSize) {
        final end =
            (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        final chunk = bytes.sublist(i, end);
        if (writeChar.properties.writeWithoutResponse) {
          await writeChar.write(chunk, withoutResponse: true);
        } else {
          await writeChar.write(chunk, withoutResponse: false);
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }

      await Future.delayed(const Duration(seconds: 1));
      await targetDevice.disconnect();
    } catch (e) {
      debugPrint('PrinterService error: $e');
      rethrow;
    }
  }

  // ── ESC/POS generator ─────────────────────────────────────────────────────

  Future<Uint8List> _generateEscPos(ReceiptData data,
      {OutletInfo? outlet}) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final lines = _buildReceiptLines(data, outlet: outlet);
    List<int> bytes = [];

    for (final line in lines) {
      switch (line.type) {
        case _LineType.separator:
          bytes += generator.text('================================');
          break;
        case _LineType.divider:
          bytes += generator.text('--------------------------------');
          break;
        case _LineType.blank:
          bytes += generator.feed(1);
          break;
        case _LineType.centerBig:
          bytes += generator.text(line.value,
              styles: const PosStyles(
                align: PosAlign.center,
                bold: true,
                height: PosTextSize.size2,
                width: PosTextSize.size2,
              ));
          break;
        case _LineType.centerBold:
          bytes += generator.text(line.value,
              styles:
                  const PosStyles(align: PosAlign.center, bold: true));
          break;
        case _LineType.center:
          for (final wrapped in _wrapText(line.value, 32)) {
            bytes += generator.text(wrapped,
                styles: const PosStyles(align: PosAlign.center));
          }
          break;
        case _LineType.keyValue:
          bytes += generator.row([
            PosColumn(text: line.label, width: 6),
            PosColumn(
                text: line.value,
                width: 6,
                styles: const PosStyles(align: PosAlign.right)),
          ]);
          break;
        case _LineType.totalRow:
          bytes += generator.row([
            PosColumn(
                text: line.label,
                width: 6,
                styles: const PosStyles(bold: true)),
            PosColumn(
                text: line.value,
                width: 6,
                styles: const PosStyles(
                    align: PosAlign.right, bold: true)),
          ]);
          break;
        case _LineType.splitRow:
        case _LineType.kembalianRow:
          bytes += generator.row([
            PosColumn(text: line.label, width: 6),
            PosColumn(
                text: line.value,
                width: 6,
                styles: const PosStyles(align: PosAlign.right)),
          ]);
          break;
        case _LineType.itemHeader:
          bytes += generator.text(
            '${line.label} ${line.value}',
            styles: const PosStyles(bold: true),
          );
          break;
        case _LineType.itemDetail:
          bytes += generator.row([
            PosColumn(text: '   ${line.label}', width: 7),
            PosColumn(
                text: line.value,
                width: 5,
                styles: const PosStyles(align: PosAlign.right)),
          ]);
          break;
        case _LineType.itemPrice:
          if (line.label.isEmpty) {
            bytes += generator.row([
              PosColumn(text: '', width: 6),
              PosColumn(
                  text: line.value,
                  width: 6,
                  styles: const PosStyles(
                      align: PosAlign.right, bold: true)),
            ]);
          } else {
            bytes += generator.row([
              PosColumn(text: '  ${line.label}', width: 7),
              PosColumn(
                  text: line.value,
                  width: 5,
                  styles: const PosStyles(
                      align: PosAlign.right, bold: true)),
            ]);
          }
          break;
        case _LineType.logo:
          if (line.imageData != null) {
            try {
              final escLogoBytes =
                  await _logoToEscPos(generator, line.imageData!);
              if (escLogoBytes != null) bytes += escLogoBytes;
            } catch (e) {
              debugPrint('Logo ESC/POS error: $e');
            }
          }
          break;
      }
    }

    bytes += generator.feed(2);
    bytes += generator.cut();
    return Uint8List.fromList(bytes);
  }

  static List<String> _wrapText(String text, int maxChars) {
    if (text.length <= maxChars) return [text];
    final words = text.split(' ');
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      if (current.isEmpty) {
        current = word;
      } else if ((current.length + 1 + word.length) <= maxChars) {
        current += ' $word';
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  Future<List<int>?> _logoToEscPos(
      Generator generator, Uint8List imageBytes) async {
    try {
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) return null;

      const maxWidth = 200;
      if (image.width > maxWidth) {
        final ratio = maxWidth / image.width;
        image = img.copyResize(
          image,
          width: maxWidth,
          height: (image.height * ratio).round(),
          interpolation: img.Interpolation.average,
        );
      }

      image = img.grayscale(image);
      return generator.imageRaster(image, align: PosAlign.center);
    } catch (e) {
      debugPrint('_logoToEscPos error: $e');
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Preview Widget
// ─────────────────────────────────────────────────────────────────────────────

class _ReceiptPreviewWidget extends StatelessWidget {
  final ReceiptData data;
  final OutletInfo? outlet;
  const _ReceiptPreviewWidget({required this.data, this.outlet});

  static const _black = Color(0xFF000000);
  static const _dark = Color(0xFF1A1A1A);
  static const _medium = Color(0xFF555555);
  static const _light = Color(0xFF888888);
  static const _lineColor = Color(0xFFBBBBBB);
  static const _bg = Color(0xFFFFFFFF);
  static const _fontFamily = 'monospace';

  @override
  Widget build(BuildContext context) {
    final lines = PrinterService._buildReceiptLines(data, outlet: outlet);

    return Container(
      width: 300,
      color: _bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: lines.map(_buildLine).toList(),
        ),
      ),
    );
  }

  Widget _buildLine(_Line line) {
    switch (line.type) {
      case _LineType.separator:
        return _solidLine(thick: true);
      case _LineType.divider:
        return _solidLine(thick: false);
      case _LineType.blank:
        return const SizedBox(height: 5);
      case _LineType.logo:
        if (line.imageData == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxHeight: 64, maxWidth: 200),
              child: Image.memory(line.imageData!, fit: BoxFit.contain),
            ),
          ),
        );
      case _LineType.centerBig:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(line.value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _black,
                fontFamily: _fontFamily,
                letterSpacing: 1.5,
              )),
        );
      case _LineType.centerBold:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(line.value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: line.color ?? _dark,
                fontFamily: _fontFamily,
              )),
        );
      case _LineType.center:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text(line.value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                color: _light,
                fontFamily: _fontFamily,
              )),
        );
      case _LineType.keyValue:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Text(line.label,
                style: const TextStyle(
                    fontSize: 11,
                    color: _medium,
                    fontFamily: _fontFamily)),
            Expanded(
              child: Text(line.value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      fontSize: 11,
                      color: _dark,
                      fontWeight: FontWeight.w600,
                      fontFamily: _fontFamily)),
            ),
          ]),
        );
      case _LineType.totalRow:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            const Text('TOTAL',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _black,
                    fontFamily: _fontFamily)),
            Expanded(
              child: Text(line.value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _black,
                      fontFamily: _fontFamily)),
            ),
          ]),
        );
      case _LineType.splitRow:
      case _LineType.kembalianRow:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Text(line.label,
                style: const TextStyle(
                    fontSize: 11,
                    color: _medium,
                    fontFamily: _fontFamily)),
            Expanded(
              child: Text(line.value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _dark,
                      fontFamily: _fontFamily)),
            ),
          ]),
        );
      case _LineType.itemHeader:
        return Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(right: 6, top: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: Text(line.label.replaceAll('.', ''),
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2196F3),
                          fontFamily: _fontFamily)),
                ),
              ),
              Expanded(
                child: Text(line.value,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _dark,
                        fontFamily: _fontFamily)),
              ),
            ],
          ),
        );
      case _LineType.itemDetail:
        return Padding(
          padding: const EdgeInsets.only(left: 24, bottom: 1),
          child: Row(children: [
            Text('${line.label}: ',
                style: const TextStyle(
                    fontSize: 10,
                    color: _medium,
                    fontFamily: _fontFamily)),
            Expanded(
              child: Text(line.value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                      fontSize: 10,
                      color: _dark,
                      fontWeight: FontWeight.w600,
                      fontFamily: _fontFamily)),
            ),
          ]),
        );
      case _LineType.itemPrice:
        return Padding(
          padding: const EdgeInsets.only(left: 24, bottom: 3),
          child: Row(children: [
            if (line.label.isNotEmpty)
              Text(line.label,
                  style: const TextStyle(
                      fontSize: 10,
                      color: _medium,
                      fontFamily: _fontFamily)),
            const Spacer(),
            Text(line.value,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _dark,
                    fontFamily: _fontFamily)),
          ]),
        );
    }
  }

  Widget _solidLine({required bool thick}) => Padding(
        padding: EdgeInsets.symmetric(vertical: thick ? 5 : 4),
        child:
            Container(height: thick ? 1.5 : 0.8, color: _lineColor),
      );
}