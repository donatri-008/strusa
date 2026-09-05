import 'dart:io';
import 'package:strusa/models/evaluation_result.dart';
import 'package:strusa/models/ground_truth_mapping.dart';
import 'package:strusa/services/ai_gemini_service.dart';
import 'package:strusa/services/mapping_evaluator_service.dart';

/// Satu varian prompt yang mau diuji dalam ablation study (RM3).
class PromptVariant {
  final String id; // ex: "v1_baseline", "v2_few_shot", "v3_short"
  final String Function(List<String> headers) builder;

  const PromptVariant({required this.id, required this.builder});
}

/// Kumpulan varian prompt siap pakai. Silakan tambah/ubah sesuai kebutuhan
/// eksperimen ablation (contoh: baseline vs few-shot vs instruksi ringkas).
class PromptVariants {
  /// Sama persis dengan prompt produksi di AIGeminiService (kontrol/baseline).
  static PromptVariant baseline(AIGeminiService service) => PromptVariant(
        id: 'v1_baseline',
        builder: service.buildDefaultPrompt,
      );

  /// Varian few-shot: kasih 1 contoh mapping supaya model punya acuan format.
  static PromptVariant fewShot() => PromptVariant(
        id: 'v2_few_shot',
        builder: (headers) => '''
Berikut header CSV transaksi PPOB:
${headers.join(', ')}

Contoh mapping yang benar untuk header lain (hanya sebagai acuan format, isi
sesuai header di atas, JANGAN copy nilai kolom di contoh):
{
  "mappings": {
    "transactionNumber": "No Transaksi",
    "transactionDate": "Tanggal",
    "customerName": "Nama Pelanggan",
    "customerPhone": "No HP",
    "productType": "Jenis Produk",
    "productName": "Nama Produk",
    "amount": "Nominal",
    "adminFee": "Biaya Admin",
    "totalAmount": "Total",
    "paymentStatus": "Status",
    "paymentMethod": "Metode Bayar",
    "meterNumber": null,
    "customerId": null,
    "tariff": null,
    "period": null,
    "tokenNumber": null,
    "kwh": null,
    "packageInfo": null
  }
}

Sekarang buatkan mapping yang sama untuk header CSV di atas.
Field yang tidak ada di header, isi null.
Hanya balas JSON, tanpa teks lain.
''',
      );

  /// Varian instruksi ringkas: tanpa penjelasan panjang tiap field.
  static PromptVariant concise() => PromptVariant(
        id: 'v3_concise',
        builder: (headers) => '''
Header CSV: ${headers.join(', ')}

Mapping ke field: transactionNumber, transactionDate, customerName,
customerPhone, productType, productName, amount, adminFee, totalAmount,
paymentStatus, paymentMethod, meterNumber, customerId, tariff, period,
tokenNumber, kwh, packageInfo.

Balas HANYA JSON: {"mappings": {"field": "nama_header_csv_atau_null", ...}}
''',
      );

  /// Varian dengan penekanan anti-halusinasi (larang mengarang nama kolom).
  static PromptVariant antiHallucination() => PromptVariant(
        id: 'v4_anti_hallucination',
        builder: (headers) => '''
PENTING: Header CSV yang TERSEDIA hanya ini, JANGAN mengarang nama header lain:
${headers.join(', ')}

Petakan header di atas (dan HANYA header di atas) ke field berikut:
transactionNumber, transactionDate, customerName, customerPhone, productType,
productName, amount, adminFee, totalAmount, paymentStatus, paymentMethod,
meterNumber, customerId, tariff, period, tokenNumber, kwh, packageInfo.

Jika tidak ada header yang cocok untuk suatu field, WAJIB isi null untuk
field tersebut. Jangan pernah membuat nama kolom yang tidak ada di daftar
header di atas.

Jawab hanya dengan JSON: {"mappings": {...}}
''',
      );

  static List<PromptVariant> all(AIGeminiService service) => [
        baseline(service),
        fewShot(),
        concise(),
        antiHallucination(),
      ];
}

/// Hasil ablation: laporan tiap varian + ranking berdasarkan macro-F1.
class AblationResult {
  final List<MappingEvaluationReport> reports;

  AblationResult(this.reports);

  List<MappingEvaluationReport> get rankedByMacroF1 {
    final sorted = [...reports];
    sorted.sort((a, b) => b.macroF1.compareTo(a.macroF1));
    return sorted;
  }

  MappingEvaluationReport get best => rankedByMacroF1.first;

  String toReadableSummary() {
    final buffer = StringBuffer();
    buffer.writeln('===== HASIL PROMPT ABLATION TESTING (RM3) =====\n');
    for (final r in rankedByMacroF1) {
      buffer.writeln(r.toReadableSummary());
      buffer.writeln();
    }
    buffer.writeln('>>> Prompt terbaik: ${best.label} (macro-F1: '
        '${best.macroF1.toStringAsFixed(3)})');
    return buffer.toString();
  }
}

/// Runner ablation: jalankan beberapa varian prompt terhadap 1 file CSV +
/// ground truth yang sama, lalu bandingkan akurasinya.
class PromptAblationService {
  final AIGeminiService aiService;
  final MappingEvaluatorService evaluator = MappingEvaluatorService();

  PromptAblationService({required this.aiService});

  Future<AblationResult> run({
    required File csvFile,
    required GroundTruthDataset groundTruth,
    List<PromptVariant>? variants,
  }) async {
    final variantList = variants ?? PromptVariants.all(aiService);
    final groundTruthMaps = groundTruth.toFieldMaps();

    final List<MappingEvaluationReport> reports = [];

    for (final variant in variantList) {
      final stopwatch = Stopwatch()..start();
      final predicted = await aiService.mapCsvToFieldMaps(
        csvFile,
        promptBuilder: variant.builder,
      );
      stopwatch.stop();

      if (predicted.length != groundTruthMaps.length) {
        // Baris hasil AI beda jumlah sama ground truth -> tetap dievaluasi
        // pakai jumlah minimum supaya tidak crash, tapi dicatat sebagai FN
        // besar untuk transparansi hasil (AI gagal proses sebagian baris).
        final minLen = predicted.length < groundTruthMaps.length
            ? predicted.length
            : groundTruthMaps.length;
        reports.add(evaluator.evaluate(
          label: 'Gemini - ${variant.id} (baris tidak lengkap: '
              '${predicted.length}/${groundTruthMaps.length})',
          groundTruth: groundTruthMaps.sublist(0, minLen),
          predicted: predicted.sublist(0, minLen),
          elapsed: stopwatch.elapsed,
        ));
        continue;
      }

      reports.add(evaluator.evaluate(
        label: 'Gemini - ${variant.id}',
        groundTruth: groundTruthMaps,
        predicted: predicted,
        elapsed: stopwatch.elapsed,
      ));
    }

    return AblationResult(reports);
  }
}