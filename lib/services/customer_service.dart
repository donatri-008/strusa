import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class CustomerModel {
  final String id;
  final List<String> numbers;
  final String name;
  final bool hasDebt;
  final int totalDebt;
  final DateTime? lastTransaction;

  const CustomerModel({
    required this.id,
    required this.numbers,
    required this.name,
    this.hasDebt = false,
    this.totalDebt = 0,
    this.lastTransaction,
  });

  CustomerModel copyWith({
    String?       id,
    List<String>? numbers,
    String?       name,
    bool?         hasDebt,
    int?          totalDebt,
    DateTime?     lastTransaction,
  }) {
    return CustomerModel(
      id:              id              ?? this.id,
      numbers:         numbers         ?? this.numbers,
      name:            name            ?? this.name,
      hasDebt:         hasDebt         ?? this.hasDebt,
      totalDebt:       totalDebt       ?? this.totalDebt,
      lastTransaction: lastTransaction ?? this.lastTransaction,
    );
  }

  String get number => numbers.isNotEmpty ? numbers.first : '';

  bool hasNumber(String n) {
    final clean = _cleanNum(n);
    return numbers.any((x) => _cleanNum(x) == clean);
  }

  String get numbersDisplay => numbers.join(', ');

  static String _cleanNum(String n) =>
      n.trim().replaceAll(RegExp(r'\s+'), '');

  factory CustomerModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;

    final rawList = d['numbers'];
    List<String> numbers = [];
    if (rawList is List) {
      numbers = rawList
          .map((e) => e.toString().trim().replaceAll(RegExp(r'\s+'), ''))
          .where((e) => e.isNotEmpty)
          .toList();
    }

    if (numbers.isEmpty) {
      final legacy = (d['number'] as String? ?? '').trim();
      if (legacy.isNotEmpty) numbers = [legacy];
    }

    return CustomerModel(
      id: doc.id,
      numbers: numbers,
      name: d['name'] ?? '',
      hasDebt: d['hasDebt'] ?? false,
      totalDebt: (d['totalDebt'] as num?)?.toInt() ?? 0,
      lastTransaction: (d['lastTransaction'] as Timestamp?)?.toDate(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hasil cleanup
// ─────────────────────────────────────────────────────────────────────────────

class CleanupResult {
  final int namesCorrected;
  final int customersMerged;
  final int numbersConsolidated;
  final List<String> log;

  const CleanupResult({
    required this.namesCorrected,
    required this.customersMerged,
    required this.numbersConsolidated,
    required this.log,
  });

  bool get hasChanges =>
      namesCorrected > 0 || customersMerged > 0 || numbersConsolidated > 0;

  String get summary {
    if (!hasChanges) return 'Data pelanggan sudah bersih, tidak ada duplikat.';
    final parts = <String>[];
    if (namesCorrected > 0) parts.add('$namesCorrected nama dikoreksi');
    if (customersMerged > 0) parts.add('$customersMerged duplikat digabung');
    if (numbersConsolidated > 0) {
      parts.add('$numbersConsolidated nomor dikonsolidasi');
    }
    return '${parts.join(', ')}.';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class CustomerService {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid => _auth.currentUser?.uid ?? 'unknown';

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('customers');

  // ── Normalisasi ────────────────────────────────────────────────────────────

  static String _cleanNum(String n) =>
      n.trim().replaceAll(RegExp(r'\s+'), '');

  static String normalizeName(String name) {
    final s = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.isEmpty) return '';
    return s.split(' ').map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  String _docId(String name) {
    final key = name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    return '${_uid}_$key';
  }

  // ── Read ────────────────────────────────────────────────────────────────────
  Future<List<CustomerModel>> getAll() async {
    try {
      final prefix    = '${_uid}_';
      final prefixEnd = '${_uid}_\uf8ff';

      QuerySnapshot<Map<String, dynamic>> snap;

      try {
        // Coba dari server dulu
        snap = await _col
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: prefix)
            .where(FieldPath.documentId, isLessThanOrEqualTo: prefixEnd)
            .get(const GetOptions(source: Source.server));
      } catch (_) {
        // Server tidak bisa dijangkau → pakai cache
        debugPrint('[CustomerService] Server tidak bisa dijangkau, pakai cache');
        snap = await _col
            .where(FieldPath.documentId, isGreaterThanOrEqualTo: prefix)
            .where(FieldPath.documentId, isLessThanOrEqualTo: prefixEnd)
            .get(const GetOptions(source: Source.cache));
      }

      debugPrint('[CustomerService] getAll: ${snap.docs.length} docs (uid: $_uid)');

      final list = snap.docs.map(CustomerModel.fromFirestore).toList();
      list.sort((a, b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    } catch (e, st) {
      debugPrint('[CustomerService] getAll error: $e\n$st');
      return [];
    }
  }

  Future<void> delete(String id) async {
    try {
      await _col.doc(id).delete();
    } catch (e) {
      debugPrint('[CustomerService] delete error: $e');
      rethrow;
    }
  }

  Future<void> updateCustomer({
    required String id,
    required String name,
    required List<String> numbers,
  }) async {
    final cleanName = normalizeName(name);
    if (cleanName.isEmpty) return;

    final cleanNums = numbers
        .map((n) => _cleanNum(n))
        .where((n) => n.isNotEmpty && RegExp(r'^\d+$').hasMatch(n))
        .toList();

    try {
      await _col.doc(id).update({
        'name'     : cleanName,
        'numbers'  : cleanNums,
        'number'   : cleanNums.isNotEmpty ? cleanNums.first : '',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[CustomerService] updateCustomer error: $e');
      rethrow;
    }
  }

  Future<CustomerModel?> getByNumber(String number) async {
    try {
      final clean = _cleanNum(number);
      if (clean.isEmpty) return null;

      final snap = await _col
          .where('userId', isEqualTo: _uid)
          .where('numbers', arrayContains: clean)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return CustomerModel.fromFirestore(snap.docs.first);
      }

      final snap2 = await _col
          .where('userId', isEqualTo: _uid)
          .where('number', isEqualTo: clean)
          .limit(1)
          .get();
      if (snap2.docs.isNotEmpty) {
        return CustomerModel.fromFirestore(snap2.docs.first);
      }

      return null;
    } catch (e) {
      debugPrint('[CustomerService] getByNumber error: $e');
      return null;
    }
  }

  Future<CustomerModel?> _getByNameExact(String name) async {
    final clean = normalizeName(name);
    if (clean.isEmpty) return null;
    final all = await getAll();
    return all
        .where((c) => c.name.toLowerCase() == clean.toLowerCase())
        .firstOrNull;
  }

  // ── Write ────────────────────────────────────────────────────────────────────

  Future<void> upsert({
    required String number,
    required String name,
  }) async {
    final cleanNum  = _cleanNum(number);
    final cleanName = normalizeName(name);
    if (cleanName.isEmpty) return;

    if (cleanNum.isNotEmpty && !RegExp(r'^\d+$').hasMatch(cleanNum)) {
      if (cleanNum.toLowerCase() == cleanName.toLowerCase()) {
        debugPrint('[CustomerService] upsert dipanggil dengan number=name, redirect ke upsertNameOnly');
        await upsertNameOnly(name: cleanName);
        return;
      }
    }

    try {
      final byName = await _getByNameExact(cleanName);

      if (byName != null) {
        final updates = <String, dynamic>{
          'name':            cleanName,
          'lastTransaction': FieldValue.serverTimestamp(),
        };
        if (cleanNum.isNotEmpty && !byName.hasNumber(cleanNum)) {
          updates['numbers'] = FieldValue.arrayUnion([cleanNum]);
          if (byName.number.isEmpty) updates['number'] = cleanNum;
        }
        await _col.doc(byName.id).update(updates);
        return;
      }

      if (cleanNum.isNotEmpty) {
        final byNum = await getByNumber(cleanNum);
        if (byNum != null) {
          if (byNum.name.isEmpty) {
            await _col.doc(byNum.id).update({
              'name':            cleanName,
              'lastTransaction': FieldValue.serverTimestamp(),
            });
          }
          return;
        }
      }

      final docId = _docId(cleanName);
      final nums  = cleanNum.isNotEmpty ? [cleanNum] : <String>[];

      await _col.doc(docId).set({
        'userId':          _uid,
        'name':            cleanName,
        'number':          cleanNum,
        'numbers':         nums,
        'hasDebt':         false,
        'totalDebt':       0,
        'lastTransaction': FieldValue.serverTimestamp(),
        'createdAt':       FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[CustomerService] upsert error: $e');
    }
  }

  Future<void> upsertNameOnly({required String name}) async {
    final cleanName = normalizeName(name);
    if (cleanName.isEmpty) return;

    try {
      final byName = await _getByNameExact(cleanName);

      if (byName != null) {
        await _col.doc(byName.id).update({
          'name':            cleanName,
          'lastTransaction': FieldValue.serverTimestamp(),
        });
        return;
      }

      final docId = _docId(cleanName);
      await _col.doc(docId).set({
        'userId':          _uid,
        'name':            cleanName,
        'number':          '',
        'numbers':         <String>[],
        'hasDebt':         false,
        'totalDebt':       0,
        'lastTransaction': FieldValue.serverTimestamp(),
        'createdAt':       FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[CustomerService] upsertNameOnly error: $e');
    }
  }

  Future<void> updateDebtStatus({
    required String number,
    required bool hasDebt,
    required int totalDebt,
  }) async {
    try {
      final c = await getByNumber(number);
      if (c == null) return;
      await _col.doc(c.id).update({
        'hasDebt':   hasDebt,
        'totalDebt': totalDebt,
      });
    } catch (e) {
      debugPrint('[CustomerService] updateDebtStatus error: $e');
    }
  }

  // ── Cleanup otomatis ────────────────────────────────────────────────────────

  Future<CleanupResult> cleanupDuplicates() async {
    final log               = <String>[];
    int namesCorrected      = 0;
    int customersMerged     = 0;
    int numbersConsolidated = 0;

    try {
      final prefix    = '${_uid}_';
      final prefixEnd = '${_uid}_\uf8ff';

      // ✅ FIX: Sama seperti getAll() — ganti orderBy ke where(FieldPath.documentId)
      final snap = await _col
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: prefix)
          .where(FieldPath.documentId, isLessThanOrEqualTo: prefixEnd)
          .get();

      if (snap.docs.isEmpty) {
        return const CleanupResult(
          namesCorrected: 0,
          customersMerged: 0,
          numbersConsolidated: 0,
          log: ['Tidak ada data pelanggan.'],
        );
      }

      final Map<String, List<Map<String, dynamic>>> groups = {};

      for (final doc in snap.docs) {
        final d = doc.data();

        final rawName   = (d['name'] as String? ?? '').trim();
        final cleanName = normalizeName(rawName);
        if (cleanName.isEmpty) continue;

        if (rawName != cleanName) {
          namesCorrected++;
          log.add('Nama: "$rawName" → "$cleanName"');
        }

        final Set<String> nums = {};
        final legacy = _cleanNum(d['number'] as String? ?? '');

        if (legacy.isNotEmpty && RegExp(r'^\d+$').hasMatch(legacy)) {
          nums.add(legacy);
        }

        final list = d['numbers'];
        if (list is List) {
          for (final n in list) {
            final c = _cleanNum(n.toString());
            if (c.isNotEmpty && RegExp(r'^\d+$').hasMatch(c)) {
              nums.add(c);
            }
          }
        }

        final key = cleanName.toLowerCase();
        groups.putIfAbsent(key, () => []).add({
          'docId':     doc.id,
          'ref':       doc.reference,
          'name':      cleanName,
          'numbers':   nums.toList(),
          'hasDebt':   d['hasDebt'] as bool? ?? false,
          'totalDebt': (d['totalDebt'] as num?)?.toInt() ?? 0,
          'lastTx':    d['lastTransaction'] as Timestamp?,
          'createdAt': d['createdAt'],
        });
      }

      final batch = _db.batch();
      int ops = 0;

      for (final entry in groups.entries) {
        final items      = entry.value;
        final masterName = items.first['name'] as String;

        final Set<String> allNums = {};
        int        totalDebt = 0;
        bool       hasDebt   = false;
        Timestamp? latestTx;
        dynamic    createdAt;

        for (final item in items) {
          allNums.addAll(item['numbers'] as List<String>);
          totalDebt += item['totalDebt'] as int;
          hasDebt    = hasDebt || (item['hasDebt'] as bool);
          createdAt ??= item['createdAt'];

          final tx = item['lastTx'] as Timestamp?;
          if (tx != null &&
              (latestTx == null ||
                  tx.toDate().isAfter(latestTx.toDate()))) {
            latestTx = tx;
          }
        }

        final masterDocId = _docId(masterName);
        final masterRef   = _col.doc(masterDocId);

        if (items.length > 1) {
          customersMerged     += items.length - 1;
          numbersConsolidated += allNums.length;
          log.add(
            'Gabung "$masterName": '
            '${items.length} dokumen → '
            '${allNums.length} nomor: ${allNums.join(', ')}',
          );
        } else if (items.length == 1) {
          final item    = items.first;
          final oldNums = item['numbers'] as List<String>;
          final docRef  = item['ref'] as DocumentReference;

          if (docRef.id == masterDocId &&
              (item['name'] as String) == masterName) {
            batch.update(docRef, {
              'name':    masterName,
              'numbers': oldNums,
              'number':  oldNums.isNotEmpty ? oldNums.first : '',
            });
            ops++;
            continue;
          }
        }

        batch.set(masterRef, {
          'userId':          _uid,
          'name':            masterName,
          'number':          allNums.isNotEmpty ? allNums.first : '',
          'numbers':         allNums.toList(),
          'hasDebt':         hasDebt,
          'totalDebt':       totalDebt,
          'lastTransaction': latestTx ?? FieldValue.serverTimestamp(),
          'createdAt':       createdAt ?? FieldValue.serverTimestamp(),
        });
        ops++;

        for (final item in items) {
          final ref = item['ref'] as DocumentReference;
          if (ref.id != masterDocId) {
            batch.delete(ref);
            ops++;
            log.add('  Hapus lama: ${ref.id}');
          }
        }

        if (ops >= 450) {
          await batch.commit();
          ops = 0;
        }
      }

      if (ops > 0) await batch.commit();

    } catch (e, st) {
      debugPrint('[CustomerService] cleanupDuplicates error: $e\n$st');
      log.add('ERROR: $e');
    }

    return CleanupResult(
      namesCorrected:      namesCorrected,
      customersMerged:     customersMerged,
      numbersConsolidated: numbersConsolidated,
      log:                 log,
    );
  }
}