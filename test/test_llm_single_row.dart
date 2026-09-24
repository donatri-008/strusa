import 'dart:io';
import 'dart:convert';
// Pastikan path import ini sesuai dengan struktur folder project Anda
import 'package:strusa/services/ai_gemini_service.dart'; 

void main() async {
  // 1. Masukkan API Key Gemini Anda di sini (atau biarkan kosong jika sudah di-set di environment)
  final apiKey = Platform.environment['GEMINI_API_KEY'] ?? 'apikey';
  
  if (apiKey.isEmpty || apiKey == 'MASUKKAN_API_KEY_ANDA_DISINI') {
    print('⚠️ Error: GEMINI_API_KEY kosong. Silakan isi variabel apiKey di kode atau set via terminal.');
    return;
  }

  // 2. Buat file CSV sementara berisi Header + 1 Baris Data (Sesuai data AgenPulsa/OrderKuota Anda)
  final tempFile = File('temp_sample_llm.csv');
  final csvContent = '''ID,Produk,Provider,NO. HP,Nominal,Harga,Tanggal,Status,Metode Pembayaran
727860357,Paket Internet,Indosat (Old Freedom),085631241968,"Freedom Internet 9GB, 28 Hari",32947,31/08/2026 14:08,SUKSES,Tunai''';
  
  await tempFile.writeAsString(csvContent);
  print('📄 File sementara dibuat: ${tempFile.absolute.path}\n');

  // 3. Jalankan LLM Mapper
  print('=== HASIL GENERATIVE LLM MAPPER (Output Asli dari Kode) ===');
  try {
    final llmResult = await AIGeminiService(apiKey: apiKey).mapCsvToFieldMaps(tempFile);

    for (var row in llmResult) {
      // Kita hanya print 9 core fields yang relevan untuk Tabel 4 Jurnal
      final relevantFields = [
        'transactionNumber',
        'transactionDate',
        'customerPhone',
        'productType',
        'productName',
        'amount',
        'paymentStatus',
        'paymentMethod',
        'packageDescription'
      ];

      print('{');
      for (var key in relevantFields) {
        if (row.containsKey(key)) {
          final value = row[key];
          // Format output agar rapi: "key": "value"  atau  "key": null
          print('  "$key": ${value == null ? 'null' : '"$value"'}');
        }
      }
      print('}');
    }
  } catch (e, stackTrace) {
    print('❌ Error saat memanggil LLM:');
    print(e);
    print(stackTrace);
  } finally {
    // 4. Bersihkan file sementara agar tidak menumpuk
    if (await tempFile.exists()) {
      await tempFile.delete();
      print('\n🧹 File sementara telah dihapus.');
    }
  }
}