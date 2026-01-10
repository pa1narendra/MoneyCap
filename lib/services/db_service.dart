
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('finance_tracker.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2, // Increment version
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
  source $textType
  )
''');
    // Index for faster sorting and filtering by date
    await db.execute('CREATE INDEX idx_timestamp ON transactions (timestamp)');
  }

  // Add migration logic
  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE transactions ADD COLUMN source TEXT DEFAULT "SMS"');
    }
  }

  Future<int> create(TransactionModel transaction) async {
    final db = await instance.database;
    return await db.insert('transactions', transaction.toMap());
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

  Future<void> deleteAll() async {
     final db = await instance.database;
     await db.delete('transactions');
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
