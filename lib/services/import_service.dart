import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';
import '../config/env.dart';

class ImportService {

  Future<Map<String, dynamic>> analyzeCSV(File file) async {
    try {
      debugPrint('Reading CSV file...');
      
      // Read CSV file
      final input = await file.readAsString();

      List<List<dynamic>> fields;

      if (input.contains(';')) {
        fields = const CsvToListConverter(
          fieldDelimiter: ';',
          eol: '\n',
        ).convert(input);
      } else {
        fields = const CsvToListConverter(
          fieldDelimiter: ',',
          eol: '\n',
        ).convert(input);
      }

      if (fields.isEmpty) {
        throw Exception('File CSV kosong');
      }

      debugPrint('CSV loaded: ${fields.length} rows');

      // Get headers
      final headers = fields[0].map((e) => e.toString()).toList();
      debugPrint('Headers: $headers');

      // Get sample data (first 3 rows)
      final sampleData = fields.length > 4 
          ? fields.sublist(1, 4)
          : fields.sublist(1);

      debugPrint('Calling Gemini AI for analysis...');

      // Use Gemini AI to analyze headers
      final model = GenerativeModel(
        model: 'gemini-3.5-flash-lite',
        apiKey: Env.geminiApiKey,
      );

      final prompt = '''
Analyze these CSV headers and map them to our transaction fields.

CSV Headers: ${headers.join(', ')}

Sample data (first row):
${fields.length > 1 ? fields[1].join(', ') : 'No data'}

Our required fields:
- date: tanggal transaksi (format: DD/MM/YYYY, DD-MM-YYYY, or YYYY-MM-DD)
- productName: nama produk/layanan
- category: kategori produk (Pulsa, Paket Data, Token Listrik, dll) - OPTIONAL
- customerNumber: nomor pelanggan/HP/meter
- customerName: nama pelanggan - OPTIONAL
- nominal: nilai transaksi (harga pokok)
- adminFee: biaya admin - OPTIONAL (default 0 if not found)
- isPaid: status lunas (lunas/belum, true/false, 1/0)

IMPORTANT:
1. Return ONLY the column INDEX (0, 1, 2, etc) for each field
2. Use null for optional fields if not found
3. For adminFee, use null if column not found (we'll default to 0)
4. For category, use null if not found (we'll auto-detect from product name)

Return ONLY a JSON object with this exact format (no explanation):
{
  "date": 0,
  "productName": 1,
  "category": null,
  "customerNumber": 2,
  "customerName": null,
  "nominal": 3,
  "adminFee": 4,
  "isPaid": 5
}
''';

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);

      debugPrint('AI Response received');
      debugPrint('Raw response: ${response.text}');

      // Parse AI response
      final mappingText = response.text ?? '{}';
      
      // Clean the response to extract JSON
      String jsonString;
      final jsonStart = mappingText.indexOf('{');
      final jsonEnd = mappingText.lastIndexOf('}') + 1;
      
      if (jsonStart >= 0 && jsonEnd > jsonStart) {
        jsonString = mappingText.substring(jsonStart, jsonEnd);
      } else {
        // Fallback: auto-detect based on keywords
        debugPrint('AI response invalid, using auto-detection');
        jsonString = _autoDetectMapping(headers);
      }

      debugPrint('Extracted JSON: $jsonString');

      return {
        'headers': headers,
        'data': fields.sublist(1), // Data without headers
        'sampleData': sampleData,
        'mapping': jsonString,
        'totalRows': fields.length - 1,
      };
    } catch (e, stackTrace) {
      debugPrint('Error in analyzeCSV: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  String _autoDetectMapping(List<String> headers) {
    debugPrint('Auto-detecting column mapping...');
    
    final mapping = <String, dynamic>{
      'date': _findColumnIndex(headers, ['tanggal', 'date', 'tgl', 'waktu']),
      'productName': _findColumnIndex(headers, ['produk', 'product', 'nama', 'layanan', 'service']),
      'category': _findColumnIndex(headers, ['kategori', 'category', 'jenis', 'type']),
      'customerNumber': _findColumnIndex(headers, ['nomor', 'no', 'hp', 'telepon', 'phone', 'customer', 'pelanggan', 'meter']),
      'customerName': _findColumnIndex(headers, ['nama', 'name', 'pelanggan', 'customer']),
      'nominal': _findColumnIndex(headers, ['nominal', 'harga', 'price', 'amount', 'jumlah', 'total']),
      'adminFee': _findColumnIndex(headers, ['admin', 'fee', 'biaya', 'charge']),
      'isPaid': _findColumnIndex(headers, ['status', 'lunas', 'paid', 'bayar']),
    };

    debugPrint('Auto-detected mapping: $mapping');
    
    // Convert to JSON string with null handling
    final jsonMap = mapping.map((key, value) => MapEntry(key, value ?? 'null'));
    return '$jsonMap';
  }

  int? _findColumnIndex(List<String> headers, List<String> keywords) {
    for (var i = 0; i < headers.length; i++) {
      final header = headers[i].toLowerCase().trim();
      for (var keyword in keywords) {
        if (header.contains(keyword.toLowerCase())) {
          return i;
        }
      }
    }
    return null;
  }

  Future<Map<String, int>> importTransactions({
    required List<List<dynamic>> data,
    required Map<String, dynamic> mapping, String? dateFormat,
  }) async {
    try {
      debugPrint('Starting import with ${data.length} rows');
      debugPrint('Mapping: $mapping');

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final batch = FirebaseFirestore.instance.batch();
      int successCount = 0;
      int errorCount = 0;
      int batchCount = 0;

      for (var i = 0; i < data.length; i++) {
        try {
          final row = data[i];
          debugPrint('Processing row ${i + 1}: $row');

          // Skip empty rows
          if (row.isEmpty || row.every((cell) => cell == null || cell.toString().trim().isEmpty)) {
            debugPrint('Skipping empty row ${i + 1}');
            continue;
          }

          final productName = _getValueFromMapping(row, mapping['productName']);
          final customerNumber = _getValueFromMapping(row, mapping['customerNumber']);
          final nominal = _parseNumber(_getValueFromMapping(row, mapping['nominal']));

          // Validate required fields
          if (productName == null || productName.toString().trim().isEmpty) {
            debugPrint('Row ${i + 1}: Missing product name');
            errorCount++;
            continue;
          }

          if (customerNumber == null || customerNumber.toString().trim().isEmpty) {
            debugPrint('Row ${i + 1}: Missing customer number');
            errorCount++;
            continue;
          }

          if (nominal <= 0) {
            debugPrint('Row ${i + 1}: Invalid nominal: $nominal');
            errorCount++;
            continue;
          }

          final adminFee = _parseNumber(_getValueFromMapping(row, mapping['adminFee']));
          final category = _detectCategory(
            productName.toString(),
            _getValueFromMapping(row, mapping['category'])?.toString(),
          );

          // Extract data based on mapping
          final transactionData = {
            'userId': user.uid,
            'userEmail': user.email,
            'productName': productName.toString().trim(),
            'category': category,
            'customerNumber': customerNumber.toString().trim(),
            'customerName': _getValueFromMapping(row, mapping['customerName'])?.toString().trim() ?? '',
            'nominal': nominal,
            'adminFee': adminFee,
            'totalAmount': nominal + adminFee,
            'paymentMethod': 'IMPORT',
            'isPaid': _parseBool(_getValueFromMapping(row, mapping['isPaid'])),
            'date': _parseDate(_getValueFromMapping(row, mapping['date'])),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'syncStatus': 'synced',
            'source': 'csv_import',
          };

          debugPrint('Transaction data: $transactionData');

          final docRef = FirebaseFirestore.instance.collection('transactions').doc();
          batch.set(docRef, transactionData);
          
          successCount++;
          batchCount++;

          // Commit batch every 500 operations (Firestore limit)
          if (batchCount >= 500) {
            debugPrint('Committing batch of $batchCount operations...');
            await batch.commit();
            batchCount = 0;
          }

        } catch (e) {
          errorCount++;
          debugPrint('Error importing row ${i + 1}: $e');
        }
      }

      // Commit remaining operations
      if (batchCount > 0) {
        debugPrint('Committing final batch of $batchCount operations...');
        await batch.commit();
      }

      debugPrint('Import complete: $successCount success, $errorCount failed');

      // Log activity
      await FirebaseFirestore.instance.collection('activity_logs').add({
        'userId': user.uid,
        'userEmail': user.email,
        'action': 'import_csv',
        'description': 'Import $successCount transaksi dari CSV ($errorCount gagal)',
        'timestamp': FieldValue.serverTimestamp(),
      });

      return {
        'success': successCount,
        'failed': errorCount,
      };

    } catch (e, stackTrace) {
      debugPrint('Error in importTransactions: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  dynamic _getValueFromMapping(List<dynamic> row, dynamic mapping) {
    if (mapping == null || mapping.toString() == 'null') return null;

    try {
      int index;
      
      if (mapping is int) {
        index = mapping;
      } else if (mapping is String) {
        index = int.parse(mapping);
      } else {
        return null;
      }

      if (index >= 0 && index < row.length) {
        final value = row[index];
        return value;
      }
    } catch (e) {
      debugPrint('Error getting value from mapping: $e');
    }

    return null;
  }

  String _detectCategory(String productName, String? explicitCategory) {
    // If explicit category provided, use it
    if (explicitCategory != null && explicitCategory.trim().isNotEmpty) {
      return explicitCategory.trim();
    }

    // Auto-detect from product name
    final lower = productName.toLowerCase();
    
    if (lower.contains('pulsa')) return 'Pulsa';
    if (lower.contains('paket') || lower.contains('data') || lower.contains('internet')) return 'Paket Data';
    if (lower.contains('token') && lower.contains('listrik')) return 'Token Listrik';
    if (lower.contains('tagihan') && lower.contains('listrik')) return 'Tagihan Listrik';
    if (lower.contains('pln')) return 'Token Listrik';
    if (lower.contains('bpjs')) return 'BPJS';
    if (lower.contains('indihome') || lower.contains('wifi')) return 'Indihome';
    if (lower.contains('pdam') || lower.contains('air')) return 'PDAM';
    if (lower.contains('gopay') || lower.contains('ovo') || lower.contains('dana') || 
        lower.contains('wallet') || lower.contains('e-money')) {
      return 'E-Wallet';
    }
    if (lower.contains('transfer')) return 'Jasa Transfer';

    return 'Pulsa'; // Default
  }

  int _parseNumber(dynamic value) {
    if (value == null) return 0;
    
    try {
      if (value is int) return value;
      if (value is double) return value.toInt();
      
      if (value is String) {
        // Remove all non-digit characters
        final cleaned = value.replaceAll(RegExp(r'[^\d]'), '');
        if (cleaned.isEmpty) return 0;
        return int.parse(cleaned);
      }
    } catch (e) {
      debugPrint('Error parsing number from value: $value, error: $e');
    }
    
    return 0;
  }

  bool _parseBool(dynamic value) {
    if (value == null) return false;
    
    try {
      if (value is bool) return value;
      
      if (value is String) {
        final lower = value.toLowerCase().trim();
        return lower == 'true' || 
              lower == 'lunas' || 
              lower == '1' || 
              lower == 'yes' || 
              lower == 'y' ||
              lower == 'paid';
      }
      
      if (value is int) return value == 1;
    } catch (e) {
      debugPrint('Error parsing bool from value: $value, error: $e');
    }
    
    return false;
  }

  DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    
    try {
      if (value is DateTime) return value;
      
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) return DateTime.now();

        // Try different date formats
        final formats = [
          'dd/MM/yyyy',
          'dd-MM-yyyy',
          'yyyy-MM-dd',
          'dd/MM/yyyy HH:mm',
          'dd-MM-yyyy HH:mm',
          'yyyy-MM-dd HH:mm',
          'dd/MM/yyyy HH:mm:ss',
          'dd-MM-yyyy HH:mm:ss',
          'yyyy-MM-dd HH:mm:ss',
        ];

        for (var format in formats) {
          try {
            final parsed = DateFormat(format).parse(trimmed);
            debugPrint('Date parsed successfully: $trimmed -> $parsed using format: $format');
            return parsed;
          } catch (_) {
            // Try next format
          }
        }

        // Try ISO 8601
        try {
          return DateTime.parse(trimmed);
        } catch (_) {}

        debugPrint('Could not parse date: $trimmed, using current date');
      }
    } catch (e) {
      debugPrint('Error parsing date from value: $value, error: $e');
    }
    
    return DateTime.now();
  }
}