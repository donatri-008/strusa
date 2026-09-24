import 'dart:io';
// Sesuaikan path import ini dengan struktur folder project Anda
import 'package:strusa/services/rule_based_mapper_service.dart'; 

void main() async {
  // 1. Buat file CSV sementara berisi 1 baris data + header (sesuai data AgenPulsa/OrderKuota Anda)
  final tempFile = File('temp_sample.csv');
  final csvContent = '''ID, Produk,Provider,NO. HP,Nominal,Harga,Tanggal,Status, Metode Pembayaran
727860357, Paket Internet,Indosat (Old Freedom),085631241968,"Freedom Internet 9GB, 28 Hari",32947,31/08/2026 14:08,SUKSES, Tunai''';
  
  await tempFile.writeAsString(csvContent);

  // 2. Jalankan Rule-Based Mapper
  print('=== HASIL RULE-BASED MAPPER (Output Asli dari Kode) ===');
  final ruleBasedResult = await RuleBasedMapperService().mapCsvToFieldMaps(tempFile);
  
  for (var row in ruleBasedResult) {
    // Kita hanya print field yang relevan untuk Tabel 4
    final relevantFields = ['transactionNumber','productType', 'productName', 'customerPhone', 'amount', 'packageDescription', 'transactionDate', 'paymentStatus', 'paymentMethod'];
    print('{');
    for (var key in relevantFields) {
      if (row.containsKey(key)) {
        final value = row[key];
        print('  "$key": ${value == null ? 'null' : '"$value"'}');
      }
    }
    print('}');
  }

  // 3. Bersihkan file sementara
  await tempFile.delete();
}