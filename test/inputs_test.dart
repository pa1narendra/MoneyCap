import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneycap/screens/budgets_screen.dart';
import 'package:moneycap/screens/category_rules_screen.dart';
import 'package:moneycap/services/balance_service.dart';
import 'package:moneycap/services/db_service.dart';
import 'package:moneycap/widgets/input_dialogs.dart';

import 'helpers.dart';

/// Opens [open] from a button so route animations run like in the app. Closing
/// a dialog must not throw: pumpAndSettle fails the test on any framework
/// exception, including a text controller used after being disposed.
Future<void> launch(WidgetTester t, Future<void> Function(BuildContext) open) async {
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: TextButton(onPressed: () => open(ctx), child: const Text('open')),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  group('validateAmount', () {
    test('empty and non-numbers are rejected everywhere', () {
      for (final bad in [null, '', '   ', '.', '-', 'abc']) {
        expect(validateAmount(bad), isNotNull, reason: '"$bad"');
        expect(validateAmount(bad, allowZero: true, allowNegative: true), isNotNull, reason: '"$bad"');
      }
    });

    test('limits need a positive amount; balances may be 0 or negative', () {
      expect(validateAmount('0'), isNotNull);
      expect(validateAmount('-5'), isNotNull);
      expect(validateAmount('12.50'), isNull);
      expect(validateAmount('0', allowZero: true), isNull);
      expect(validateAmount('-5', allowNegative: true), isNull);
      expect(validateAmount('99999999999999'), isNotNull);
    });
  });

  group('amount dialog (balances)', () {
    testWidgets('saving empty shows an error and stays open', (t) async {
      await launch(t, (c) => showAmountDialog(c, title: 'Closing Balance', allowZero: true, allowNegative: true));
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Enter an amount'), findsOneWidget);
      expect(find.text('Closing Balance'), findsOneWidget);
    });

    testWidgets('cancel closes without an error', (t) async {
      await launch(t, (c) => showAmountDialog(c, title: 'Opening Balance'));
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('Opening Balance'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('a valid value is returned, including 0', (t) async {
      double? got;
      await launch(t, (c) async => got = await showAmountDialog(c, title: 'B', allowZero: true));
      await t.enterText(find.byType(TextFormField), '0');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(got, 0);
      expect(t.takeException(), isNull);
    });

    testWidgets('letters can\'t be typed into a money field', (t) async {
      await launch(t, (c) => showAmountDialog(c, title: 'B'));
      await t.enterText(find.byType(TextFormField), 'abc');
      await t.pump();
      expect(find.text('abc'), findsNothing);
    });
  });

  group('budget dialog', () {
    testWidgets('saving with no limit shows an error and stays open', (t) async {
      await launch(t, (c) => showDialog<Object>(context: c, builder: (_) => const BudgetDialog()));
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Enter an amount'), findsOneWidget);
      expect(find.text('New budget'), findsOneWidget);
    });

    testWidgets('a zero limit is rejected', (t) async {
      await launch(t, (c) => showDialog<Object>(context: c, builder: (_) => const BudgetDialog()));
      await t.enterText(find.byType(TextFormField), '0');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Enter an amount above 0'), findsOneWidget);
    });

    testWidgets('cancel closes without an error', (t) async {
      await launch(t, (c) => showDialog<Object>(context: c, builder: (_) => const BudgetDialog()));
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('New budget'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('a category outside the expense list doesn\'t crash', (t) async {
      await launch(t, (c) => showDialog<Object>(
          context: c, builder: (_) => const BudgetDialog(category: 'Income')));
      expect(find.text('Income'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('rule dialog', () {
    testWidgets('empty and one-letter rules are rejected', (t) async {
      await launch(t, (c) => showDialog<Object>(context: c, builder: (_) => const RuleDialog()));
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Enter part of a merchant name'), findsOneWidget);
      await t.enterText(find.byType(TextFormField), 'a');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Use at least 2 characters'), findsOneWidget);
    });

    testWidgets('cancel closes without an error', (t) async {
      await launch(t, (c) => showDialog<Object>(context: c, builder: (_) => const RuleDialog()));
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('name dialog allows empty, since a name is optional', (t) async {
    String? got;
    await launch(t, (c) async => got = await showTextDialog(c, title: 'Your name', initial: 'Alex'));
    await t.enterText(find.byType(TextFormField), '   ');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(got, '');
    expect(t.takeException(), isNull);
  });

  group('separate banks', () {
    late Directory dir;
    final db = DatabaseHelper.instance;
    setUp(() async => dir = await setUpTestDb());
    tearDown(() async => tearDownTestDb(dir));

    test('each bank reconciles on its own, debit card included, credit card not', () async {
      final at = DateTime(2026, 11, 3);
      await db.create(txn(amount: 100, account: 'HDFC A/c XX1111', at: at));
      await db.create(txn(amount: 50, account: 'HDFC Debit XX5555', at: at));
      await db.create(txn(amount: 300, account: 'SBI A/c XX2222', at: at));
      await db.create(txn(amount: 900, account: 'HDFC Card XX9921', at: at));
      await db.create(txn(amount: 25, account: 'PhonePe Wallet', at: at));
      List<num> of(List<Map<String, Object?>> r) => r.map((e) => e['amount'] as num).toList();
      expect(of(await db.monthRows('2026-11', account: 'HDFC A/c XX1111')), unorderedEquals([100, 50]));
      expect(of(await db.monthRows('2026-11', account: 'SBI A/c XX2222')), [300]);
      expect(of(await db.monthRows('2026-11')), unorderedEquals([100, 50, 300]));

      final s = BalanceService();
      await db.saveOpeningBalance('2026-11', 1000, account: 'HDFC A/c XX1111');
      await db.saveClosingBalance('2026-11', 850, account: 'HDFC A/c XX1111');
      await db.saveOpeningBalance('2026-11', 5000, account: 'SBI A/c XX2222');
      await db.saveClosingBalance('2026-11', 4000, account: 'SBI A/c XX2222');
      expect((await s.getDiscrepancy('2026-11', account: 'HDFC A/c XX1111'))!.discrepancy, 0);
      expect((await s.getDiscrepancy('2026-11', account: 'SBI A/c XX2222'))!.discrepancy, -700);
    });

    test('the monthly prompt asks about each bank in turn', () async {
      final at = DateTime(2026, 11, 2);
      await db.create(txn(account: 'HDFC A/c XX1111', at: at));
      await db.create(txn(account: 'HDFC A/c XX1111', at: at.add(const Duration(hours: 1))));
      await db.create(txn(account: 'SBI A/c XX2222', at: at));
      await db.create(txn(account: 'HDFC Card XX9921', at: at));
      final s = BalanceService();
      final first = await s.checkBalancePrompt(at: at);
      expect(first!.account, 'HDFC A/c XX1111');
      expect(first.type, PromptType.opening);
      await db.saveOpeningBalance('2026-11', 10, account: first.account);
      expect((await s.checkBalancePrompt(at: at))!.account, 'SBI A/c XX2222');
      // Skipping a bank moves on instead of asking again.
      expect(await s.checkBalancePrompt(at: at, skip: {'SBI A/c XX2222'}), isNull);
      // Nothing is asked mid-month.
      expect(await s.checkBalancePrompt(at: DateTime(2026, 11, 15)), isNull);
    });
  });
}
