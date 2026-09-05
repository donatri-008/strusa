/// Model hasil evaluasi akurasi mapping (per field & keseluruhan).
/// Dipakai untuk RM2 (akurasi Gemini) & RM3 (Gemini vs rule-based).
library;

class FieldEvaluationResult {
  final String field;
  final int tp; // Prediksi benar, sesuai ground truth
  final int fp; // Prediksi ada tapi salah / GT kosong tapi diprediksi ada
  final int fn; // GT ada tapi tidak terprediksi / prediksi salah

  FieldEvaluationResult({
    required this.field,
    required this.tp,
    required this.fp,
    required this.fn,
  });

  double get precision => (tp + fp) == 0 ? 0 : tp / (tp + fp);
  double get recall => (tp + fn) == 0 ? 0 : tp / (tp + fn);
  double get f1 {
    final p = precision;
    final r = recall;
    if (p + r == 0) return 0;
    return 2 * p * r / (p + r);
  }

  Map<String, dynamic> toMap() => {
        'field': field,
        'tp': tp,
        'fp': fp,
        'fn': fn,
        'precision': precision,
        'recall': recall,
        'f1': f1,
      };

  @override
  String toString() =>
      '$field -> P: ${precision.toStringAsFixed(3)} R: ${recall.toStringAsFixed(3)} F1: ${f1.toStringAsFixed(3)} (TP=$tp FP=$fp FN=$fn)';
}

class MappingEvaluationReport {
  final String label; // ex: "Gemini - Prompt v1", "Rule-Based Baseline"
  final int totalRows;
  final List<FieldEvaluationResult> fieldResults;
  final Duration? elapsed; // waktu eksekusi mapping (untuk RM4)

  MappingEvaluationReport({
    required this.label,
    required this.totalRows,
    required this.fieldResults,
    this.elapsed,
  });

  /// Macro-average: rata-rata precision/recall/F1 antar field (bobot sama tiap field)
  double get macroPrecision => _avg(fieldResults.map((f) => f.precision));
  double get macroRecall => _avg(fieldResults.map((f) => f.recall));
  double get macroF1 => _avg(fieldResults.map((f) => f.f1));

  /// Micro-average: dihitung dari total TP/FP/FN semua field (bobot ikut jumlah data)
  double get microPrecision {
    final tp = fieldResults.fold<int>(0, (a, b) => a + b.tp);
    final fp = fieldResults.fold<int>(0, (a, b) => a + b.fp);
    return (tp + fp) == 0 ? 0 : tp / (tp + fp);
  }

  double get microRecall {
    final tp = fieldResults.fold<int>(0, (a, b) => a + b.tp);
    final fn = fieldResults.fold<int>(0, (a, b) => a + b.fn);
    return (tp + fn) == 0 ? 0 : tp / (tp + fn);
  }

  double get microF1 {
    final p = microPrecision;
    final r = microRecall;
    if (p + r == 0) return 0;
    return 2 * p * r / (p + r);
  }

  double _avg(Iterable<double> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  Map<String, dynamic> toMap() => {
        'label': label,
        'totalRows': totalRows,
        'elapsedMs': elapsed?.inMilliseconds,
        'macroPrecision': macroPrecision,
        'macroRecall': macroRecall,
        'macroF1': macroF1,
        'microPrecision': microPrecision,
        'microRecall': microRecall,
        'microF1': microF1,
        'fields': fieldResults.map((f) => f.toMap()).toList(),
      };

  String toReadableSummary() {
    final buffer = StringBuffer();
    buffer.writeln('=== $label ===');
    buffer.writeln('Total baris: $totalRows');
    if (elapsed != null) {
      buffer.writeln('Waktu eksekusi: ${elapsed!.inMilliseconds} ms');
    }
    buffer.writeln(
        'Macro  -> P: ${macroPrecision.toStringAsFixed(3)} R: ${macroRecall.toStringAsFixed(3)} F1: ${macroF1.toStringAsFixed(3)}');
    buffer.writeln(
        'Micro  -> P: ${microPrecision.toStringAsFixed(3)} R: ${microRecall.toStringAsFixed(3)} F1: ${microF1.toStringAsFixed(3)}');
    buffer.writeln('--- Per Field ---');
    for (final f in fieldResults) {
      buffer.writeln(f.toString());
    }
    return buffer.toString();
  }
}