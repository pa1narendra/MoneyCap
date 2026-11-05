import 'package:flutter_test/flutter_test.dart';
import 'package:moneycap/services/backup_service.dart';
import 'package:moneycap/services/balance_service.dart';
import 'package:moneycap/services/category_service.dart';
import 'package:moneycap/services/insights_service.dart';

import 'helpers.dart';

void main() {
  group('categories', () {
    test('built-in keywords', () {
      expect(Categories.resolve(txn(merchant: 'SWIGGY'), {}), Categories.food);
      expect(Categories.resolve(txn(merchant: 'UBER INDIA'), {}), Categories.transport);
      expect(Categories.resolve(txn(merchant: 'Some Kirana'), {}), Categories.groceries);
      expect(Categories.resolve(txn(merchant: 'ATM S1AW000123'), {}), Categories.cash);
    });

    test('short keywords need a whole word ("ola" is not "Motorola")', () {
      expect(Categories.resolve(txn(merchant: 'Motorola Store'), {}), isNot(Categories.transport));
      expect(Categories.resolve(txn(merchant: 'OLA CABS'), {}), Categories.transport);
    });

    test('user rule beats built-in; override beats rule', () {
      final rules = {'swiggy': Categories.groceries};
      expect(Categories.resolve(txn(merchant: 'Swiggy Instamart'), rules), Categories.groceries);
      expect(Categories.resolve(txn(merchant: 'Swiggy', category: Categories.travel), rules),
          Categories.travel);
    });

    test('transfers and credits get their own buckets', () {
      expect(Categories.resolve(txn(kind: 'TRANSFER'), {}), Categories.transfers);
      expect(Categories.resolve(txn(type: 'CREDIT', merchant: 'ACME'), {}), Categories.income);
    });
  });

  group('recurring', () {
    test('detects a monthly subscription', () {
      final list = [
        for (var m = 6; m <= 10; m++) txn(merchant: 'NETFLIX', amount: 649, at: DateTime(2026, m, 3)),
        txn(merchant: 'Netflix', amount: 649, at: DateTime(2026, 11, 3)),
      ];
      final r = Insights.detectRecurring(list);
      expect(r, hasLength(1));
      expect(r.single.cadence, Cadence.monthly);
      expect(r.single.typicalAmount, 649);
      expect(r.single.nextExpected, DateTime(2026, 12, 3));
    });

    test('ignores irregular spending at the same merchant', () {
      final list = [
        txn(merchant: 'Amazon', amount: 300, at: DateTime(2026, 9, 1)),
        txn(merchant: 'Amazon', amount: 4500, at: DateTime(2026, 9, 4)),
        txn(merchant: 'Amazon', amount: 120, at: DateTime(2026, 10, 20)),
      ];
      expect(Insights.detectRecurring(list), isEmpty);
    });

    test('transfers are not subscriptions', () {
      final list = [
        for (var m = 7; m <= 10; m++)
          txn(merchant: 'Self', amount: 10000, kind: 'TRANSFER', at: DateTime(2026, m, 1)),
      ];
      expect(Insights.detectRecurring(list), isEmpty);
    });

    test('Jan 31 monthly payment is next expected at end of Feb', () {
      final list = [
        txn(merchant: 'Gym', amount: 1500, at: DateTime(2026, 11, 30)),
        txn(merchant: 'Gym', amount: 1500, at: DateTime(2026, 12, 31)),
        txn(merchant: 'Gym', amount: 1500, at: DateTime(2027, 1, 31)),
      ];
      expect(Insights.detectRecurring(list).single.nextExpected, DateTime(2027, 2, 28));
    });
  });

  test('budget status sums only this month\'s expenses', () {
    final list = [
      txn(merchant: 'Swiggy', amount: 900, at: DateTime(2026, 11, 2)),
      txn(merchant: 'Zomato', amount: 300, at: DateTime(2026, 11, 3)),
      txn(merchant: 'Swiggy', amount: 999, at: DateTime(2026, 10, 3)), // last month
      txn(merchant: 'Swiggy', amount: 50, type: 'CREDIT', at: DateTime(2026, 11, 4)), // refund
    ];
    final spent = Insights.spendByCategory(list, {}, month: DateTime(2026, 11));
    final s = Insights.budgetStatus({Categories.food: 1000}, spent).single;
    expect(s.spent, 1200);
    expect(s.over, isTrue);
  });

  group('untrusted input', () {
    test('backup with an unknown column is reduced to known columns', () {
      final t = BackupService.decode('{"format":"moneycap-backup","schema":5,"tables":{"transactions":[{'
          '"amount":1.5,"type":"DEBIT","merchant":"x","timestamp":1,"body":"b","source":"SMS",'
          '"amount) VALUES (1); DROP TABLE budgets; --":1}]}}');
      expect(t['transactions']!.single.keys,
          unorderedEquals(['amount', 'type', 'merchant', 'timestamp', 'body', 'source', 'kind']));
    });

    test('backup rejects wrong types, other files and newer schemas', () {
      expect(() => BackupService.decode('not json'), throwsA(isA<BackupException>()));
      expect(() => BackupService.decode('{"hello":1}'), throwsA(isA<BackupException>()));
      expect(() => BackupService.decode('{"format":"moneycap-backup","schema":99,"tables":{}}'),
          throwsA(isA<BackupException>()));
      expect(
          () => BackupService.decode('{"format":"moneycap-backup","schema":5,"tables":{"budgets":'
              '[{"category":"Food","monthly_limit":"lots"}]}}'),
          throwsA(isA<BackupException>()));
    });

    test('notification payloads are validated', () {
      expect(BalancePrompt.fromPayload('closing:2026-11')!.type, PromptType.closing);
      expect(BalancePrompt.fromPayload('opening:2026-13'), isNull);
      expect(BalancePrompt.fromPayload('opening:garbage'), isNull);
      expect(BalancePrompt.fromPayload(''), isNull);
    });
  });
}
