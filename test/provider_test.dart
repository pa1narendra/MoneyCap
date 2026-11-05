import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneycap/providers/transaction_provider.dart';
import 'package:moneycap/services/db_service.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final db = DatabaseHelper.instance;

  setUp(() async => dir = await setUpTestDb());
  tearDown(() async => tearDownTestDb(dir));

  Future<TransactionProvider> providerWith(List<Future<int>> inserts) async {
    await Future.wait(inserts);
    final p = TransactionProvider(loadPrefs: false)..setFilter(TimeFilter.all);
    await p.loadTransactions();
    return p;
  }

  test('totals exclude transfers; list toggle hides them from income/expense', () async {
    final p = await providerWith([
      db.create(txn(amount: 1000, type: 'CREDIT', merchant: 'Salary')),
      db.create(txn(amount: 200, merchant: 'Swiggy')),
      db.create(txn(amount: 5000, kind: 'TRANSFER', merchant: 'Card bill')),
      db.create(txn(amount: 5000, type: 'CREDIT', kind: 'TRANSFER', merchant: 'From savings')),
    ]);
    expect(p.totalIncome, 1000);
    expect(p.totalExpense, 200);
    p.setTypeFilter(TypeFilter.expense);
    expect(p.filteredTransactions.map((t) => t.merchant), ['Swiggy']);
    p.setTypeFilter(TypeFilter.all);
    expect(p.filteredTransactions, hasLength(4));
  });

  test('account filter and search (incl. category) narrow the view', () async {
    final p = await providerWith([
      db.create(txn(merchant: 'Swiggy', account: 'A/c XX1111')),
      db.create(txn(merchant: 'Uber', account: 'Card XX2222')),
    ]);
    expect(p.accounts, unorderedEquals(['A/c XX1111', 'Card XX2222']));
    p.setAccountFilter('Card XX2222');
    expect(p.filteredTransactions.single.merchant, 'Uber');
    p.setAccountFilter(null);
    p.setSearchQuery('food');
    expect(p.filteredTransactions.single.merchant, 'Swiggy');
  });

  test('CSV neutralises formula injection and quotes text', () async {
    final p = await providerWith([
      db.create(txn(merchant: '=HYPERLINK("http://evil","x")', source: 'MANUAL')),
      db.create(txn(merchant: 'Ravi, "the" plumber', source: 'MANUAL')),
    ]);
    final csv = p.buildCsv();
    expect(csv, contains('"\'=HYPERLINK(""http://evil"",""x"")"'));
    expect(csv, contains('"Ravi, ""the"" plumber"'));
    expect(csv.split('\n').first, 'Date,Type,Kind,Category,Merchant,Account,Amount,Source');
  });

  test('category rule applies to all transactions from a merchant', () async {
    final p = await providerWith([
      db.create(txn(merchant: 'Krishna Stores')),
      db.create(txn(merchant: 'KRISHNA STORES', at: DateTime(2026, 11, 6))),
    ]);
    await p.setCategory(p.transactions.first, 'Health', applyToMerchant: true);
    expect(p.transactions.map(p.categoryOf), ['Health', 'Health']);
  });

  test('re-import keeps manual entries', () async {
    final p = await providerWith([
      db.create(txn(merchant: 'Rent', source: 'MANUAL')),
      db.create(txn(merchant: 'Swiggy', key: 'k')),
    ]);
    await p.resetSmsData(); // no SMS permission in tests: nothing is re-imported
    expect(p.transactions.map((t) => t.merchant), ['Rent']);
  });
}
