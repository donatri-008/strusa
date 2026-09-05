import 'package:strusa/models/evaluation_result.dart';
import 'package:strusa/models/ground_truth_mapping.dart';

/// Kalkulator precision/recall/F1-score per field, bandingkan hasil mapping
/// (Gemini ATAU rule-based) terhadap ground truth manual.
///
/// Dipakai untuk RM2 (akurasi Gemini vs ground truth) dan RM3
/// (Gemini vs baseline rule-based, tinggal ganti `predicted`-nya).
class MappingEvaluatorService {
  /// Field numerik dibandingkan dengan toleransi, bukan exact string match,
  /// supaya beda format "10000" vs "10000.0" vs "Rp10.000" tidak dianggap salah.
  static const List<String> _numericFields = [
    'amount',
    'adminFee',
    'totalAmount',
    'kwh',
  ];

  static const double _numericTolerance = 1.0;

  MappingEvaluationReport evaluate({
    required String label,
    required List<Map<String, String?>> groundTruth,
    required List<Map<String, String?>> predicted,
    List<String>? fields,
    Duration? elapsed,
  }) {
    final evalFields = fields ?? kTargetSchemaFields;

    if (groundTruth.length != predicted.length) {
      throw ArgumentError(
        'Jumlah baris ground truth (${groundTruth.length}) dan predicted '
        '(${predicted.length}) harus sama. Pastikan urutan baris CSV konsisten.',
      );
    }

    final List<FieldEvaluationResult> fieldResults = [];

    for (final field in evalFields) {
      int tp = 0, fp = 0, fn = 0;

      for (int i = 0; i < groundTruth.length; i++) {
        final gtValue = _clean(groundTruth[i][field]);
        final predValue = _clean(predicted[i][field]);

        final gtEmpty = gtValue == null;
        final predEmpty = predValue == null;

        if (gtEmpty && predEmpty) {
          continue; // true negative, tidak relevan untuk P/R
        } else if (!gtEmpty && predEmpty) {
          fn++; // seharusnya ada nilai, tapi tidak terprediksi
        } else if (gtEmpty && !predEmpty) {
          fp++; // seharusnya kosong, tapi diprediksi ada isinya
        } else {
          // keduanya ada isi -> cek cocok atau tidak
          final match = _isMatch(field, gtValue!, predValue!);
          if (match) {
            tp++;
          } else {
            // salah ekstraksi: dihitung gagal recall (nilai benar tidak didapat)
            // sekaligus gagal precision (nilai yang dikeluarkan salah)
            fp++;
            fn++;
          }
        }
      }

      fieldResults.add(FieldEvaluationResult(
        field: field,
        tp: tp,
        fp: fp,
        fn: fn,
      ));
    }

    return MappingEvaluationReport(
      label: label,
      totalRows: groundTruth.length,
      fieldResults: fieldResults,
      elapsed: elapsed,
    );
  }

  String? _clean(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool _isMatch(String field, String gt, String pred) {
    if (_numericFields.contains(field)) {
      final gtNum = _parseNumeric(gt);
      final predNum = _parseNumeric(pred);
      if (gtNum == null || predNum == null) {
        return gt.toLowerCase() == pred.toLowerCase();
      }
      return (gtNum - predNum).abs() <= _numericTolerance;
    }

    // Default: case-insensitive, tanpa spasi berlebih
    final a = gt.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final b = pred.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    return a == b;
  }

  double? _parseNumeric(String value) {
    final cleaned = value
        .replaceAll('Rp', '')
        .replaceAll('.', '')
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'[^0-9.\-]'), '')
        .trim();
    return double.tryParse(cleaned);
  }

  /// Bandingkan dua report (misal Gemini vs Rule-Based) buat RM3, hasilnya
  /// selisih macro-F1 per field supaya kelihatan field mana yang paling
  /// diuntungkan/dirugikan pakai LLM dibanding rule-based.
  Map<String, double> compareF1(
    MappingEvaluationReport a,
    MappingEvaluationReport b,
  ) {
    final Map<String, double> diff = {};
    for (final fa in a.fieldResults) {
      final fb = b.fieldResults.firstWhere(
        (f) => f.field == fa.field,
        orElse: () => FieldEvaluationResult(field: fa.field, tp: 0, fp: 0, fn: 0),
      );
      diff[fa.field] = fa.f1 - fb.f1; // positif = a lebih baik dari b
    }
    return diff;
  }
}