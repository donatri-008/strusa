import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Logger waktu rekap MANUAL vs OTOMATIS (via Strusa+Gemini), buat RM4:
/// "Bagaimana efisiensi waktu & pengurangan human error rekap otomatis vs manual?"
///
/// Cara pakai:
///   final timer = ReconciliationTimer();
///   timer.startManual();
///   ... (peneliti rekap manual pakai stopwatch HP / observasi langsung) ...
///   await timer.stopManual(rowCount: 50, errorCount: 3, notes: 'CSV OrderKuota Juli');
///
///   timer.startAutomated();
///   await controller.importFromCSV(file, userId);
///   await timer.stopAutomated(rowCount: 50, errorCount: 0, notes: 'CSV OrderKuota Juli');
///
///   final summary = await timer.exportSummary();
class ReconciliationSession {
  final String mode; // 'manual' atau 'automated'
  final int rowCount;
  final int errorCount; // jumlah baris salah/butuh koreksi manual
  final int durationMs;
  final String notes;
  final DateTime timestamp;

  ReconciliationSession({
    required this.mode,
    required this.rowCount,
    required this.errorCount,
    required this.durationMs,
    required this.notes,
    required this.timestamp,
  });

  double get errorRate => rowCount == 0 ? 0 : errorCount / rowCount;
  double get msPerRow => rowCount == 0 ? 0 : durationMs / rowCount;

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'rowCount': rowCount,
        'errorCount': errorCount,
        'durationMs': durationMs,
        'notes': notes,
        'timestamp': timestamp.toIso8601String(),
      };

  factory ReconciliationSession.fromJson(Map<String, dynamic> json) =>
      ReconciliationSession(
        mode: json['mode'],
        rowCount: json['rowCount'],
        errorCount: json['errorCount'],
        durationMs: json['durationMs'],
        notes: json['notes'] ?? '',
        timestamp: DateTime.parse(json['timestamp']),
      );
}

class ReconciliationTimer {
  static const String _prefsKey = 'reconciliation_sessions_log';

  Stopwatch? _manualStopwatch;
  Stopwatch? _automatedStopwatch;

  void startManual() {
    _manualStopwatch = Stopwatch()..start();
  }

  void startAutomated() {
    _automatedStopwatch = Stopwatch()..start();
  }

  Future<ReconciliationSession> stopManual({
    required int rowCount,
    required int errorCount,
    String notes = '',
  }) async {
    _manualStopwatch?.stop();
    final session = ReconciliationSession(
      mode: 'manual',
      rowCount: rowCount,
      errorCount: errorCount,
      durationMs: _manualStopwatch?.elapsedMilliseconds ?? 0,
      notes: notes,
      timestamp: DateTime.now(),
    );
    await _persist(session);
    _manualStopwatch = null;
    return session;
  }

  Future<ReconciliationSession> stopAutomated({
    required int rowCount,
    required int errorCount,
    String notes = '',
  }) async {
    _automatedStopwatch?.stop();
    final session = ReconciliationSession(
      mode: 'automated',
      rowCount: rowCount,
      errorCount: errorCount,
      durationMs: _automatedStopwatch?.elapsedMilliseconds ?? 0,
      notes: notes,
      timestamp: DateTime.now(),
    );
    await _persist(session);
    _automatedStopwatch = null;
    return session;
  }

  Future<void> _persist(ReconciliationSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_prefsKey) ?? [];
    existing.add(jsonEncode(session.toJson()));
    await prefs.setStringList(_prefsKey, existing);
  }

  Future<List<ReconciliationSession>> getAllSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    return raw
        .map((s) => ReconciliationSession.fromJson(jsonDecode(s)))
        .toList();
  }

  Future<void> clearAllSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Ringkasan perbandingan manual vs otomatis, siap dipakai di bab hasil (RM4).
  Future<Map<String, dynamic>> exportSummary() async {
    final sessions = await getAllSessions();
    final manual = sessions.where((s) => s.mode == 'manual').toList();
    final automated = sessions.where((s) => s.mode == 'automated').toList();

    double avg(List<double> xs) =>
        xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

    final manualAvgMsPerRow = avg(manual.map((s) => s.msPerRow).toList());
    final autoAvgMsPerRow = avg(automated.map((s) => s.msPerRow).toList());
    final manualAvgErrorRate = avg(manual.map((s) => s.errorRate).toList());
    final autoAvgErrorRate = avg(automated.map((s) => s.errorRate).toList());

    final speedupFactor =
        autoAvgMsPerRow == 0 ? 0 : manualAvgMsPerRow / autoAvgMsPerRow;

    return {
      'totalSesiManual': manual.length,
      'totalSesiOtomatis': automated.length,
      'rataRataMsPerBarisManual': manualAvgMsPerRow,
      'rataRataMsPerBarisOtomatis': autoAvgMsPerRow,
      'percepatan_x': speedupFactor,
      'rataRataErrorRateManual': manualAvgErrorRate,
      'rataRataErrorRateOtomatis': autoAvgErrorRate,
      'penguranganErrorRate':
          manualAvgErrorRate == 0 ? 0 : 1 - (autoAvgErrorRate / manualAvgErrorRate),
      'sesiMentah': sessions.map((s) => s.toJson()).toList(),
    };
  }
}