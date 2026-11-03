import 'dart:io';
import 'package:strusa/models/ground_truth_mapping.dart';

/// base : ground truth utama
/// B    : paymentMethod=null ("Saldo Akun" bukan kanal bayar pelanggan)
/// C    : buang baris Harga=0 (transaksi cek/gift, bukan penjualan)
GroundTruthDataset applyGtVariant(GroundTruthDataset d) {
  final v = Platform.environment['GT_VARIANT'] ?? 'base';
  if (v == 'base' || d.edgeCaseCategory != 'real_data') return d;
  var rows = d.expectedRows.map((r) => Map<String, String?>.from(r)).toList();
  if (v == 'B') {
    for (final r in rows) { r['paymentMethod'] = null; }
  } else if (v == 'C') {
    rows = rows.where((r) => r['amount'] != '0').toList();
  }
  return GroundTruthDataset(
    id: d.id, dataFilePath: d.dataFilePath, platform: d.platform,
    edgeCaseCategory: d.edgeCaseCategory, description: d.description,
    expectedRows: rows);
}