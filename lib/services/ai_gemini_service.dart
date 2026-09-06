// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:csv/csv.dart';

class AIGeminiService {
  late GenerativeModel _model;
  final String apiKey;

  AIGeminiService({required this.apiKey}) {
    _model = GenerativeModel(
      model: 'gemini-3.5-flash-lite',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.1,
        maxOutputTokens: 2048,
      ),
    );
  }

  String buildDefaultPrompt(List<String> headers) {
    return '''
Saya memiliki data CSV transaksi PPOB dengan header berikut:
${headers.join(', ')}

Tolong analisis dan mapping field-field berikut dari CSV:
1. Nomor Transaksi (transaction number)
2. Tanggal Transaksi (date/time)
3. Nama Pelanggan (customer name)
4. No HP/Telepon Pelanggan (phone number)
5. Jenis Produk/Layanan (product type: listrik, token, pulsa, paket data, bpjs, pdam, indihome)
6. Nama Produk (product name)
7. Nominal/Harga (amount)
8. Biaya Admin (admin fee)
9. Total Bayar (total amount)
10. Status Pembayaran (payment status: lunas/belum lunas)
11. Metode Pembayaran (payment method: cash, transfer, qris, ewallet)
12. No Meter (untuk listrik)
13. ID Pelanggan (untuk BPJS, Indihome, PDAM)
14. Tarif/Daya (untuk listrik)
15. Periode/Bulan (untuk tagihan bulanan)
16. Token Number (untuk token listrik)
17. KWH (untuk token listrik)
18. Paket Info (untuk Indihome, dll)

Berikan hasil mapping dalam format JSON seperti ini:
{
  "mappings": {
    "transactionNumber": "nama_kolom_di_csv",
    "transactionDate": "nama_kolom_di_csv",
    "customerName": "nama_kolom_di_csv",
    "customerPhone": "nama_kolom_di_csv",
    "productType": "nama_kolom_di_csv",
    "productName": "nama_kolom_di_csv",
    "amount": "nama_kolom_di_csv",
    "adminFee": "nama_kolom_di_csv",
    "totalAmount": "nama_kolom_di_csv",
    "paymentStatus": "nama_kolom_di_csv",
    "paymentMethod": "nama_kolom_di_csv",
    "meterNumber": "nama_kolom_di_csv atau null",
    "customerId": "nama_kolom_di_csv atau null",
    "tariff": "nama_kolom_di_csv atau null",
    "period": "nama_kolom_di_csv atau null",
    "tokenNumber": "nama_kolom_di_csv atau null",
    "kwh": "nama_kolom_di_csv atau null",
    "packageInfo": "nama_kolom_di_csv atau null"
  }
}

Jika field tidak ada di CSV, isi dengan null.
Hanya berikan JSON, tanpa penjelasan tambahan.
''';
  }

  Future<List<Map<String, String?>>> mapCsvToFieldMaps(
    File csvFile, {
    String Function(List<String> headers)? promptBuilder,
  }) async {
    final input = csvFile.readAsStringSync();
    final normalizedInput = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final fields = const CsvToListConverter(eol: '\n', shouldParseNumbers: false).convert(normalizedInput);

    if (fields.isEmpty) return [];

    // FIX: Trim header
    final headers = fields[0].map((e) => e.toString().trim()).toList();
    final prompt = (promptBuilder ?? buildDefaultPrompt)(headers);

    final content = [Content.text(prompt)];
    final response = await _model.generateContent(content);

    if (response.candidates.isEmpty) {
      throw Exception('Gemini tidak mengembalikan candidate. promptFeedback: ${response.promptFeedback}');
    }

    final responseText = response.text ?? '';
    if (responseText.trim().isEmpty) {
      throw Exception('Response Gemini kosong.');
    }

    final mappings = _parseAIResponse(responseText);
    final List<Map<String, String?>> results = [];

    for (int i = 1; i < fields.length; i++) {
      final row = fields[i];
      final Map<String, dynamic> rowData = {};
      for (int j = 0; j < headers.length && j < row.length; j++) {
        rowData[headers[j]] = row[j];
      }

      dynamic getValue(String mappingKey) {
        String? columnName = mappings[mappingKey];
        if (columnName == null || columnName == 'null') return null;
        return rowData[columnName];
      }

      final Map<String, String?> mappedRow = {};
      for (final key in [
        'transactionNumber', 'transactionDate', 'customerName', 'customerPhone',
        'productType', 'productName', 'amount', 'adminFee', 'totalAmount',
        'paymentStatus', 'paymentMethod', 'meterNumber', 'customerId',
        'tariff', 'period', 'tokenNumber', 'kwh', 'packageInfo',
      ]) {
        final v = getValue(key);
        mappedRow[key] = _normalizeField(key, v?.toString());
      }

      // FIX: Post-processing untuk memecah data yang tergabung (Merged Fields)
      _extractMergedFields(mappedRow);

      results.add(mappedRow);
    }

    return results;
  }

  // ===========================================================================
  // Helper: Ekstraksi data yang tergabung dalam satu kolom (Merged Fields)
  // ===========================================================================
  void _extractMergedFields(Map<String, String?> mappedRow) {
    // 1. Ekstrak No HP dari Nama Pelanggan jika kolom HP kosong
    if (mappedRow['customerPhone'] == null && mappedRow['customerName'] != null) {
      String name = mappedRow['customerName']!;
      RegExp phoneRegex = RegExp(r'(?:0|\+?62)?8\d{8,11}');
      var match = phoneRegex.firstMatch(name);
      if (match != null) {
        String extractedPhone = match.group(0)!;
        if (extractedPhone.startsWith('62')) {
          extractedPhone = '0${extractedPhone.substring(2)}';
        } else if (extractedPhone.startsWith('8')) {
          extractedPhone = '0$extractedPhone';
        }

        mappedRow['customerPhone'] = extractedPhone;
        mappedRow['customerName'] = name.replaceAll(match.group(0)!, '').replaceAll(RegExp(r'[\s\-\(\)\|,]+'), ' ').trim();
      }
    }

    // 2. Ekstrak Periode dari Nama Produk jika kolom Periode kosong
    if (mappedRow['period'] == null && mappedRow['productName'] != null) {
      String prodName = mappedRow['productName']!;
      RegExp periodRegex = RegExp(r'(?:periode|bulan)\s+([a-zA-Z0-9/\s]+)', caseSensitive: false);
      var match = periodRegex.firstMatch(prodName);
      if (match != null) {
        mappedRow['period'] = match.group(1)!.trim();
        mappedRow['productName'] = prodName.replaceAll(match.group(0)!, '').replaceAll(RegExp(r'[\s\-\|,/]+'), ' ').trim();
      }
    }

    // 3. Ekstrak No Meter dari Nama Produk jika kolom Meter kosong
    if (mappedRow['meterNumber'] == null && mappedRow['productName'] != null) {
      String prodName = mappedRow['productName']!;
      RegExp meterRegex = RegExp(r'(?:meter|no\s+meter)\s+(\d+)', caseSensitive: false);
      var match = meterRegex.firstMatch(prodName);
      if (match != null) {
        mappedRow['meterNumber'] = match.group(1)!.trim();
        mappedRow['productName'] = prodName.replaceAll(match.group(0)!, '').replaceAll(RegExp(r'[\s\-\|,]+'), ' ').trim();
      }
    }

    // 4. Ekstrak KWH dari Nama Produk
    if (mappedRow['kwh'] == null && mappedRow['productName'] != null) {
      String prodName = mappedRow['productName']!;
      RegExp kwhRegex = RegExp(r'(\d+(?:\.\d+)?)\s*kwh', caseSensitive: false);
      var match = kwhRegex.firstMatch(prodName);
      if (match != null) {
        mappedRow['kwh'] = match.group(1)!.replaceAll('.', '').trim();
        mappedRow['productName'] = prodName.replaceAll(match.group(0)!, '').replaceAll(RegExp(r'[\s\-\|,/]+'), ' ').trim();
      }
    }
  }

  // ===========================================================================
  // Helper: Normalisasi nilai field agar sesuai standar Ground Truth
  // ===========================================================================
  String? _normalizeField(String key, String? rawValue) {
    if (rawValue == null || rawValue.trim().isEmpty) return rawValue;
    String val = rawValue.trim();
    String valLower = val.toLowerCase();

    // 1. Normalisasi Nomor HP (hapus simbol, pastikan awalan 0)
    if (key == 'customerPhone') {
      String digits = val.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.startsWith('62')) {
        digits = '0${digits.substring(2)}';
      } else if (digits.startsWith('8')) {
        digits = '0$digits';
      }
      return digits.isEmpty ? null : digits;
    }

    // 2. Normalisasi Tanggal ke format YYYYMMDD
    if (key == 'transactionDate') {
      try {
        DateTime dt = DateTime.parse(val);
        return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
      } catch (_) {}

      RegExp dmyRegex = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})');
      var match = dmyRegex.firstMatch(val);
      if (match != null) {
        int day = int.parse(match.group(1)!);
        int month = int.parse(match.group(2)!);
        int year = int.parse(match.group(3)!);
        return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      }

      RegExp ymdRegex = RegExp(r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})');
      match = ymdRegex.firstMatch(val);
      if (match != null) {
        int year = int.parse(match.group(1)!);
        int month = int.parse(match.group(2)!);
        int day = int.parse(match.group(3)!);
        return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      }

      RegExp ddmmyyyyRegex = RegExp(r'^(\d{2})(\d{2})(\d{4})$');
      match = ddmmyyyyRegex.firstMatch(val);
      if (match != null) return '${match.group(3)}-${match.group(2)}-${match.group(1)}';

      RegExp textDateRegex = RegExp(r'^(\d{1,2})\s+([a-zA-Z]+)\s+(\d{4})');
      match = textDateRegex.firstMatch(val);
      if (match != null) {
        int day = int.parse(match.group(1)!);
        String monthStr = match.group(2)!.toLowerCase();
        int year = int.parse(match.group(3)!);
        Map<String, int> months = {
          'januari': 1, 'january': 1, 'feb': 2, 'februari': 2, 'february': 2,
          'maret': 3, 'mar': 3, 'march': 3, 'april': 4, 'mei': 5, 'may': 5,
          'juni': 6, 'jun': 6, 'june': 6, 'juli': 7, 'jul': 7, 'july': 7,
          'agustus': 8, 'aug': 8, 'august': 8, 'september': 9, 'sep': 9,
          'oktober': 10, 'oct': 10, 'october': 10, 'november': 11, 'nov': 11,
          'desember': 12, 'dec': 12, 'december': 12
        };
        int month = months[monthStr] ?? 1;
        return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      }
      return val;
    }

    // 3. Normalisasi Nominal (Amount, AdminFee, TotalAmount) jadi angka murni
    if (key == 'amount' || key == 'adminFee' || key == 'totalAmount') {
      String cleaned = val.replaceAll('Rp', '').replaceAll(' ', '').replaceAll('-', '').trim();

      // Deteksi: kalau ada titik DAN koma, yang terakhir muncul adalah desimal
      final lastDot = cleaned.lastIndexOf('.');
      final lastComma = cleaned.lastIndexOf(',');

      if (lastDot != -1 && lastComma != -1) {
        if (lastComma > lastDot) {
          // format "1.234,56" -> titik ribuan, koma desimal
          cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
        } else {
          // format "1,234.56" -> koma ribuan, titik desimal
          cleaned = cleaned.replaceAll(',', '');
        }
      } else if (lastComma != -1) {
        // hanya koma: cek apakah pola desimal (2 digit di belakang) atau ribuan
        final afterComma = cleaned.substring(lastComma + 1);
        cleaned = afterComma.length == 2
            ? cleaned.replaceAll(',', '.')   // "150,50" -> desimal
            : cleaned.replaceAll(',', '');   // "150,000" -> ribuan
      } else if (lastDot != -1) {
        final afterDot = cleaned.substring(lastDot + 1);
        if (afterDot.length == 2 || afterDot == '00' || afterDot.isEmpty) {
          cleaned = cleaned.substring(0, lastDot) + (afterDot.isEmpty ? '' : '.$afterDot');
        } else {
          cleaned = cleaned.replaceAll('.', ''); // ribuan gaya "1.000.000"
        }
      }

      double? parsed = double.tryParse(cleaned);
      if (parsed != null) return parsed.round().toString();
      return val;
    }

    // 4. Normalisasi ProductType
    if (key == 'productType') {
      if (valLower.contains('token')) return 'token';
      if (valLower.contains('paket') || valLower.contains('data')) return 'paketdata';
      if (valLower.contains('listrik')) return 'listrik';
      if (valLower.contains('pulsa')) return 'pulsa';
      if (valLower.contains('bpjs')) return 'bpjs';
      if (valLower.contains('pdam') || valLower.contains('air')) return 'pdam';
      if (valLower.contains('indihome') || valLower.contains('internet')) return 'indihome';
      return 'lainnya';
    }

    // 5. Normalisasi PaymentStatus
    if (key == 'paymentStatus') {
      if (valLower.contains('lunas') || valLower.contains('sukses') || valLower.contains('berhasil') || 
          valLower.contains('paid') || valLower.contains('ok') || valLower.contains('success')) {
        return 'lunas';
      }
      return 'belumlunas';
    }

    // 6. Normalisasi PaymentMethod
    if (key == 'paymentMethod') {
      if (valLower.contains('cash') || valLower.contains('tunai')) return 'cash';
      if (valLower.contains('transfer') || valLower.contains('bank')) return 'transfer';
      if (valLower.contains('qris')) return 'qris';
      if (valLower.contains('wallet') || valLower.contains('ewallet') || valLower.contains('ovo') || 
          valLower.contains('gopay') || valLower.contains('dana') || valLower.contains('shopee')) {
        return 'ewallet';
      }
      return 'cash';
    }

    // 7. Pembersihan Prefix untuk MeterNumber & CustomerId
    if (key == 'meterNumber' || key == 'customerId') {
      String cleaned = val.replaceAll(RegExp(r'^(no\s+meter|id\s+pelanggan|meter|id)\s*', caseSensitive: false), '').trim();
      return cleaned.isEmpty ? null : cleaned;
    }
    
    return val; 
  }

  Map<String, dynamic> _parseAIResponse(String response) {
    try {
      String cleaned = response.replaceAll('```json', '').replaceAll('```', '').trim();
      int startIndex = cleaned.indexOf('{');
      int endIndex = cleaned.lastIndexOf('}') + 1;

      if (startIndex < 0 || endIndex <= startIndex) {
        throw Exception('Invalid AI response format: no JSON object found.');
      }

      String jsonStr = cleaned.substring(startIndex, endIndex);
      Map<String, dynamic> parsed = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (parsed.containsKey('mappings') && parsed['mappings'] is Map) {
        return Map<String, dynamic>.from(parsed['mappings'] as Map);
      }
      return parsed;
    } catch (e) {
      print('Error parsing AI response: $e');
      rethrow;
    }
  }
}