import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneycap/providers/transaction_provider.dart';
import 'package:moneycap/services/backup_service.dart';
import 'package:moneycap/services/db_service.dart';
import 'package:moneycap/services/sms_service.dart';
import 'package:moneycap/widgets/backup_reminder.dart';
import 'package:moneycap/widgets/input_dialogs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('names', () {
    late Directory dir;
    final db = DatabaseHelper.instance;
    setUp(() async => dir = await setUpTestDb());
    tearDown(() async => tearDownTestDb(dir));

    Future<TransactionProvider> load(List<Future<int>> inserts) async {
      await Future.wait(inserts);
      final p = TransactionProvider(loadPrefs: false)..setFilter(TimeFilter.all);
      await p.setMerchantName(txn(merchant: 'nobody yet'), '', isSelf: false); // loads names
      await p.loadTransactions();
      return p;
    }

    test('a name shows on every payment from that UPI ID, and the SMS text is kept', () async {
      final p = await load([
        db.create(txn(merchant: '*9795@superyes', type: 'CREDIT', key: 'a')),
        db.create(txn(merchant: '*9795@superyes', type: 'CREDIT', key: 'b', at: DateTime(2026, 10, 2))),
        db.create(txn(merchant: '*7585@axl', type: 'CREDIT', key: 'c')),
      ]);
      await p.setMerchantName(p.transactions.firstWhere((t) => t.merchant == '*9795@superyes'), 'Ravi', isSelf: false);
      expect(p.transactions.where((t) => t.merchant == 'Ravi'), hasLength(2));
      expect(p.transactions.where((t) => t.merchant == '*7585@axl'), hasLength(1));
      final ravi = p.transactions.firstWhere((t) => t.merchant == 'Ravi');
      expect(ravi.originalMerchant, '*9795@superyes');
      expect(p.isSelf(ravi), isFalse);
      expect(p.totalIncome, 300); // a name doesn't change what's counted

      // Searching by the SMS text still finds it.
      p.setSearchQuery('superyes');
      expect(p.filteredTransactions, hasLength(2));
    });

    test('editing a named row keeps the SMS text on the row', () async {
      final p = await load([db.create(txn(merchant: '*9795@superyes', key: 'a'))]);
      await p.setMerchantName(p.transactions.single, 'Ravi', isSelf: false);
      await p.updateTransaction(p.transactions.single.copyWith(amount: 55));
      final raw = await (await db.database).query('transactions');
      expect(raw.single['merchant'], '*9795@superyes');
      expect(p.transactions.single.merchant, 'Ravi');
      expect(p.transactions.single.amount, 55);
    });

    test('removing a name puts the SMS text back', () async {
      final p = await load([db.create(txn(merchant: '*9795@superyes', key: 'a'))]);
      await p.setMerchantName(p.transactions.single, 'Ravi', isSelf: false);
      await p.setMerchantName(p.transactions.single, '', isSelf: false);
      expect(p.transactions.single.merchant, '*9795@superyes');
      expect(p.transactions.single.originalMerchant, isNull);
    });

    test('"This is me" turns both directions into transfers, and undoing it restores them', () async {
      final p = await load([
        db.create(txn(merchant: 'MY NAME', amount: 60000, key: 'out')),
        db.create(txn(merchant: 'My Name', amount: 500, key: 'out2')),
        db.create(txn(merchant: 'Shop', amount: 100, key: 'shop')),
      ]);
      expect(p.totalExpense, 60600);
      await p.setMerchantName(p.transactions.firstWhere((t) => t.amount == 60000), 'Me', isSelf: true);
      expect(p.totalExpense, 100);
      expect(p.transactions.where((t) => t.isTransfer), hasLength(2));
      await p.setMerchantName(p.transactions.firstWhere((t) => t.amount == 60000), '', isSelf: false);
      expect(p.totalExpense, 60600);
    });

    test('new SMS from your own account are transfers; a row you changed stays changed', () async {
      await db.setMerchantName('MY NAME', '', isSelf: true);
      final ids = await db.createAllRaw([txn(merchant: 'MY NAME', key: 'new').toMap()..remove('id')]);
      await db.applySelfRules(ids);
      final row = (await db.readAllTransactions()).single;
      expect(row.isTransfer, isTrue);
      await db.update(row.copyWith(kind: 'NORMAL'));
      await db.applySelfRules([]);
      expect((await db.readAllTransactions()).single.isTransfer, isFalse);
    });

    test('made-up labels and empty names can\'t be named', () async {
      final p = TransactionProvider(loadPrefs: false);
      for (final m in ['Unknown', 'Refund', 'Reversal', 'Salary', 'Credit card bill']) {
        expect(p.canName(txn(merchant: m)), isFalse, reason: m);
      }
      expect(p.canName(txn(merchant: '*9795@superyes')), isTrue);
      expect(p.canName(txn(merchant: 'Rent', source: 'MANUAL')), isFalse);
    });

    test('names survive backup and restore', () async {
      await db.setMerchantName('*9795@superyes', 'Ravi', isSelf: false);
      await db.setMerchantName('MY NAME', '', isSelf: true);
      final json = await BackupService.encode();
      await db.restoreAll({'merchant_names': const []});
      expect(await db.getMerchantNames(), isEmpty);
      await BackupService.restore(json);
      final names = await db.getMerchantNames();
      expect(names['*9795@superyes']?.name, 'Ravi');
      expect(names['my name']?.isSelf, isTrue);
    });

    test('updating from 3.0.0 (schema 5) adds names and asks to rebuild its wrong rows', () async {
      await db.create(txn(merchant: 'Shop', key: 'k'));
      final raw = await db.database;
      await raw.execute('DROP TABLE merchant_names');
      await raw.setVersion(5);
      await DatabaseHelper.resetForTest();
      expect(await db.readAllTransactions(), hasLength(1));
      expect(await db.getMerchantNames(), isEmpty);
      expect(await SmsService.isRescanPending(), isTrue);
    });

    test('a current database does not rebuild', () async {
      await db.create(txn(merchant: 'Shop', key: 'k'));
      await DatabaseHelper.resetForTest();
      await db.readAllTransactions();
      expect(await SmsService.isRescanPending(), isFalse);
    });

    test('balances and manual rows on 3.0.0 labels move to the bank label', () async {
      await db.create(txn(account: 'HDFC A/c XX1111', key: 'sms'));
      await db.create(txn(account: 'A/c XX1111', source: 'MANUAL', merchant: 'Cash'));
      await db.saveOpeningBalance('2026-10', 500, account: 'A/c XX1111');
      await db.saveOpeningBalance('2026-11', 700, account: 'A/c XX1111');
      await db.saveOpeningBalance('2026-11', 900, account: 'HDFC A/c XX1111');
      // No SMS rows for this one, so there's no bank to move it to.
      await db.saveOpeningBalance('2026-11', 50, account: 'A/c XX9999');
      await db.relinkOldAccountLabels();
      expect((await db.getMonthlyBalance('2026-10', account: 'HDFC A/c XX1111'))!['opening_balance'], 500.0);
      // A balance already on the new label wins, and nothing is lost silently.
      expect((await db.getMonthlyBalance('2026-11', account: 'HDFC A/c XX1111'))!['opening_balance'], 900.0);
      expect((await db.getMonthlyBalance('2026-11', account: 'A/c XX9999'))!['opening_balance'], 50.0);
      final rows = await db.readAllTransactions();
      expect(rows.map((r) => r.account), everyElement('HDFC A/c XX1111'));
    });

    test('a last-4 shared by two banks is left alone', () async {
      await db.create(txn(account: 'HDFC A/c XX1111', key: 'a'));
      await db.create(txn(account: 'SBI A/c XX1111', key: 'b'));
      await db.saveOpeningBalance('2026-11', 500, account: 'A/c XX1111');
      await db.relinkOldAccountLabels();
      expect((await db.getMonthlyBalance('2026-11', account: 'A/c XX1111'))!['opening_balance'], 500.0);
    });

    test('an update from v4 asks once before rebuilding SMS rows', () async {
      await DatabaseHelper.resetForTest();
      DatabaseHelper.needsRescan = true;
      expect(await SmsService.isRescanPending(), isTrue);
      await SmsService.confirmRescan();
      expect(await SmsService.isRescanPending(), isFalse);
    });
  });

  group('dialogs', () {
    Future<void> launch(WidgetTester t, Future<void> Function(BuildContext) open) async {
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(body: TextButton(onPressed: () => open(ctx), child: const Text('open'))),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    Future<bool> Function() noBackup() => () async => true;

    testWidgets('backup reminder never forces a backup', (t) async {
      bool? go;
      var backups = 0;
      await launch(t, (c) async => go = await confirmWithBackupReminder(c, null,
          title: 'Sure?', message: 'm', confirmLabel: 'Re-import', onBackup: () async {
        backups++;
        return true;
      }));
      await t.tap(find.text('Re-import'));
      await t.pumpAndSettle();
      expect(go, isTrue);
      expect(backups, 0);
    });

    testWidgets('backing up comes back to the choice, marked done', (t) async {
      bool? go;
      await launch(t, (c) async => go = await confirmWithBackupReminder(c, null,
          title: 'Sure?', message: 'm', confirmLabel: 'Re-import', onBackup: noBackup()));
      await t.tap(find.text('Back up first'));
      await t.pumpAndSettle();
      expect(find.textContaining('Backup created'), findsOneWidget);
      expect(go, isNull);
      await t.tap(find.text('Re-import'));
      await t.pumpAndSettle();
      expect(go, isTrue);
    });

    testWidgets('cancel stops the action', (t) async {
      bool? go;
      await launch(t, (c) async => go = await confirmWithBackupReminder(c, null,
          title: 'Sure?', message: 'm', confirmLabel: 'Re-import', onBackup: noBackup()));
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(go, isFalse);
    });

    testWidgets('a failed backup doesn\'t claim it worked', (t) async {
      await launch(t, (c) => confirmWithBackupReminder(c, null,
          title: 'Sure?', message: 'm', confirmLabel: 'Go', onBackup: () async => false));
      await t.tap(find.text('Back up first'));
      await t.pumpAndSettle();
      expect(find.textContaining('Backup created'), findsNothing);
      expect(find.text('Back up first'), findsOneWidget);
    });

    testWidgets('name dialog returns the name and "This is me", and closes cleanly', (t) async {
      (String, bool)? got;
      await launch(t, (c) async => got = await showDialog<(String, bool)>(
          context: c, builder: (_) => const NameDialog(smsName: '*9795@superyes')));
      await t.enterText(find.byType(TextField), '  Ravi ');
      await t.tap(find.text('This is me'));
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(got, ('Ravi', true));
      expect(t.takeException(), isNull);
    });
  });
}
