// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:strusa/models/ground_truth_mapping.dart';
import 'package:strusa/services/ai_gemini_service.dart';
import 'package:strusa/services/rule_based_mapper_service.dart';

enum MapperKind { gemini, ruleBased }

class _RunResult {
  final String datasetId;
  final String category;
  final MapperKind mapper;
  final bool threw;
  final String? errorMessage;
  final int rowsCompared;
  final int fieldsExpected;
  final int fieldsPredicted;
  final int fieldsCorrect;

  _RunResult.error({
    required this.datasetId,
    required this.category,
    required this.mapper,
    required String error,
  })  : threw = true,
        errorMessage = error,
        rowsCompared = 0,
        fieldsExpected = 0,
        fieldsPredicted = 0,
        fieldsCorrect = 0;

  _RunResult.success({
    required this.datasetId,
    required this.category,
    required this.mapper,
    required this.rowsCompared,
    required this.fieldsExpected,
    required this.fieldsPredicted,
    required this.fieldsCorrect,
  })  : threw = false,
        errorMessage = null;

  double get precision => fieldsPredicted == 0 ? 0 : fieldsCorrect / fieldsPredicted;
  double get recall => fieldsExpected == 0 ? 0 : fieldsCorrect / fieldsExpected;
  double get f1 {
    if (precision + recall == 0) return 0;
    return 2 * precision * recall / (precision + recall);
  }
}

void main() {
  final mappersToRun = <MapperKind>[MapperKind.gemini, MapperKind.ruleBased];

  // 🆕 Tampung semua hasil test untuk diekspor
  final List<Map<String, dynamic>> exportData = [];

  group('Edge Case Batch Robustness Test', () {
    for (final dataset in allEdgeCaseDatasets) {
      for (final mapper in mappersToRun) {
        test(
          '${dataset.id} (${mapper.name})',
          () async {
            final result = await _runOne(dataset, mapper);

            // 🆕 Simpan hasil ke list export
            exportData.add({
              'datasetId': dataset.id,
              'category': dataset.edgeCaseCategory,
              'mapper': mapper.name,
              'rowsCompared': result.rowsCompared,
              'fieldsExpected': result.fieldsExpected,
              'fieldsPredicted': result.fieldsPredicted,
              'fieldsCorrect': result.fieldsCorrect,
              'precision': double.parse(result.precision.toStringAsFixed(4)),
              'recall': double.parse(result.recall.toStringAsFixed(4)),
              'f1Score': double.parse(result.f1.toStringAsFixed(4)),
              'f1Percentage': '${(result.f1 * 100).toStringAsFixed(1)}%',
              'status': result.threw ? 'ERROR' : 'OK',
              'errorMessage': result.errorMessage,
            });

            if (result.threw) {
              fail('Error pada ${dataset.id} (${mapper.name}): ${result.errorMessage}');
            } else {
              final f1 = (result.f1 * 100).toStringAsFixed(1);
              print('[OK] ${dataset.id} (${mapper.name}) -> F1=$f1% '
                  '(Rows: ${result.rowsCompared}, Correct: ${result.fieldsCorrect}/${result.fieldsExpected})');
            }
          },
          timeout: const Timeout(Duration(minutes: 3)),
        );
      }
    }
  });

  // 🆕 Export ke 3 format setelah semua test selesai
  tearDownAll(() async {
    if (exportData.isEmpty) {
      print('\n⚠️ Tidak ada data untuk diekspor.');
      return;
    }

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;

    // 1. Export ke JSON
    final jsonFile = File('test_results_$timestamp.json');
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(exportData),
    );
    print('\n📄 JSON: ${jsonFile.absolute.path}');

    // 2. Export ke CSV
    final csvFile = File('test_results_$timestamp.csv');
    await csvFile.writeAsString(_generateCsv(exportData));
    print('📊 CSV:  ${csvFile.absolute.path}');

    // 3. Export ke HTML Report
    final htmlFile = File('test_report_$timestamp.html');
    await htmlFile.writeAsString(_generateHtmlReport(exportData, mappersToRun));
    print('🌐 HTML: ${htmlFile.absolute.path}');

    // 4. Cetak ringkasan akhir
    _printSummary(exportData);
  });
}

Future<_RunResult> _runOne(GroundTruthDataset dataset, MapperKind mapper) async {
  try {
    final csvFile = File(dataset.csvFilePath);
    if (!await csvFile.exists()) {
      throw FileSystemException('Fixture CSV not found', dataset.csvFilePath);
    }

    final predictedRows = switch (mapper) {
      MapperKind.gemini => await _runGeminiMapper(csvFile),
      MapperKind.ruleBased => await _runRuleBasedMapper(csvFile),
    };

    return _evaluate(dataset, mapper, predictedRows);
  } catch (e, stackTrace) {
    return _RunResult.error(
      datasetId: dataset.id,
      category: dataset.edgeCaseCategory,
      mapper: mapper,
      error: '$e\n$stackTrace',
    );
  }
}

Future<List<Map<String, String?>>> _runGeminiMapper(File csvFile) async {
  final apiKey = Platform.environment['GEMINI_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    throw StateError('GEMINI_API_KEY kosong.');
  }
  final service = AIGeminiService(apiKey: apiKey);
  return service.mapCsvToFieldMaps(csvFile);
}

Future<List<Map<String, String?>>> _runRuleBasedMapper(File csvFile) async {
  final service = RuleBasedMapperService();
  return service.mapCsvToFieldMaps(csvFile);
}

_RunResult _evaluate(
  GroundTruthDataset dataset,
  MapperKind mapper,
  List<Map<String, String?>> predictedRows,
) {
  final rowsToCompare = dataset.expectedRows.length < predictedRows.length
      ? dataset.expectedRows.length
      : predictedRows.length;

  int fieldsExpected = 0;
  int fieldsPredicted = 0;
  int fieldsCorrect = 0;

  for (var i = 0; i < rowsToCompare; i++) {
    final expected = dataset.expectedRows[i];
    final predicted = predictedRows[i];

    for (final field in kTargetSchemaFields) {
      final expectedValue = _normalize(expected[field]);
      final predictedValue = _normalize(predicted[field]);

      if (expectedValue != null) fieldsExpected++;
      if (predictedValue != null) fieldsPredicted++;

      if (expectedValue == predictedValue) {
        if (expectedValue != null) fieldsCorrect++;
      } else {
        print('  ⚠️ [MISMATCH] Row ${i + 1}, Field "$field":');
        print('     Expected: "$expectedValue"');
        print('     Got:      "$predictedValue"');
      }
    }
  }

  if (dataset.expectedRows.length > predictedRows.length) {
    for (var i = predictedRows.length; i < dataset.expectedRows.length; i++) {
      for (final field in kTargetSchemaFields) {
        if (_normalize(dataset.expectedRows[i][field]) != null) {
          fieldsExpected++;
        }
      }
    }
  }

  return _RunResult.success(
    datasetId: dataset.id,
    category: dataset.edgeCaseCategory,
    mapper: mapper,
    rowsCompared: rowsToCompare,
    fieldsExpected: fieldsExpected,
    fieldsPredicted: fieldsPredicted,
    fieldsCorrect: fieldsCorrect,
  );
}

/// Normalisasi nilai untuk perbandingan yang adil.
String? _normalize(dynamic value) {
  if (value == null) return null;
  String str = value.toString().trim();
  if (str.isEmpty) return null;

  // Normalisasi khusus untuk field numerik
  if (RegExp(r'^[\d\.,\sRp\-]+$').hasMatch(str)) {
    String cleaned = str.replaceAll(RegExp(r'[Rp\s\-]'), '');
    if (cleaned.endsWith('.00') || cleaned.endsWith(',00')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    cleaned = cleaned.replaceAll(RegExp(r'[\.,]'), '');
    if (cleaned.isNotEmpty && RegExp(r'^\d+$').hasMatch(cleaned)) {
      return cleaned;
    }
  }

  return str.toLowerCase();
}

// ============================================================================
// 🆕 FUNGSI EXPORT
// ============================================================================

/// Generate CSV dari data hasil test
String _generateCsv(List<Map<String, dynamic>> data) {
  final buffer = StringBuffer();
  final headers = data.first.keys.toList();

  // Header
  buffer.writeln(headers.map(_escapeCsv).join(','));

  // Rows
  for (final row in data) {
    buffer.writeln(headers.map((h) => _escapeCsv(row[h])).join(','));
  }

  return buffer.toString();
}

/// Escape nilai untuk CSV (handle koma, quote, newline)
String _escapeCsv(dynamic value) {
  if (value == null) return '""';
  final str = value.toString();
  if (str.contains(',') || str.contains('"') || str.contains('\n')) {
    return '"${str.replaceAll('"', '""')}"';
  }
  return str;
}

/// Generate HTML Report yang cantik dan profesional
String _generateHtmlReport(List<Map<String, dynamic>> data, List<MapperKind> mappers) {
  final avgF1 = data.map((e) => (e['f1Score'] as num).toDouble()).reduce((a, b) => a + b) / data.length;
  final totalCorrect = data.fold<int>(0, (sum, e) => sum + (e['fieldsCorrect'] as int));
  final totalExpected = data.fold<int>(0, (sum, e) => sum + (e['fieldsExpected'] as int));
  final perfectCount = data.where((e) => (e['f1Score'] as num) == 1.0).length;
  final errorCount = data.where((e) => e['status'] == 'ERROR').length;

  final rows = data.map((row) {
    final f1 = (row['f1Score'] as num).toDouble() * 100;
    final color = f1 >= 95 ? '#16a34a' : f1 >= 80 ? '#ca8a04' : '#dc2626';
    final bgColor = f1 >= 95 ? '#dcfce7' : f1 >= 80 ? '#fef9c3' : '#fee2e2';
    return '''
    <tr>
      <td><strong>${row['datasetId']}</strong></td>
      <td>${row['category']}</td>
      <td><code>${row['mapper']}</code></td>
      <td class="num">${row['rowsCompared']}</td>
      <td class="num">${row['fieldsCorrect']} / ${row['fieldsExpected']}</td>
      <td class="num">${((row['precision'] as num) * 100).toStringAsFixed(1)}%</td>
      <td class="num">${((row['recall'] as num) * 100).toStringAsFixed(1)}%</td>
      <td class="f1-cell" style="background:$bgColor;color:$color">
        <strong>${f1.toStringAsFixed(1)}%</strong>
      </td>
    </tr>''';
  }).join('\n');

  return '''
<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Edge Case Test Report - Strusa</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #f8fafc;
      color: #1e293b;
      line-height: 1.6;
      padding: 40px 20px;
    }
    .container { max-width: 1200px; margin: 0 auto; }
    header {
      background: linear-gradient(135deg, #1e40af 0%, #3b82f6 100%);
      color: white;
      padding: 40px;
      border-radius: 12px;
      margin-bottom: 30px;
      box-shadow: 0 10px 25px rgba(30, 64, 175, 0.2);
    }
    header h1 { font-size: 2em; margin-bottom: 8px; }
    header p { opacity: 0.9; font-size: 0.95em; }
    .summary-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 20px;
      margin-bottom: 30px;
    }
    .summary-card {
      background: white;
      padding: 24px;
      border-radius: 12px;
      box-shadow: 0 2px 8px rgba(0,0,0,0.06);
      border-left: 4px solid #3b82f6;
    }
    .summary-card.highlight { border-left-color: #16a34a; }
    .summary-card.warning { border-left-color: #ca8a04; }
    .summary-card.danger { border-left-color: #dc2626; }
    .summary-card .label {
      font-size: 0.85em;
      color: #64748b;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 8px;
    }
    .summary-card .value {
      font-size: 2em;
      font-weight: 700;
      color: #0f172a;
    }
    .summary-card .sub {
      font-size: 0.85em;
      color: #64748b;
      margin-top: 4px;
    }
    .section {
      background: white;
      border-radius: 12px;
      padding: 30px;
      box-shadow: 0 2px 8px rgba(0,0,0,0.06);
      margin-bottom: 30px;
    }
    .section h2 {
      font-size: 1.3em;
      margin-bottom: 20px;
      color: #0f172a;
      padding-bottom: 12px;
      border-bottom: 2px solid #e2e8f0;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.9em;
    }
    thead {
      background: #f1f5f9;
    }
    th {
      padding: 12px 14px;
      text-align: left;
      font-weight: 600;
      color: #475569;
      text-transform: uppercase;
      font-size: 0.75em;
      letter-spacing: 0.5px;
    }
    td {
      padding: 14px;
      border-bottom: 1px solid #e2e8f0;
    }
    tr:hover { background: #f8fafc; }
    td.num { text-align: right; font-variant-numeric: tabular-nums; }
    th.num { text-align: right; }
    .f1-cell {
      text-align: center;
      border-radius: 6px;
      font-variant-numeric: tabular-nums;
    }
    code {
      background: #f1f5f9;
      padding: 2px 8px;
      border-radius: 4px;
      font-size: 0.85em;
      color: #475569;
    }
    footer {
      text-align: center;
      color: #64748b;
      font-size: 0.85em;
      margin-top: 40px;
      padding: 20px;
    }
    @media print {
      body { background: white; padding: 0; }
      .section, .summary-card { box-shadow: none; border: 1px solid #e2e8f0; }
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>📊 Edge Case Batch Test Report</h1>
      <p>Strusa CSV Mapper Robustness Evaluation • Generated: ${DateTime.now().toString().split('.').first}</p>
      <p>Mappers Tested: ${mappers.map((m) => m.name).join(', ')}</p>
    </header>

    <div class="summary-grid">
      <div class="summary-card highlight">
        <div class="label">Average F1 Score</div>
        <div class="value">${(avgF1 * 100).toStringAsFixed(2)}%</div>
        <div class="sub">Across ${data.length} datasets</div>
      </div>
      <div class="summary-card">
        <div class="label">Total Fields Correct</div>
        <div class="value">$totalCorrect / $totalExpected</div>
        <div class="sub">${((totalCorrect / totalExpected) * 100).toStringAsFixed(1)}% overall accuracy</div>
      </div>
      <div class="summary-card highlight">
        <div class="label">Perfect Scores (100%)</div>
        <div class="value">$perfectCount / ${data.length}</div>
        <div class="sub">Datasets with F1 = 100%</div>
      </div>
      <div class="summary-card ${errorCount > 0 ? 'danger' : ''}">
        <div class="label">Errors</div>
        <div class="value">$errorCount</div>
        <div class="sub">Failed test runs</div>
      </div>
    </div>

    <div class="section">
      <h2>Detailed Results per Dataset</h2>
      <table>
        <thead>
          <tr>
            <th>Dataset</th>
            <th>Edge Case</th>
            <th>Mapper</th>
            <th class="num">Rows</th>
            <th class="num">Correct</th>
            <th class="num">Precision</th>
            <th class="num">Recall</th>
            <th class="num">F1 Score</th>
          </tr>
        </thead>
        <tbody>
          $rows
        </tbody>
      </table>
    </div>

    <footer>
      <p>Report generated by <strong>Strusa Edge Case Batch Test</strong></p>
      <p>Rule-based baseline vs AI-powered mapping evaluation</p>
    </footer>
  </div>
</body>
</html>''';
}

/// Cetak ringkasan statistik di terminal
void _printSummary(List<Map<String, dynamic>> data) {
  final avgF1 = data.map((e) => (e['f1Score'] as num).toDouble()).reduce((a, b) => a + b) / data.length;
  final perfectCount = data.where((e) => (e['f1Score'] as num) == 1.0).length;
  final errorCount = data.where((e) => e['status'] == 'ERROR').length;

  print('\n${'=' * 70}');
  print('🏆 RINGKASAN HASIL TEST');
  print('=' * 70);
  print('  Total Dataset Diuji  : ${data.length}');
  print('  Rata-rata F1 Score   : ${(avgF1 * 100).toStringAsFixed(2)}%');
  print('  Skor Sempurna (100%) : $perfectCount / ${data.length}');
  print('  Error                : $errorCount');
  print('=' * 70);

  if (perfectCount == data.length && errorCount == 0) {
    print('🎉 SELAMAT! Semua edge case berhasil ditangani dengan sempurna!');
  } else if (avgF1 >= 0.9) {
    print('✨ Hasil sangat baik. Rule-based baseline sudah sangat optimal.');
  } else if (avgF1 >= 0.7) {
    print('👍 Hasil baik. Masih ada ruang perbaikan untuk kasus kompleks.');
  } else {
    print('⚠️  Hasil perlu ditingkatkan. Pertimbangkan pendekatan AI/Gemini.');
  }
  print('=' * 70 + '\n');
}