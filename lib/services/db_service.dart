
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('moneycap.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4, // v4: dedup_key on transactions
      onCreate: _createDB,
      onUpgrade: _upgradeDB, // Handle migration
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const realType = 'REAL NOT NULL';
    const integerType = 'INTEGER NOT NULL';

    await db.execute('''
CREATE TABLE transactions (
  id $idType,
  amount $realType,
  type $textType,
  merchant $textType,
  timestamp $integerType,
  body $textType,
  source $textType,
  dedup_key TEXT
  )
''');
    // Index for faster sorting and filtering by date
    await db.execute('CREATE INDEX idx_timestamp ON transactions (timestamp)');
    // Unique signature per SMS transaction so re-delivered messages can't create
    // duplicate rows. Partial (NULL excluded) so manual entries are never merged.
    await db.execute(
        'CREATE UNIQUE INDEX idx_dedup ON transactions(dedup_key) WHERE dedup_key IS NOT NULL');
    
    // Monthly balances table
    await db.execute('''
CREATE TABLE monthly_balances (
  id $idType,
  month $textType,
  opening_balance REAL,
  closing_balance REAL,
  opening_recorded_at TEXT,
  closing_recorded_at TEXT,
  is_reconciled INTEGER DEFAULT 0
  )
''');
    await db.execute('CREATE UNIQUE INDEX idx_month ON monthly_balances (month)');
  }

  // Add migration logic
  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE transactions ADD COLUMN source TEXT DEFAULT "SMS"');
    }
    if (oldVersion < 3) {
      // Create monthly_balances table
      const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
      const textType = 'TEXT NOT NULL';
      await db.execute('''
CREATE TABLE monthly_balances (
  id $idType,
  month $textType,
  opening_balance REAL,
  closing_balance REAL,
  opening_recorded_at TEXT,
  closing_recorded_at TEXT,
  is_reconciled INTEGER DEFAULT 0
  )
''');
      await db.execute('CREATE UNIQUE INDEX idx_month ON monthly_balances (month)');
    }
    if (oldVersion < 4) {
      // Add the de-dup signature column + a partial unique index. Existing rows
      // stay NULL (excluded from the index) so the migration can't fail on any
      // duplicates already present; dedup applies to all future inserts.
      await db.execute('ALTER TABLE transactions ADD COLUMN dedup_key TEXT');
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_dedup ON transactions(dedup_key) WHERE dedup_key IS NOT NULL');
    }
  }

  Future<int> create(TransactionModel transaction) async {
    final db = await instance.database;
    return await db.insert('transactions', transaction.toMap());
  }

  /// Insert many transactions in a SINGLE transaction (one fsync instead of one
  /// per row). This is the difference between a multi-minute first sync and a
  /// few-second one when thousands of SMS are imported.
  Future<void> createAll(List<TransactionModel> transactions) async {
    if (transactions.isEmpty) return;
    await createAllRaw(transactions.map((t) => t.toMap()).toList());
  }

  /// Batch-insert pre-built column maps (e.g. produced off-isolate by the
  /// parser). Each map must match the `transactions` columns; any `id` is
  /// dropped so AUTOINCREMENT assigns it.
  Future<void> createAllRaw(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();
    for (final row in rows) {
      final r = Map<String, dynamic>.from(row)..remove('id');
      // Skip rows whose dedup_key already exists (re-delivered SMS) instead of
      // failing the whole batch.
      batch.insert('transactions', r, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<DateTime?> getLatestTimestamp() async {
    final db = await instance.database;
    final result = await db.query(
      'transactions',
      columns: ['timestamp'],
      orderBy: 'timestamp DESC',
      where: "source = ?",
      whereArgs: ['SMS'],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(result.first['timestamp'] as int);
    }
    return null;
  }

  Future<TransactionModel> readTransaction(int id) async {
    final db = await instance.database;
    final maps = await db.query(
      'transactions',
      columns: ['id', 'amount', 'type', 'merchant', 'timestamp', 'body', 'source'],
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return TransactionModel.fromMap(maps.first);
    } else {
      throw Exception('ID $id not found');
    }
  }

  Future<List<TransactionModel>> readAllTransactions() async {
    final db = await instance.database;
    const orderBy = 'timestamp DESC';
    final result = await db.query('transactions', orderBy: orderBy);
    return result.map((json) => TransactionModel.fromMap(json)).toList();
  }

  Future<int> update(TransactionModel transaction) async {
    final db = await instance.database;
    return db.update(
      'transactions',
      transaction.toMap(),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await instance.database;
    return await db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAll() async {
    final db = await instance.database;
    return await db.delete('transactions');
  }

  // Monthly Balance Methods
  Future<Map<String, dynamic>?> getMonthlyBalance(String month) async {
    final db = await instance.database;
    final result = await db.query(
      'monthly_balances',
      where: 'month = ?',
      whereArgs: [month],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> saveOpeningBalance(String month, double balance) async {
    final db = await instance.database;
    final existing = await getMonthlyBalance(month);
    
    if (existing != null) {
      return await db.update(
        'monthly_balances',
        {
          'opening_balance': balance,
          'opening_recorded_at': DateTime.now().toIso8601String(),
        },
        where: 'month = ?',
        whereArgs: [month],
      );
    } else {
      return await db.insert('monthly_balances', {
        'month': month,
        'opening_balance': balance,
        'opening_recorded_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<int> saveClosingBalance(String month, double balance) async {
    final db = await instance.database;
    final existing = await getMonthlyBalance(month);
    
    if (existing != null) {
      return await db.update(
        'monthly_balances',
        {
          'closing_balance': balance,
          'closing_recorded_at': DateTime.now().toIso8601String(),
        },
        where: 'month = ?',
        whereArgs: [month],
      );
    } else {
      return await db.insert('monthly_balances', {
        'month': month,
        'closing_balance': balance,
        'closing_recorded_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<int> markReconciled(String month) async {
    final db = await instance.database;
    return await db.update(
      'monthly_balances',
      {'is_reconciled': 1},
      where: 'month = ?',
      whereArgs: [month],
    );
  }

  Future<List<Map<String, dynamic>>> getAllMonthlyBalances() async {
    final db = await instance.database;
    return await db.query('monthly_balances', orderBy: 'month DESC');
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
