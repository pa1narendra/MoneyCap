import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'db_service.dart';

class BackupException implements Exception {
  final String message;
  BackupException(this.message);
  @override
  String toString() => message;
}

/// Full local backup/restore as a single JSON file that the user shares/saves
/// themselves (nothing is uploaded by the app).
///
/// Restore treats the file as UNTRUSTED: only known tables and columns are
/// accepted (map keys become SQL column names, so this whitelist is what
/// blocks SQL injection through a crafted file) and every value is
/// type-checked before anything is written. The restore itself is one DB
/// transaction, so a bad file can't leave data half-replaced.
class BackupService {
  BackupService._();

  static const format = 'moneycap-backup';

  /// column -> expected type ('i' int, 'r' real/num, 't' text). Upper-case
  /// means NOT NULL.
  static const _schema = <String, Map<String, String>>{
    'transactions': {
      'id': 'i', 'amount': 'R', 'type': 'T', 'merchant': 'T', 'timestamp': 'I',
      'body': 'T', 'source': 'T', 'dedup_key': 't', 'kind': 't', 'account': 't',
      'category': 't',
    },
    'monthly_balances': {
      'id': 'i', 'month': 'T', 'account': 't', 'opening_balance': 'r',
      'closing_balance': 'r', 'opening_recorded_at': 't', 'closing_recorded_at': 't',
      'is_reconciled': 'i',
    },
    'ignored_keys': {'dedup_key': 'T'},
    'category_rules': {'pattern': 'T', 'category': 'T'},
    'budgets': {'category': 'T', 'monthly_limit': 'R'},
  };

  static Future<String> encode() async {
    final tables = await DatabaseHelper.instance.dumpAll();
    return jsonEncode({
      'format': format,
      'schema': DatabaseHelper.schemaVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'tables': tables,
    });
  }

  /// Writes the backup into the app's private temp dir and returns the file
  /// (the caller hands it to the share sheet). Older exports are removed.
  static Future<File> writeExportFile(String name, String contents) async {
    final dir = await getTemporaryDirectory();
    await cleanupExports();
    final file = File('${dir.path}/$name');
    await file.writeAsString(contents, flush: true);
    return file;
  }

  /// Deletes exported CSV/backup files left in the temp dir (they contain
  /// financial data and shouldn't linger after being shared).
  static Future<void> cleanupExports() async {
    try {
      final dir = await getTemporaryDirectory();
      await for (final f in dir.list()) {
        final n = f.uri.pathSegments.isEmpty ? '' : f.uri.pathSegments.last;
        if (f is File && n.startsWith('moneycap_')) await f.delete();
      }
    } catch (_) {}
  }

  /// Validates [json] and returns sanitized tables. Throws [BackupException].
  static Map<String, List<Map<String, Object?>>> decode(String json) {
    final Object? root;
    try {
      root = jsonDecode(json);
    } catch (_) {
      throw BackupException('This file is not a MoneyCap backup.');
    }
    if (root is! Map || root['format'] != format || root['tables'] is! Map) {
      throw BackupException('This file is not a MoneyCap backup.');
    }
    final schema = root['schema'];
    if (schema is! int || schema > DatabaseHelper.schemaVersion) {
      throw BackupException('This backup is from a newer version of MoneyCap. Update the app first.');
    }
    final tables = root['tables'] as Map;
    final out = <String, List<Map<String, Object?>>>{};
    for (final entry in _schema.entries) {
      final rows = tables[entry.key];
      if (rows == null) {
        out[entry.key] = const [];
        continue;
      }
      if (rows is! List) throw BackupException('Backup is damaged (${entry.key}).');
      out[entry.key] = [
        for (final r in rows) _cleanRow(entry.key, entry.value, r),
      ];
    }
    return out;
  }

  static Map<String, Object?> _cleanRow(String table, Map<String, String> cols, Object? r) {
    if (r is! Map) throw BackupException('Backup is damaged ($table).');
    final row = <String, Object?>{};
    for (final c in cols.entries) {
      final v = r[c.key];
      final required = c.value == c.value.toUpperCase();
      if (v == null) {
        if (required) throw BackupException('Backup is damaged ($table.${c.key}).');
        continue;
      }
      switch (c.value.toLowerCase()) {
        case 'i':
          if (v is! int) throw BackupException('Backup is damaged ($table.${c.key}).');
          row[c.key] = v;
        case 'r':
          if (v is! num || !v.isFinite) throw BackupException('Backup is damaged ($table.${c.key}).');
          row[c.key] = v.toDouble();
        case 't':
          if (v is! String) throw BackupException('Backup is damaged ($table.${c.key}).');
          row[c.key] = v;
      }
    }
    // Older backups (schema < 5) lack these; fill the same defaults the
    // migration would.
    if (table == 'transactions') row['kind'] ??= 'NORMAL';
    if (table == 'monthly_balances') row['account'] ??= '';
    return row;
  }

  static Future<void> restore(String json) async {
    final tables = decode(json);
    await DatabaseHelper.instance.restoreAll(tables);
  }
}
