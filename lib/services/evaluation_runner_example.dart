// Alur lengkap: RM2 (akurasi Gemini) -> RM3 (vs rule-based + ablation)
// -> RM4 (efisiensi waktu, pakai ReconciliationTimer terpisah saat rekap riil).
// ignore_for_file: avoid_print
import 'dart:io';
import 'package:strusa/models/ground_truth_mapping.dart';
import 'package:strusa/services/ai_gemini_service.dart';
import 'package:strusa/services/rule_based_mapper_service.dart';
import 'package:strusa/services/mapping_evaluator_service.dart';
import 'package:strusa/services/prompt_ablation_service.dart';

Future<void> runFullEvaluation({
  required File csvFile,
  required GroundTruthDataset groundTruth,
  required String geminiApiKey,
}) async {
  final aiService = AIGeminiService(apiKey: geminiApiKey);
  final ruleBasedService = RuleBasedMapperService();
  final evaluator = MappingEvaluatorService();
  final groundTruthMaps = groundTruth.toFieldMaps();

  // ---------------------------------------------------------------------
  // RM2: Akurasi Gemini vs Ground Truth (prompt default/produksi)
  // ---------------------------------------------------------------------
  final geminiStopwatch = Stopwatch()..start();
  final geminiPredicted = await aiService.mapCsvToFieldMaps(csvFile);
  geminiStopwatch.stop();

  final geminiReport = evaluator.evaluate(
    label: 'Gemini (RM2 - prompt produksi)',
    groundTruth: groundTruthMaps,
    predicted: geminiPredicted,
    elapsed: geminiStopwatch.elapsed,
  );
  print(geminiReport.toReadableSummary());

  // ---------------------------------------------------------------------
  // RM3a: Gemini vs Rule-Based Baseline
  // ---------------------------------------------------------------------
  final ruleStopwatch = Stopwatch()..start();
  final rulePredicted = await ruleBasedService.mapCsvToFieldMaps(csvFile);
  ruleStopwatch.stop();

  final ruleReport = evaluator.evaluate(
    label: 'Rule-Based Baseline (RM3)',
    groundTruth: groundTruthMaps,
    predicted: rulePredicted,
    elapsed: ruleStopwatch.elapsed,
  );
  print(ruleReport.toReadableSummary());

  final diffPerField = evaluator.compareF1(geminiReport, ruleReport);
  print('\n=== Selisih F1 per field (Gemini - RuleBased), positif = Gemini menang ===');
  diffPerField.forEach((field, diff) {
    print('$field: ${diff.toStringAsFixed(3)}');
  });

  print('\nRingkasan RM3:');
  print('Gemini  macro-F1 : ${geminiReport.macroF1.toStringAsFixed(3)}  '
      '(waktu: ${geminiReport.elapsed?.inMilliseconds} ms)');
  print('RuleBsd macro-F1 : ${ruleReport.macroF1.toStringAsFixed(3)}  '
      '(waktu: ${ruleReport.elapsed?.inMilliseconds} ms)');

  // ---------------------------------------------------------------------
  // RM3b: Prompt Ablation Testing
  // ---------------------------------------------------------------------
  final ablationService = PromptAblationService(aiService: aiService);
  final ablationResult = await ablationService.run(
    csvFile: csvFile,
    groundTruth: groundTruth,
  );
  print(ablationResult.toReadableSummary());

  // Catatan RM4 (efisiensi waktu manual vs otomatis) TIDAK dijalankan di sini
  // karena butuh sesi rekap manual riil oleh peneliti. Gunakan
  // `ReconciliationTimer` langsung di lokasi rekap manual/di halaman import
  // CSV Strusa. Lihat dokumentasi di reconciliation_timer.dart.
}