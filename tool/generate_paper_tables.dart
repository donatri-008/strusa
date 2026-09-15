// tool/generate_paper_tables.dart
//
// Jalankan: GEMINI_API_KEY=xxx dart run tool/generate_paper_tables.dart
// (copy file ini ke tool/ di root project strusa dulu, lalu `flutter pub get`
//  supaya dependency `excel` yang sudah ada di pubspec.yaml ter-resolve)
//
// Hasil akhir: 3 FILE XLSX (bukan markdown lagi), masing-masing satu tabel:
//   paper_table1_summary.xlsx            — Avg F1 (Real) vs Avg F1 (Edge) vs Avg Exec Time
//   paper_table2_perfield_realdata.xlsx  — Per-field F1 di data riil (rata2 4 dataset xlsx)
//   paper_table3_edgecases.xlsx          — F1 di edge-case kritis + homonim skema
//
// ignore_for_file: avoid_print
import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:strusa/models/ground_truth_mapping.dart';
import 'package:strusa/models/real_data_mapping.dart';
import 'package:strusa/services/ai_gemini_service.dart';
import 'package:strusa/services/rule_based_mapper_service.dart';
import 'package:strusa/services/mapping_evaluator_service.dart';
import 'package:strusa/models/evaluation_result.dart';

enum Mapper { ruleBased, gemini }

final evaluator = MappingEvaluatorService();

/// Align predicted rows to ground truth by transactionNumber (real data has
/// non-1:1 row counts sometimes; edge case too, just to be safe).
List<Map<String, String?>> _alignByKey(
  List<Map<String, String?>> groundTruth,
  List<Map<String, String?>> predicted,
) {
  final byKey = {for (final r in predicted) r['transactionNumber']: r};
  return groundTruth
      .map((gt) => byKey[gt['transactionNumber']] ?? <String, String?>{})
      .toList();
}

class RunOutcome {
  final MappingEvaluationReport report;
  final int elapsedMs;
  RunOutcome(this.report, this.elapsedMs);
}

Future<List<Map<String, String?>>> _predict(
    GroundTruthDataset ds, Mapper m, String apiKey) {
  final file = File(ds.dataFilePath);
  return switch (m) {
    Mapper.ruleBased => RuleBasedMapperService().mapCsvToFieldMaps(file),
    Mapper.gemini => AIGeminiService(apiKey: apiKey).mapCsvToFieldMaps(file),
  };
}

Future<RunOutcome> runOne(GroundTruthDataset ds, Mapper m, String apiKey) async {
  final sw = Stopwatch()..start();
  final predicted = await _predict(ds, m, apiKey);
  sw.stop();
  final aligned = _alignByKey(ds.toFieldMaps(), predicted);
  final report = evaluator.evaluate(
    label: '${m.name} - ${ds.id}',
    groundTruth: ds.toFieldMaps(),
    predicted: aligned,
    elapsed: sw.elapsed,
  );
  return RunOutcome(report, sw.elapsedMilliseconds);
}

double _avg(Iterable<double> xs) =>
    xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

// ── Excel helpers ───────────────────────────────────────────────────────────

/// Buat workbook baru dengan satu sheet bernama [sheetName], hapus sheet
/// default "Sheet1" yang otomatis dibuat oleh package `excel`.
Excel _newWorkbook(String sheetName) {
  final excel = Excel.createExcel();
  excel.rename(excel.getDefaultSheet()!, sheetName);
  return excel;
}

void _writeHeaderRow(Sheet sheet, List<String> headers) {
  sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
  // Bold header row
  for (var col = 0; col < headers.length; col++) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
    cell.cellStyle = CellStyle(bold: true);
  }
}

void _writeDataRow(Sheet sheet, List<dynamic> values) {
  sheet.appendRow(values.map((v) {
    if (v is num) return DoubleCellValue(v.toDouble());
    return TextCellValue(v.toString());
  }).toList());
}

Future<void> _saveWorkbook(Excel excel, String fileName) async {
  final bytes = excel.encode();
  if (bytes == null) throw Exception('Gagal encode $fileName');
  final file = File(fileName);
  await file.writeAsBytes(bytes, flush: true);
  print('Saved -> ${file.absolute.path}');
}

Future<void> main() async {
  final apiKey = Platform.environment['GEMINI_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    stderr.writeln('GEMINI_API_KEY belum di-set.');
    exit(1);
  }

  // ── Run semua dataset x semua mapper ──────────────────────────────────
  final Map<Mapper, List<RunOutcome>> realRuns = {
    Mapper.ruleBased: [],
    Mapper.gemini: [],
  };
  final Map<Mapper, List<RunOutcome>> edgeRuns = {
    Mapper.ruleBased: [],
    Mapper.gemini: [],
  };

  for (final ds in allRealDataDatasets) {
    for (final m in Mapper.values) {
      print('Running ${ds.id} (${m.name})...');
      realRuns[m]!.add(await runOne(ds, m, apiKey));
    }
  }
  for (final ds in allEdgeCaseDatasets) {
    for (final m in Mapper.values) {
      print('Running ${ds.id} (${m.name})...');
      edgeRuns[m]!.add(await runOne(ds, m, apiKey));
    }
  }

  // ── TABLE I — paper_table1_summary.xlsx ────────────────────────────────
  {
    final excel = _newWorkbook('Table I - Summary');
    final sheet = excel['Table I - Summary'];
    _writeHeaderRow(sheet, [
      'Method',
      'F1-Score (Real Data)',
      'F1-Score (Edge-Case)',
      'Avg. Execution Time (ms)',
    ]);
    for (final m in Mapper.values) {
      final realF1 = _avg(realRuns[m]!.map((r) => r.report.microF1));
      final edgeF1 = _avg(edgeRuns[m]!.map((r) => r.report.microF1));
      final allMs = [...realRuns[m]!, ...edgeRuns[m]!]
          .map((r) => r.elapsedMs.toDouble());
      final label = m == Mapper.ruleBased ? 'Rule-Based' : 'Generative LLM (Gemini)';
      _writeDataRow(sheet, [
        label,
        double.parse((realF1 * 100).toStringAsFixed(1)),
        double.parse((edgeF1 * 100).toStringAsFixed(1)),
        double.parse(_avg(allMs).toStringAsFixed(0)),
      ]);
    }
    await _saveWorkbook(excel, 'paper_table1_summary.xlsx');
  }

  // ── TABLE II — paper_table2_perfield_realdata.xlsx ─────────────────────
  {
    final excel = _newWorkbook('Table II - Per-Field F1');
    final sheet = excel['Table II - Per-Field F1'];
    _writeHeaderRow(sheet, [
      'Target Field',
      'Rule-Based F1 (%)',
      'Generative LLM F1 (%)',
      'Note',
    ]);
    for (final field in kTargetSchemaFields) {
      double fieldF1(Mapper m) => _avg(realRuns[m]!.map((r) {
            final fr = r.report.fieldResults.where((f) => f.field == field);
            return fr.isEmpty ? 0.0 : fr.first.f1;
          }));
      final rb = fieldF1(Mapper.ruleBased);
      final gm = fieldF1(Mapper.gemini);
      final String note;
      if (rb >= 0.999 && gm >= 0.999) {
        note = 'Both perfect';
      } else if (gm > rb + 0.01) {
        note = 'LLM superior in normalization, est.';
      } else if (rb > gm + 0.01) {
        note = 'Rule-based superior, est.';
      } else {
        note = 'Comparable';
      }
      _writeDataRow(sheet, [
        field,
        double.parse((rb * 100).toStringAsFixed(1)),
        double.parse((gm * 100).toStringAsFixed(1)),
        note,
      ]);
    }
    await _saveWorkbook(excel, 'paper_table2_perfield_realdata.xlsx');
  }

  // ── TABLE III — paper_table3_edgecases.xlsx ────────────────────────────
  {
    final excel = _newWorkbook('Table III - Edge Cases');
    final sheet = excel['Table III - Edge Cases'];
    _writeHeaderRow(sheet, [
      'Scenario',
      'Rule-Based F1 (%)',
      'Generative LLM F1 (%)',
      'Analysis',
    ]);

    final scenarios = <String, String>{
      'ec04_currency_formatting':
          'Currency Formatting (Rp / thousand-sep / decimal comma)',
      'ec05_non_standard_status': 'Non-Standard Status Vocabulary',
      'ec06_duplicate_headers': 'Duplicate / Ambiguous Headers',
      'ec08_merged_fields':
          'Merged Composite Fields (name+phone, product+kWh)',
      'ec09_platform_schema_variation':
          'Cross-Platform Schema Variation (EN/abbrev headers)',
    };

    RunOutcome? findRun(List<RunOutcome> list, String id) {
      final matches = list.where((r) => r.report.label.endsWith(id));
      return matches.isEmpty ? null : matches.first;
    }

    scenarios.forEach((id, label) {
      final rbRun = findRun(edgeRuns[Mapper.ruleBased]!, id);
      final gmRun = findRun(edgeRuns[Mapper.gemini]!, id);
      final rbF1 = rbRun?.report.microF1 ?? 0.0;
      final gmF1 = gmRun?.report.microF1 ?? 0.0;
      final String analysis;
      if (gmF1 > rbF1 + 0.02) {
        analysis = 'LLM handles semantic/format variation rule-based patterns miss.';
      } else if (rbF1 > gmF1 + 0.02) {
        analysis = 'Rule-based regex sufficient; LLM adds no gain here.';
      } else {
        analysis = 'Both approaches handle this case equivalently.';
      }
      _writeDataRow(sheet, [
        label,
        double.parse((rbF1 * 100).toStringAsFixed(1)),
        double.parse((gmF1 * 100).toStringAsFixed(1)),
        analysis,
      ]);
    });

    // Bonus row: schema homonymy on real data ('amount' field, Nominal=text
    // vs Harga=numeric) — the paper's core novelty case, measured across the
    // 4 real datasets rather than a single edge-case fixture.
    double amountF1(Mapper m) => _avg(realRuns[m]!.map((r) {
          final fr = r.report.fieldResults.where((f) => f.field == 'amount');
          return fr.isEmpty ? 0.0 : fr.first.f1;
        }));
    final rbAmt = amountF1(Mapper.ruleBased);
    final gmAmt = amountF1(Mapper.gemini);
    final homonymAnalysis = gmAmt > rbAmt + 0.02
        ? 'LLM correctly infers "amount" is in Harga, not the homonymous Nominal column; rule-based mis-extracts free-text package descriptions.'
        : 'Rule-based homonym-priority pattern (Harga-before-Nominal) closes most of the gap on this fixture set.';
    _writeDataRow(sheet, [
      'Schema Homonymy (real data: "Nominal"=text desc vs "Harga"=numeric amount)',
      double.parse((rbAmt * 100).toStringAsFixed(1)),
      double.parse((gmAmt * 100).toStringAsFixed(1)),
      homonymAnalysis,
    ]);

    await _saveWorkbook(excel, 'paper_table3_edgecases.xlsx');
  }

  print('\nSelesai. 3 file xlsx sudah dibuat di root project:');
  print('  - paper_table1_summary.xlsx');
  print('  - paper_table2_perfield_realdata.xlsx');
  print('  - paper_table3_edgecases.xlsx');
}