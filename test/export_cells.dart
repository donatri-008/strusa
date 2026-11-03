import 'dart:convert';
import 'dart:io';

typedef CellMatcher = bool Function(String field, String gt, String pred);

String? _c(String? v) {
  final t = v?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

String _q(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';

class CellExporter {
  final String runId = Platform.environment['RUN_ID'] ?? 'run1';
  final String gtVariant = Platform.environment['GT_VARIANT'] ?? 'base';
  final List<String> _cells = [];
  final List<String> _latency = [];
  final List<Map<String, dynamic>> _mappings = [];

  /// outcome: tp | fp | fn | fpfn | tn
  void addCells({
    required String suite,
    required String datasetId,
    required String category,
    required String mapper,
    required List<Map<String, String?>> gt,
    required List<Map<String, String?>> pred,
    required List<String> fields,
    required CellMatcher match,
  }) {
    for (var i = 0; i < gt.length; i++) {
      final p = i < pred.length ? pred[i] : <String, String?>{};
      for (final f in fields) {
        final g = _c(gt[i][f]);
        final v = _c(p[f]);
        String o;
        if (g == null && v == null) {
          o = 'tn';
        } else if (g != null && v == null) {
          o = 'fn';
        } else if (g == null && v != null) {
          o = 'fp';
        } else {
          o = match(f, g!, v!) ? 'tp' : 'fpfn';
        }
        _cells.add([gtVariant, runId, suite, datasetId, category, mapper, i, f, o, g, v]
            .map((e) => _q('$e'.replaceAll('null', '')))
            .join(','));
      }
    }
  }

  void addLatency(String suite, String datasetId, String mapper, int ms) =>
      _latency.add('$gtVariant,$runId,$suite,$datasetId,$mapper,$ms');

  void addMapping(String datasetId, List<String> headers,
          Map<String, dynamic>? mappings, int ms) =>
      _mappings.add({
        'datasetId': datasetId,
        'headers': headers,
        'mappings': mappings,
        'elapsedMs': ms,
      });

  Future<void> flush() async {
    Directory('out').createSync();
    final tag = '${gtVariant}_$runId';
    final suffix = DateTime.now().millisecondsSinceEpoch;
    await File('out/cells_${tag}_$suffix.csv').writeAsString(
        'gt_variant,run,suite,dataset,category,mapper,row,field,outcome,gt,pred\n'
        '${_cells.join('\n')}\n');
    await File('out/latency_${tag}_$suffix.csv').writeAsString(
        'gt_variant,run,suite,dataset,mapper,ms\n${_latency.join('\n')}\n');
    await File('out/mappings_${tag}_$suffix.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(_mappings));
  }
}