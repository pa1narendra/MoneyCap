import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneycap/services/backup_service.dart';
import 'package:moneycap/services/db_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

void main() {
  late Directory dir;
  final db = DatabaseHelper.instance;

  setUp(() async => dir = await setUpTestDb());
  tearDown(() async => tearDownTestDb(dir));

  test('migrates a v4 database to v5 without losing data', () async {
    // Build a real v4 database the way the old app did.
    final path = DatabaseHelper.pathOverride!;
    final old = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (d, v) async {
            await d.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, '
                'amount REAL NOT NULL, type TEXT NOT NULL, merchant TEXT NOT NULL, '
                'timestamp INTEGER NOT NULL, body TEXT NOT NULL, source TEXT NOT NULL, dedup_key TEXT)');
            await d.execute('CREATE TABLE monthly_balances (id INTEGER PRIMARY KEY AUTOINCREMENT, '
                'month TEXT NOT NULL, opening_balance REAL, closing_balance REAL, '
                'opening_recorded_at TEXT, closing_recorded_at TEXT, is_reconciled INTEGER DEFAULT 0)');
            await d.execute('CREATE UNIQUE INDEX idx_month ON monthly_balances (month)');
          },
        ));
    await old.insert('transactions', {
      'amount': 50.0, 'type': 'DEBIT', 'merchant': 'Tea', 'timestamp': 1,
      'body': 'Manual Entry', 'source': 'MANUAL',
    });
    await old.insert('monthly_balances', {'month': '2026-10', 'opening_balance': 1000.0});
    await old.close();

    final rows = await db.readAllTransactions();
    expect(rows, hasLength(1));
    expect(rows.single.kind, 'NORMAL');
    expect(rows.single.account, isNull);
    expect(DatabaseHelper.needsRescan, isTrue);
    final bal = await db.getMonthlyBalance('2026-10');
    expect(bal!['opening_balance'], 1000.0);
    // Per-account balances now coexist for the same month.
    await db.saveOpeningBalance('2026-10', 500, account: 'A/c XX1234');
    expect((await db.getMonthlyBalance('2026-10', account: 'A/c XX1234'))!['opening_balance'], 500.0);
    expect((await db.getMonthlyBalance('2026-10'))!['opening_balance'], 1000.0);
  });

  test('deleted SMS row is never re-imported', () async {
    final row = txn(key: 'r:1:DEBIT:100.00').toMap()..remove('id');
    final ids = await db.createAllRaw([row]);
    expect(ids, hasLength(1));
    await db.delete(ids.single);
    expect(await db.createAllRaw([row]), isEmpty);
    expect(await db.readAllTransactions(), isEmpty);
  });

  test('duplicate dedup keys collapse; createAllRaw reports only new ids', () async {
    final row = txn(key: 'b:same').toMap()..remove('id');
    expect(await db.createAllRaw([row]), hasLength(1));
    expect(await db.createAllRaw([row, row]), isEmpty);
    expect(await db.readAllTransactions(), hasLength(1));
  });

  test('re-import keeps manual entries', () async {
    await db.create(txn(source: 'MANUAL', merchant: 'Rent'));
    await db.createAllRaw([txn(key: 'k1').toMap()..remove('id')]);
    await db.deleteSmsTransactions();
    final left = await db.readAllTransactions();
    expect(left.map((t) => t.merchant), ['Rent']);
  });

  test('list load omits the SMS body; readBody fetches it', () async {
    final id = await db.create(txn(merchant: 'Zomato'));
    final list = await db.readAllTransactions();
    expect(list.single.body, '');
    expect(await db.readBody(id), 'body of Zomato');
  });

  test('pairs a debit and credit on two own accounts as a transfer', () async {
    final t0 = DateTime(2026, 11, 5, 10);
    final ids = await db.createAllRaw([
      txn(amount: 5000, type: 'DEBIT', account: 'A/c XX1111', at: t0, key: 'a').toMap()..remove('id'),
      txn(amount: 5000, type: 'CREDIT', account: 'A/c XX2222', at: t0.add(const Duration(minutes: 2)), key: 'b').toMap()..remove('id'),
      // Same amount but same account, and one far away in time: not transfers.
      txn(amount: 5000, type: 'CREDIT', account: 'A/c XX1111', at: t0.add(const Duration(minutes: 1)), key: 'c').toMap()..remove('id'),
      txn(amount: 5000, type: 'CREDIT', account: 'A/c XX3333', at: t0.add(const Duration(days: 2)), key: 'd').toMap()..remove('id'),
    ]);
    expect(await db.pairTransfers(ids), 2);
    final kinds = {for (final t in await db.readAllTransactions()) t.dedupKey: t.kind};
    expect(kinds, {'a': 'TRANSFER', 'b': 'TRANSFER', 'c': 'NORMAL', 'd': 'NORMAL'});
  });

  test('combined reconciliation rows exclude card accounts', () async {
    await db.create(txn(amount: 100, account: 'A/c XX1111', at: DateTime(2026, 11, 2)));
    await db.create(txn(amount: 200, account: 'Card XX9999', at: DateTime(2026, 11, 3)));
    await db.create(txn(amount: 300, source: 'MANUAL', at: DateTime(2026, 11, 4)));
    await db.create(txn(amount: 999, account: 'A/c XX1111', at: DateTime(2026, 12, 1)));
    final all = await db.monthRows('2026-11');
    expect(all.map((r) => r['amount']), unorderedEquals([100.0, 300.0]));
    final card = await db.monthRows('2026-11', account: 'Card XX9999');
    expect(card.map((r) => r['amount']), [200.0]);
  });

  test('backup round-trips every table', () async {
    await db.create(txn(merchant: 'Swiggy', category: 'Food & Dining', account: 'A/c XX1'));
    await db.setCategoryRule('uber', 'Transport');
    await db.setBudget('Food & Dining', 5000);
    await db.saveOpeningBalance('2026-11', 1234.5, account: 'A/c XX1');
    final id = await db.create(txn(key: 'gone'));
    await db.delete(id);

    final json = await BackupService.encode();
    await db.restoreAll({for (final t in ['transactions', 'monthly_balances', 'ignored_keys', 'category_rules', 'budgets']) t: []});
    expect(await db.readAllTransactions(), isEmpty);

    await BackupService.restore(json);
    final t = (await db.readAllTransactions()).single;
    expect(t.merchant, 'Swiggy');
    expect(t.category, 'Food & Dining');
    expect(await db.getCategoryRules(), {'uber': 'Transport'});
    expect(await db.getBudgets(), {'Food & Dining': 5000.0});
    expect((await db.getMonthlyBalance('2026-11', account: 'A/c XX1'))!['opening_balance'], 1234.5);
    // The tombstone survived too.
    expect(await db.createAllRaw([txn(key: 'gone').toMap()..remove('id')]), isEmpty);
  });
}
