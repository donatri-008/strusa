// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:strusa/models/real_data_mapping.dart';
import 'package:strusa/services/ai_gemini_service.dart';
import 'package:strusa/services/rule_based_mapper_service.dart';
import 'package:strusa/services/mapping_evaluator_service.dart';

void main() {
  final evaluator = MappingEvaluatorService();

  for (final dataset in allRealDataDatasets) {
    test('${dataset.id} (gemini)', () async {
      final apiKey = Platform.environment['GEMINI_API_KEY'] ?? '';
      if (apiKey.isEmpty) {
        fail('GEMINI_API_KEY kosong. Set env var dulu sebelum run.');
      }
      final predicted = await AIGeminiService(apiKey: apiKey)
          .mapCsvToFieldMaps(File(dataset.csvFilePath));
      final report = evaluator.evaluate(
        label: 'Gemini - ${dataset.id}',
        groundTruth: dataset.toFieldMaps(),
        predicted: predicted,
      );
      print(report.toReadableSummary());
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('${dataset.id} (ruleBased)', () async {
      final predicted = await RuleBasedMapperService()
          .mapCsvToFieldMaps(File(dataset.csvFilePath));
      final report = evaluator.evaluate(
        label: 'RuleBased - ${dataset.id}',
        groundTruth: dataset.toFieldMaps(),
        predicted: predicted,
      );
      print(report.toReadableSummary());
    });
  }
}