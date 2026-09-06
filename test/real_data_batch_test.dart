// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:strusa/models/real_data_mapping.dart';
import 'package:strusa/services/ai_gemini_service.dart';
import 'package:strusa/services/rule_based_mapper_service.dart';
import 'package:strusa/services/mapping_evaluator_service.dart';

enum MapperKind { gemini, ruleBased }

void main() {
  final evaluator = MappingEvaluatorService();

  // 🆕 Tampung semua hasil test untuk diekspor
  final List<Map<String, dynamic>> exportData = [];
  final mappersToRun = <MapperKind>[MapperKind.gemini, MapperKind.ruleBased];

  for (final dataset in allRealDataDatasets) {
    test('${dataset.id} (gemini)', () async {
      final apiKey = Platform.environment['GEMINI_API_KEY'] ?? '';
      if (apiKey.isEmpty) {
        fail('GEMINI_API_KEY kosong. Set env var dulu sebelum run.');
      }

      final stopwatch = Stopwatch()..start();
      List<Map<String, String?>> predicted;
      try {
        predicted = await AIGeminiService(apiKey: apiKey)
            .mapCsvToFieldMaps(File(dataset.csvFilePath));
      } catch (e, st) {
        stopwatch.stop();
        exportData.add({
          'datasetId': dataset.id,
          'category': dataset.edgeCaseCategory,
          'mapper': 'gemini',
          'rowsCompared': 0,
          'fieldsExpected': 0,
          'fieldsPredicted': 0,
          'fieldsCorrect': 0,
          'precision': 0.0,
          'recall': 0.0,
          'f1Score': 0.0,
          'f1Percentage': '0.0%',
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'status': 'ERROR',
          'errorMessage': '$e\n$st',
        });
        fail('Error pada ${dataset.id} (gemini): $e');
      }
      stopwatch.stop();

      final report = evaluator.evaluate(
        label: 'Gemini - ${dataset.id}',
        groundTruth: dataset.toFieldMaps(),
        predicted: predicted,
        elapsed: stopwatch.elapsed,
      );

      exportData.add({
        'datasetId': dataset.id,
        'category': dataset.edgeCaseCategory,
        'mapper': 'gemini',
        'rowsCompared': report.totalRows,
        'fieldsExpected': report.fieldResults.fold<int>(
            0, (s, f) => s + f.tp + f.fn),
        'fieldsPredicted': report.fieldResults.fold<int>(
            0, (s, f) => s + f.tp + f.fp),
        'fieldsCorrect':
            report.fieldResults.fold<int>(0, (s, f) => s + f.tp),
        'precision': double.parse(report.microPrecision.toStringAsFixed(4)),
        'recall': double.parse(report.microRecall.toStringAsFixed(4)),
        'f1Score': double.parse(report.microF1.toStringAsFixed(4)),
        'f1Percentage': '${(report.microF1 * 100).toStringAsFixed(1)}%',
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'status': 'OK',
        'errorMessage': null,
      });

      print(report.toReadableSummary());
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('${dataset.id} (ruleBased)', () async {
      final stopwatch = Stopwatch()..start();
      final predicted = await RuleBasedMapperService()
          .mapCsvToFieldMaps(File(dataset.csvFilePath));
      stopwatch.stop();

      final report = evaluator.evaluate(
        label: 'RuleBased - ${dataset.id}',
        groundTruth: dataset.toFieldMaps(),
        predicted: predicted,
        elapsed: stopwatch.elapsed,
      );

      exportData.add({
        'datasetId': dataset.id,
        'category': dataset.edgeCaseCategory,
        'mapper': 'ruleBased',
        'rowsCompared': report.totalRows,
        'fieldsExpected': report.fieldResults.fold<int>(
            0, (s, f) => s + f.tp + f.fn),
        'fieldsPredicted': report.fieldResults.fold<int>(
            0, (s, f) => s + f.tp + f.fp),
        'fieldsCorrect':
            report.fieldResults.fold<int>(0, (s, f) => s + f.tp),
        'precision': double.parse(report.microPrecision.toStringAsFixed(4)),
        'recall': double.parse(report.microRecall.toStringAsFixed(4)),
        'f1Score': double.parse(report.microF1.toStringAsFixed(4)),
        'f1Percentage': '${(report.microF1 * 100).toStringAsFixed(1)}%',
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'status': 'OK',
        'errorMessage': null,
      });

      print(report.toReadableSummary());
    });
  }

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
    final jsonFile = File('real_data_results_$timestamp.json');
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(exportData),
    );
    print('\n📄 JSON: ${jsonFile.absolute.path}');

    // 2. Export ke CSV
    final csvFile = File('real_data_results_$timestamp.csv');
    await csvFile.writeAsString(_generateCsv(exportData));
    print('📊 CSV:  ${csvFile.absolute.path}');

    // 3. Export ke HTML Report
    final htmlFile = File('real_data_report_$timestamp.html');
    await htmlFile.writeAsString(_generateHtmlReport(exportData, mappersToRun));
    print('🌐 HTML: ${htmlFile.absolute.path}');

    // 4. Cetak ringkasan akhir
    _printSummary(exportData);
  });
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
String _generateHtmlReport(
    List<Map<String, dynamic>> data, List<MapperKind> mappers) {
  final avgF1 = data.map((e) => (e['f1Score'] as num).toDouble()).reduce((a, b) => a + b) /
      data.length;
  final totalCorrect =
      data.fold<int>(0, (sum, e) => sum + (e['fieldsCorrect'] as int));
  final totalExpected =
      data.fold<int>(0, (sum, e) => sum + (e['fieldsExpected'] as int));
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
      <td class="num">${row['elapsedMs']} ms</td>
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
  <title>Real Data Test Report - Strusa</title>
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
      <h1>📊 Real Data Batch Test Report</h1>
      <p>Strusa CSV Mapper Evaluation (Data Riil OrderKuota &amp; AgenPulsa) • Generated: ${DateTime.now().toString().split('.').first}</p>
      <p>Mappers Tested: ${mappers.map((m) => m.name).join(', ')}</p>
    </header>

    <div class="summary-grid">
      <div class="summary-card highlight">
        <div class="label">Average F1 Score</div>
        <div class="value">${(avgF1 * 100).toStringAsFixed(2)}%</div>
        <div class="sub">Across ${data.length} runs</div>
      </div>
      <div class="summary-card">
        <div class="label">Total Fields Correct</div>
        <div class="value">$totalCorrect / $totalExpected</div>
        <div class="sub">${totalExpected == 0 ? '0.0' : ((totalCorrect / totalExpected) * 100).toStringAsFixed(1)}% overall accuracy</div>
      </div>
      <div class="summary-card highlight">
        <div class="label">Perfect Scores (100%)</div>
        <div class="value">$perfectCount / ${data.length}</div>
        <div class="sub">Runs with F1 = 100%</div>
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
            <th>Platform/Kategori</th>
            <th>Mapper</th>
            <th class="num">Rows</th>
            <th class="num">Correct</th>
            <th class="num">Precision</th>
            <th class="num">Recall</th>
            <th class="num">Waktu</th>
            <th class="num">F1 Score</th>
          </tr>
        </thead>
        <tbody>
          $rows
        </tbody>
      </table>
    </div>

    <footer>
      <p>Report generated by <strong>Strusa Real Data Batch Test</strong></p>
      <p>Rule-based baseline vs Gemini AI-powered mapping evaluation — data riil UMKM 3D Store</p>
    </footer>
  </div>
</body>
</html>''';
}

/// Cetak ringkasan statistik di terminal
void _printSummary(List<Map<String, dynamic>> data) {
  final avgF1 = data.map((e) => (e['f1Score'] as num).toDouble()).reduce((a, b) => a + b) /
      data.length;
  final perfectCount = data.where((e) => (e['f1Score'] as num) == 1.0).length;
  final errorCount = data.where((e) => e['status'] == 'ERROR').length;

  print('\n${'=' * 70}');
  print('🏆 RINGKASAN HASIL TEST (DATA RIIL)');
  print('=' * 70);
  print('  Total Run Diuji      : ${data.length}');
  print('  Rata-rata F1 Score   : ${(avgF1 * 100).toStringAsFixed(2)}%');
  print('  Skor Sempurna (100%) : $perfectCount / ${data.length}');
  print('  Error                : $errorCount');
  print('=' * 70);

  if (perfectCount == data.length && errorCount == 0) {
    print('🎉 SELAMAT! Semua data riil berhasil dipetakan dengan sempurna!');
  } else if (avgF1 >= 0.9) {
    print('✨ Hasil sangat baik pada data riil OrderKuota/AgenPulsa.');
  } else if (avgF1 >= 0.7) {
    print('👍 Hasil baik. Masih ada ruang perbaikan untuk kasus kompleks.');
  } else {
    print('⚠️  Hasil perlu ditingkatkan pada data riil ini.');
  }
  print('=' * 70 + '\n');
}