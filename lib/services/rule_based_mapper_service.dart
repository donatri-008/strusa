import 'dart:io';
import 'package:csv/csv.dart';

/// Baseline RULE-BASED / REGEX untuk pemetaan CSV -> field transaksi.
class RuleBasedMapperService {
  static final Map<String, List<RegExp>> _fieldPatterns = {
    'transactionNumber': [
      RegExp(r'no\.?\s*trx', caseSensitive: false),
      RegExp(r'nomor\s*transaksi', caseSensitive: false),
      RegExp(r'no\.?\s*transaksi', caseSensitive: false),
      RegExp(r'reference\s*id', caseSensitive: false),
      RegExp(r'trx[_\-]?id', caseSensitive: false),
      RegExp(r'^id$', caseSensitive: false),
    ],
    'transactionDate': [
      RegExp(r'tanggal', caseSensitive: false),
      RegExp(r'\btgl\b', caseSensitive: false),
      RegExp(r'waktu', caseSensitive: false),
      RegExp(r'\bdate\b', caseSensitive: false),
      RegExp(r'trx[_\-]?time', caseSensitive: false),
    ],
    'customerName': [
      RegExp(r'nama\s*pelanggan', caseSensitive: false),
      RegExp(r'customer[_\-]?name', caseSensitive: false),
      RegExp(r'cust[_\-]?name', caseSensitive: false),
      RegExp(r'^nama$', caseSensitive: false),
      RegExp(r'^pelanggan$', caseSensitive: false),
    ],
    'customerPhone': [
      RegExp(r'no\.?\s*hp', caseSensitive: false),
      RegExp(r'nomor\s*tujuan', caseSensitive: false),
      RegExp(r'no\.?\s*telp', caseSensitive: false),
      RegExp(r'\bphone\b', caseSensitive: false),
      RegExp(r'msisdn', caseSensitive: false),
      RegExp(r'\bhp\b', caseSensitive: false),
    ],
    'productType': [
      RegExp(r'jenis\s*produk', caseSensitive: false),
      RegExp(r'kategori', caseSensitive: false),
      RegExp(r'jenis\s*layanan', caseSensitive: false),
      RegExp(r'^tipe$', caseSensitive: false),
      RegExp(r'prod[_\-]?cat', caseSensitive: false),
    ],
    'productName': [
      RegExp(r'nama\s*produk', caseSensitive: false),
      RegExp(r'^produk$', caseSensitive: false),
      RegExp(r'^item$', caseSensitive: false),
      RegExp(r'deskripsi', caseSensitive: false),
      RegExp(r'prod[_\-]?name', caseSensitive: false),
      RegExp(r'keterangan', caseSensitive: false),
    ],
    'amount': [
      RegExp(r'nominal', caseSensitive: false),
      RegExp(r'^harga$', caseSensitive: false),
      RegExp(r'^amount$', caseSensitive: false),
      RegExp(r'jumlah\s*bayar', caseSensitive: false),
      RegExp(r'base[_\-]?price', caseSensitive: false),
    ],
    'adminFee': [
      RegExp(r'biaya\s*admin', caseSensitive: false),
      RegExp(r'admin\s*fee', caseSensitive: false),
      RegExp(r'^fee$', caseSensitive: false),
      RegExp(r'biaya', caseSensitive: false),
      RegExp(r'nominal', caseSensitive: false),
    ],
    'totalAmount': [
      RegExp(r'total\s*bayar', caseSensitive: false),
      RegExp(r'^total$', caseSensitive: false),
      RegExp(r'grand[_\-]?total', caseSensitive: false),
    ],
    'paymentStatus': [
      RegExp(r'status\s*bayar', caseSensitive: false),
      RegExp(r'^status$', caseSensitive: false),
      RegExp(r'pay[_\-]?status', caseSensitive: false),
    ],
    'paymentMethod': [
      RegExp(r'metode\s*bayar', caseSensitive: false),
      RegExp(r'payment[_\-]?method', caseSensitive: false),
      RegExp(r'pay[_\-]?method', caseSensitive: false),
      RegExp(r'^metode$', caseSensitive: false),
      RegExp(r'keterangan', caseSensitive: false),
    ],
    'meterNumber': [
      RegExp(r'no\.?\s*meter', caseSensitive: false),
      RegExp(r'id\s*meter', caseSensitive: false),
    ],
    'customerId': [
      RegExp(r'id\s*pelanggan', caseSensitive: false),
      RegExp(r'no\.?\s*va\b', caseSensitive: false),
      RegExp(r'virtual\s*account', caseSensitive: false),
    ],
    'tariff': [
      RegExp(r'tarif', caseSensitive: false),
      RegExp(r'\bdaya\b', caseSensitive: false),
    ],
    'period': [
      RegExp(r'periode', caseSensitive: false),
      RegExp(r'^bulan$', caseSensitive: false),
    ],
    'tokenNumber': [
      RegExp(r'token', caseSensitive: false),
    ],
    'kwh': [
      RegExp(r'\bkwh\b', caseSensitive: false),
      RegExp(r'stroom', caseSensitive: false),
    ],
    'packageInfo': [
      RegExp(r'paket', caseSensitive: false),
      RegExp(r'^notes$', caseSensitive: false),
      RegExp(r'^catatan$', caseSensitive: false),
    ],
  };

  Map<String, int?> mapHeaderIndices(List<String> headers) {
    final Map<String, int?> mapping = {};
    final Set<int> usedIndices = {};

    for (final field in _fieldPatterns.keys) {
      int? matchedIndex;
      for (final pattern in _fieldPatterns[field]!) {
        for (int i = 0; i < headers.length; i++) {
          if (usedIndices.contains(i)) continue;
          if (pattern.hasMatch(headers[i])) {
            matchedIndex = i;
            break;
          }
        }
        if (matchedIndex != null) break;
      }
      mapping[field] = matchedIndex;
      if (matchedIndex != null) usedIndices.add(matchedIndex);
    }
    return mapping;
  }

  Future<List<Map<String, String?>>> mapCsvToFieldMaps(File csvFile) async {
    final input = await csvFile.readAsString();
    final normalizedInput = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final fields = const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(normalizedInput);

    if (fields.isEmpty || fields.length < 2) return [];

    final headers = fields[0].map((e) => e.toString().trim()).toList();
    final mapping = mapHeaderIndices(headers);
    final List<Map<String, String?>> results = [];

    for (int i = 1; i < fields.length; i++) {
      final row = fields[i];
      final Map<String, String?> mappedRow = {};

      for (final field in mapping.keys) {
        final colIndex = mapping[field];
        if (colIndex == null || colIndex >= row.length) {
          mappedRow[field] = null;
        } else {
          String? cleanValue = row[colIndex]?.toString().trim();
          if (cleanValue != null && ['amount', 'adminFee', 'totalAmount'].contains(field)) {
            cleanValue = _cleanNumeric(cleanValue);
          }
          mappedRow[field] = cleanValue?.isEmpty == true ? null : cleanValue;
        }
      }

      // ec08: Handle merged fields (Nama & No HP)
      if (mappedRow['customerPhone'] == null && mappedRow['customerName'] != null) {
        final phoneMatch = RegExp(r'(\+62|62|0)\d{8,15}').firstMatch(mappedRow['customerName']!);
        if (phoneMatch != null) {
          mappedRow['customerPhone'] = phoneMatch.group(0);
          mappedRow['customerName'] = mappedRow['customerName']!
              .replaceAll(phoneMatch.group(0)!, '')
              .replaceAll(RegExp(r'[\-\|\(\),]'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
        }
      }

      // ec08: Extract kWh from productName
      if (mappedRow['kwh'] == null && mappedRow['productName'] != null) {
        final kwhMatch = RegExp(r'(\d+\.?\d*)\s*kwh', caseSensitive: false).firstMatch(mappedRow['productName']!);
        if (kwhMatch != null) mappedRow['kwh'] = kwhMatch.group(1);
      }

      // ec08: Extract meterNumber from productName (e.g., "Meter 12345678")
      if (mappedRow['meterNumber'] == null && mappedRow['productName'] != null) {
        final meterMatch = RegExp(r'meter\s*[:\-]?\s*(\d+)', caseSensitive: false).firstMatch(mappedRow['productName']!);
        if (meterMatch != null) mappedRow['meterNumber'] = meterMatch.group(1);
      }

      // ec08: Extract period from productName (e.g., "Periode 06/2025" or "Juli 2025")
      if (mappedRow['period'] == null && mappedRow['productName'] != null) {
        final periodMatch = RegExp(r'(?:periode|bulan)\s*[:\-]?\s*(\d{2}/\d{4}|\d{4})', caseSensitive: false).firstMatch(mappedRow['productName']!);
        if (periodMatch != null) {
          mappedRow['period'] = periodMatch.group(1);
        } else {
          final monthYearMatch = RegExp(r'(januari|februari|maret|april|mei|juni|juli|agustus|september|oktober|november|desember)\s+\d{4}', caseSensitive: false).firstMatch(mappedRow['productName']!);
          if (monthYearMatch != null) mappedRow['period'] = monthYearMatch.group(0);
        }
      }

      if (mappedRow['tariff'] == null && mappedRow['productName'] != null) {
        final tariffMatch = RegExp(
          r'\b([a-z]\d\s*/\s*\d+\s*va)\b',
          caseSensitive: false,
        ).firstMatch(mappedRow['productName']!);
        if (tariffMatch != null) {
          mappedRow['tariff'] = tariffMatch
              .group(1)!
              .replaceAll(RegExp(r'\s+'), '')
              .toUpperCase();
        }
      }

      if (mappedRow['productName'] != null) {
        String name = mappedRow['productName']!;
        name = name.replaceAll(RegExp(r'\s*/\s*\d+\.?\d*\s*kwh.*$', caseSensitive: false), '');
        name = name.replaceAll(RegExp(r'\s*-\s*(periode|meter|bulan).*$', caseSensitive: false), '');
        mappedRow['productName'] = name.trim();
      }

      if (mappedRow['productType'] == null && mappedRow['productName'] != null) {
        mappedRow['productType'] = _normalizeProductType(mappedRow['productName']);
      }
      if (mappedRow['packageInfo'] != null) {
        String info = mappedRow['packageInfo']!;

        if (mappedRow['meterNumber'] == null) {
          final meterMatch = RegExp(r'no\.?\s*meter\s*[:\-]?\s*(\d+)', caseSensitive: false).firstMatch(info);
          if (meterMatch != null) {
            mappedRow['meterNumber'] = meterMatch.group(1);
            info = info.replaceAll(meterMatch.group(0)!, '').trim();
          }
        }

        if (mappedRow['customerId'] == null) {
          final idMatch = RegExp(r'id\s*pelanggan\s*[:\-]?\s*(\S+)', caseSensitive: false).firstMatch(info);
          if (idMatch != null) {
            mappedRow['customerId'] = idMatch.group(1);
            info = info.replaceAll(idMatch.group(0)!, '').trim();
          }
        }

        mappedRow['packageInfo'] = info.isEmpty ? null : info;
      }

      mappedRow['transactionDate'] = _normalizeDate(mappedRow['transactionDate']);
      mappedRow['productType'] = _normalizeProductType(mappedRow['productType']);
      mappedRow['paymentStatus'] = _normalizePaymentStatus(mappedRow['paymentStatus']);
      mappedRow['paymentMethod'] = _normalizePaymentMethod(mappedRow['paymentMethod']);

      results.add(mappedRow);
    }
    return results;
  }

  String? _cleanNumeric(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    String cleaned = raw.trim();
    cleaned = cleaned.replaceAll(RegExp(r'[Rp\s\-]'), '');
    if (cleaned.endsWith('.00') || cleaned.endsWith(',00')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    cleaned = cleaned.replaceAll(RegExp(r'[\.,]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[^\d]'), '');
    return cleaned.isEmpty ? null : cleaned;
  }

  String? _normalizeDate(String? raw) {
    if (raw == null) return null;
    String cleaned = raw.trim().toLowerCase();
    if (cleaned.isEmpty) return null;
    if (cleaned.contains(':')) {
      cleaned = cleaned.split(' ')[0];
    }
    final monthNames = ['januari', 'februari', 'maret', 'april', 'mei', 'juni', 'juli', 'agustus', 'september', 'oktober', 'november', 'desember'];
    for (int i = 0; i < monthNames.length; i++) {
      if (cleaned.contains(monthNames[i])) {
        final match = RegExp(r'(\d{1,2})\s+' + monthNames[i] + r'\s+(\d{4})').firstMatch(cleaned);
        if (match != null) {
          return '${match.group(2)}${(i + 1).toString().padLeft(2, '0')}${match.group(1)!.padLeft(2, '0')}';
        }
      }
    }

    // 2. Handle DD/MM/YYYY atau DD-MM-YYYY
    final dmyMatch = RegExp(r'^(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{4})').firstMatch(cleaned);
    if (dmyMatch != null) {
      return '${dmyMatch.group(3)}${dmyMatch.group(2)!.padLeft(2, '0')}${dmyMatch.group(1)!.padLeft(2, '0')}';
    }

    // 3. Handle YYYY-MM-DD atau YYYY/MM/DD
    final ymdMatch = RegExp(r'^(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})').firstMatch(cleaned);
    if (ymdMatch != null) {
      return '${ymdMatch.group(1)}${ymdMatch.group(2)!.padLeft(2, '0')}${ymdMatch.group(3)!.padLeft(2, '0')}';
    }

    return cleaned;
  }

  String? _normalizeProductType(String? raw) {
    if (raw == null) return null;
    final v = raw.toLowerCase();
    if (v.contains('token') || v.contains('ppob_pln_token')) return 'token';
    if (v.contains('listrik') || v.contains('pln')) return 'listrik';
    if (v.contains('pulsa')) return 'pulsa';
    if (v.contains('indihome') || v.contains('internet') || v.contains('ppob_indihome')) return 'indihome';
    if (v.contains('paket') || v.contains('data')) return 'paketData';
    if (v.contains('bpjs') || v.contains('ppob_bpjs')) return 'bpjs';
    if (v.contains('pdam') || v.contains('air')) return 'pdam';
    return 'lainnya';
  }

  String? _normalizePaymentStatus(String? raw) {
    if (raw == null) return null;
    final v = raw.toLowerCase();
    // FIX: Cek status negatif/gagal SEBELUM positif agar "unpaid" tidak terdeteksi sebagai "paid"
    if (v.contains('belum') || v.contains('gagal') || v.contains('failed') ||
        v.contains('pending') || v.contains('unpaid')) {
      return 'belumLunas';
    }
    if (v.contains('lunas') || v.contains('sukses') || v.contains('success') ||
        v.contains('berhasil') || v.contains('paid') || v.contains('ok')) {
      return 'lunas';
    }
    return null;
  }

  String? _normalizePaymentMethod(String? raw) {
    if (raw == null) return null;
    final v = raw.toLowerCase();
    if (v.contains('cash') || v.contains('tunai')) return 'cash';
    if (v.contains('transfer') || v.contains('va') || v.contains('bank')) return 'transfer';
    if (v.contains('qris') || v.contains('qr') || v.contains('scan')) return 'qris';
    if (v.contains('wallet') || v.contains('ewallet') || v.contains('dompet')) return 'eWallet';
    return 'cash';
  }
}