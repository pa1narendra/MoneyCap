import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction_model.dart';

/// Columns loaded for list/stat views. `body` (the full SMS text, by far the
/// largest column) is deliberately left out and fetched on demand via
/// [DatabaseHelper.readBody], which keeps the in-memory list small.
const _listColumns = [
  'id', 'amount', 'type', 'merchant', 'timestamp', 'source', 'dedup_key',
  'kind', 'account', 'category',
];

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static const schemaVersion = 5;

  /// Set when an upgrade to v5 happens: rows parsed by the old parser are
  /// unreliable, so the next sync re-imports SMS rows from the inbox.
  static bool needsRescan = false;

  DatabaseHelper._init();

  /// Tests point this at a temp file (with the ffi database factory).
  @visibleForTesting
  static String? pathOverride;

  @visibleForTesting
  static Future<void> resetForTest() async {
    await _database?.close();
    _database = null;
    needsRescan = false;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('moneycap.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final path = pathOverride ?? join(await getDatabasesPath(), filePath);
    return openDatabase(
      path,
      version: schemaVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  amount REAL NOT NULL,
  type TEXT NOT NULL,
  merchant TEXT NOT NULL,
  timestamp INTEGER NOT NULL,
  body TEXT NOT NULL,
  source TEXT NOT NULL,
  dedup_key TEXT,
  kind TEXT NOT NULL DEFAULT 'NORMAL',
  account TEXT,
  category TEXT
)''');
    await db.execute('CREATE INDEX idx_timestamp ON transactions (timestamp)');
    await db.execute(
        'CREATE UNIQUE INDEX idx_dedup ON transactions(dedup_key) WHERE dedup_key IS NOT NULL');
    await _createMonthlyBalancesV5(db);
    await _createV5Tables(db);
  }

  Future<void> _createMonthlyBalancesV5(Database db) async {
    // account '' = all bank accounts combined.
    await db.execute('''
CREATE TABLE monthly_balances (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  month TEXT NOT NULL,
  account TEXT NOT NULL DEFAULT '',
  opening_balance REAL,
  closing_balance REAL,
  opening_recorded_at TEXT,
  closing_recorded_at TEXT,
  is_reconciled INTEGER DEFAULT 0
)''');
    await db.execute(
        'CREATE UNIQUE INDEX idx_month_account ON monthly_balances (month, account)');
  }

  Future<void> _createV5Tables(Database db) async {
    // Dedup keys of SMS rows the user deleted, so a re-scan never revives them.
    await db.execute('CREATE TABLE ignored_keys (dedup_key TEXT PRIMARY KEY)');
    // User merchant->category rules. `pattern` is a lowercase substring.
    await db.execute(
        'CREATE TABLE category_rules (pattern TEXT PRIMARY KEY, category TEXT NOT NULL)');
    await db.execute(
        'CREATE TABLE budgets (category TEXT PRIMARY KEY, monthly_limit REAL NOT NULL)');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE transactions ADD COLUMN source TEXT DEFAULT 'SMS'");
    }
    if (oldVersion < 3) {
      await db.execute('''
CREATE TABLE monthly_balances (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  month TEXT NOT NULL,
  opening_balance REAL,
  closing_balance REAL,
  opening_recorded_at TEXT,
  closing_recorded_at TEXT,
  is_reconciled INTEGER DEFAULT 0
)''');
      await db.execute('CREATE UNIQUE INDEX idx_month ON monthly_balances (month)');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE transactions ADD COLUMN dedup_key TEXT');
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_dedup ON transactions(dedup_key) WHERE dedup_key IS NOT NULL');
    }
    if (oldVersion < 5) {
      await db.execute("ALTER TABLE transactions ADD COLUMN kind TEXT NOT NULL DEFAULT 'NORMAL'");
      await db.execute('ALTER TABLE transactions ADD COLUMN account TEXT');
      await db.execute('ALTER TABLE transactions ADD COLUMN category TEXT');
      // Balances become per-account: add the column, swap the unique index.
      await db.execute("ALTER TABLE monthly_balances ADD COLUMN account TEXT NOT NULL DEFAULT ''");
      await db.execute('DROP INDEX IF EXISTS idx_month');
      await db.execute(
          'CREATE UNIQUE INDEX idx_month_account ON monthly_balances (month, account)');
      await _createV5Tables(db);
      needsRescan = true;
    }
  }

  // ---------------- Transactions ----------------

  Future<int> create(TransactionModel transaction) async {
    final db = await database;
    return db.insert('transactions', transaction.toMap()..remove('id'));
  }

  /// Batch-insert pre-built column maps (e.g. produced off-isolate by the
  /// parser) in ONE transaction. Rows whose dedup_key already exists or was
  /// deleted by the user are skipped. Returns the ids of inserted rows.
  Future<List<int>> createAllRaw(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return const [];
    final db = await database;
    final ignored = await _ignoredKeys(db);
    final batch = db.batch();
    var queued = 0;
    for (final row in rows) {
      final key = row['dedup_key'] as String?;
      if (key != null && ignored.contains(key)) continue;
      batch.insert('transactions', Map<String, dynamic>.from(row)..remove('id'),
          conflictAlgorithm: ConflictAlgorithm.ignore);
      queued++;
    }
    if (queued == 0) return const [];
    final results = await batch.commit();
    // insert() with IGNORE returns 0 when the row was skipped.
    return results.whereType<int>().where((id) => id > 0).toList();
  }

  Future<Set<String>> _ignoredKeys(Database db) async {
    final rows = await db.query('ignored_keys');
    return rows.map((r) => r['dedup_key'] as String).toSet();
  }

  /// All transactions newest first, WITHOUT the SMS body (see [readBody]).
  Future<List<TransactionModel>> readAllTransactions() async {
    final db = await database;
    final result = await db.query('transactions',
        columns: _listColumns, orderBy: 'timestamp DESC, id DESC');
    return result
        .map((r) => TransactionModel.fromMap({...r, 'body': ''}))
        .toList(growable: false);
  }

  Future<String> readBody(int id) async {
    final db = await database;
    final r = await db.query('transactions',
        columns: ['body'], where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? '' : (r.first['body'] as String? ?? '');
  }

  /// Updates the editable fields only; never overwrites body/dedup/source.
  Future<int> update(TransactionModel t) async {
    final db = await database;
    return db.update(
      'transactions',
      {
        'amount': t.amount,
        'type': t.type,
        'merchant': t.merchant,
        'timestamp': t.timestamp.millisecondsSinceEpoch,
        'kind': t.kind,
        'account': t.account,
        'category': t.category,
      },
      where: 'id = ?',
      whereArgs: [t.id],
    );
  }

  /// Deletes a row. For SMS rows the dedup key is remembered so the same
  /// message is never re-imported by a later scan.
  Future<void> delete(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      final r = await txn.query('transactions',
          columns: ['dedup_key'], where: 'id = ?', whereArgs: [id], limit: 1);
      final key = r.isEmpty ? null : r.first['dedup_key'] as String?;
      if (key != null) {
        await txn.insert('ignored_keys', {'dedup_key': key},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await txn.delete('transactions', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Removes SMS-imported rows only. Manual entries, balances, rules and
  /// budgets are kept (they can't be recovered from the inbox).
  Future<int> deleteSmsTransactions() async {
    final db = await database;
    return db.delete('transactions', where: 'source = ?', whereArgs: ['SMS']);
  }

  /// Marks a debit and a credit of the same amount on two DIFFERENT accounts
  /// within [window] as an own-account transfer. Only pairs involving one of
  /// [newIds] are considered, so a pair the user un-marked is never redone.
  Future<int> pairTransfers(List<int> newIds,
      {Duration window = const Duration(minutes: 30)}) async {
    if (newIds.isEmpty) return 0;
    final db = await database;
    final fresh = newIds.toSet();
    final bounds = await db.rawQuery(
        "SELECT MIN(timestamp) lo, MAX(timestamp) hi FROM transactions WHERE id IN (${newIds.join(',')})");
    final lo = bounds.first['lo'] as int?;
    final hi = bounds.first['hi'] as int?;
    if (lo == null || hi == null) return 0;
    // One query for every candidate in the time span, then a linear sweep.
    final rows = await db.query('transactions',
        columns: ['id', 'amount', 'type', 'timestamp', 'account'],
        where: "kind = 'NORMAL' AND account IS NOT NULL AND timestamp BETWEEN ? AND ?",
        whereArgs: [lo - window.inMilliseconds, hi + window.inMilliseconds],
        orderBy: 'timestamp');
    final ids = pairTransferIds(rows, fresh, window);
    if (ids.isEmpty) return 0;
    return db.update('transactions', {'kind': TransactionModel.kindTransfer},
        where: 'id IN (${ids.join(',')})');
  }

  /// Pure pairing logic (unit-tested). [rows] must be sorted by timestamp.
  static Set<int> pairTransferIds(
      List<Map<String, Object?>> rows, Set<int> fresh, Duration window) {
    final used = <int>{};
    for (var i = 0; i < rows.length; i++) {
      final a = rows[i];
      final aId = a['id'] as int;
      if (used.contains(aId)) continue;
      for (var j = i + 1; j < rows.length; j++) {
        final b = rows[j];
        final dt = (b['timestamp'] as int) - (a['timestamp'] as int);
        if (dt > window.inMilliseconds) break;
        final bId = b['id'] as int;
        if (used.contains(bId)) continue;
        if (!fresh.contains(aId) && !fresh.contains(bId)) continue;
        if (a['type'] == b['type'] || a['account'] == b['account']) continue;
        if (((a['amount'] as num) - (b['amount'] as num)).abs() >= 0.005) continue;
        used..add(aId)..add(bId);
        break;
      }
    }
    return used;
  }

  // ---------------- Categories & budgets ----------------

  Future<Map<String, String>> getCategoryRules() async {
    final db = await database;
    final rows = await db.query('category_rules', orderBy: 'pattern');
    return {for (final r in rows) r['pattern'] as String: r['category'] as String};
  }

  Future<void> setCategoryRule(String pattern, String category) async {
    final db = await database;
    await db.insert('category_rules',
        {'pattern': pattern.toLowerCase().trim(), 'category': category},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCategoryRule(String pattern) async {
    final db = await database;
    await db.delete('category_rules', where: 'pattern = ?', whereArgs: [pattern]);
  }

  Future<Map<String, double>> getBudgets() async {
    final db = await database;
    final rows = await db.query('budgets');
    return {
      for (final r in rows) r['category'] as String: (r['monthly_limit'] as num).toDouble()
    };
  }

  Future<void> setBudget(String category, double limit) async {
    final db = await database;
    await db.insert('budgets', {'category': category, 'monthly_limit': limit},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteBudget(String category) async {
    final db = await database;
    await db.delete('budgets', where: 'category = ?', whereArgs: [category]);
  }

  // ---------------- Monthly balances (per account) ----------------

  Future<Map<String, dynamic>?> getMonthlyBalance(String month, {String account = ''}) async {
    final db = await database;
    final result = await db.query('monthly_balances',
        where: 'month = ? AND account = ?', whereArgs: [month, account], limit: 1);
    return result.isNotEmpty ? result.first : null;
  }

  Future<void> _upsertBalance(String month, String account, Map<String, Object?> values) async {
    final db = await database;
    await db.transaction((txn) async {
      final n = await txn.update('monthly_balances', values,
          where: 'month = ? AND account = ?', whereArgs: [month, account]);
      if (n == 0) {
        await txn.insert('monthly_balances', {'month': month, 'account': account, ...values});
      }
    });
  }

  Future<void> saveOpeningBalance(String month, double balance, {String account = ''}) =>
      _upsertBalance(month, account, {
        'opening_balance': balance,
        'opening_recorded_at': DateTime.now().toIso8601String(),
        'is_reconciled': 0,
      });

  Future<void> saveClosingBalance(String month, double balance, {String account = ''}) =>
      _upsertBalance(month, account, {
        'closing_balance': balance,
        'closing_recorded_at': DateTime.now().toIso8601String(),
        'is_reconciled': 0,
      });

  Future<int> markReconciled(String month, {String account = ''}) async {
    final db = await database;
    return db.update('monthly_balances', {'is_reconciled': 1},
        where: 'month = ? AND account = ?', whereArgs: [month, account]);
  }

  /// Transactions in [month] (yyyy-MM) used for reconciliation. With an
  /// [account] only that account's rows (transfers included: they really
  /// moved money). With '' = all bank accounts combined: card rows are left
  /// out because a card balance isn't part of a bank balance.
  Future<List<Map<String, Object?>>> monthRows(String month, {String account = ''}) async {
    final db = await database;
    final parts = month.split('-');
    final start = DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
    final end = DateTime(start.year, start.month + 1, 1);
    final where = StringBuffer('timestamp >= ? AND timestamp < ?');
    final args = <Object?>[start.millisecondsSinceEpoch, end.millisecondsSinceEpoch];
    if (account.isNotEmpty) {
      where.write(' AND account = ?');
      args.add(account);
    } else {
      where.write(" AND (account IS NULL OR account NOT LIKE 'Card%')");
    }
    return db.query('transactions',
        columns: ['amount', 'type', 'kind'], where: where.toString(), whereArgs: args);
  }

  /// Every row in [month] regardless of account (for totals; callers skip
  /// transfers themselves).
  Future<List<Map<String, Object?>>> monthRowsAllAccounts(String month) async {
    final db = await database;
    final parts = month.split('-');
    final start = DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
    final end = DateTime(start.year, start.month + 1, 1);
    return db.query('transactions',
        columns: ['amount', 'type', 'kind'],
        where: 'timestamp >= ? AND timestamp < ?',
        whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch]);
  }

  // ---------------- Backup / restore ----------------

  static const _backupTables = [
    'transactions', 'monthly_balances', 'ignored_keys', 'category_rules', 'budgets',
  ];

  Future<Map<String, List<Map<String, Object?>>>> dumpAll() async {
    final db = await database;
    return {for (final t in _backupTables) t: await db.query(t)};
  }

  /// Replaces ALL data with [tables] in one transaction (all-or-nothing).
  Future<void> restoreAll(Map<String, List<Map<String, Object?>>> tables) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final t in _backupTables) {
        await txn.delete(t);
      }
      for (final t in _backupTables) {
        for (final row in tables[t] ?? const <Map<String, Object?>>[]) {
          await txn.insert(t, row, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
  }
}
