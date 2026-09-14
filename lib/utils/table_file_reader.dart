import 'dart:io';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' hide Border;

class TableFileReader {
  static Future<List<List<dynamic>>> read(File file) async {
    if (file.path.toLowerCase().endsWith('.xlsx')) {
      return _readXlsx(file);
    }
    return _readCsv(file);
  }

  static Future<List<List<dynamic>>> _readCsv(File file) async {
    final input = await file.readAsString();
    final normalized = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(normalized);
  }

  static Future<List<List<dynamic>>> _readXlsx(File file) async {
    final bytes = await file.readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    Sheet? sheet;
    for (final name in excel.tables.keys) {
      final s = excel.tables[name];
      if (s != null && s.maxRows > 0) {
        sheet = s;
        break;
      }
    }
    if (sheet == null) return [];

    final rows = <List<dynamic>>[];
    for (final row in sheet.rows) {
      final cells = row.map((cell) {
        if (cell == null) return '';
        final v = cell.value;
        if (v == null) return '';
        if (v is DateCellValue) {
          final dt = v.asDateTimeLocal();
          return '${dt.day.toString().padLeft(2, '0')}/'
              '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        }
        if (v is DoubleCellValue) {
          final d = v.value;
          return d == d.truncateToDouble() ? d.toInt().toString() : d.toString();
        }
        if (v is IntCellValue) return v.value.toString();
        if (v is BoolCellValue) return v.value.toString();
        return v.toString();
      }).toList();
      if (cells.every((c) => c.toString().trim().isEmpty)) continue;
      rows.add(cells);
    }
    return rows;
  }
}