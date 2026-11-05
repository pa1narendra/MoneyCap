import 'package:flutter_test/flutter_test.dart';
import 'package:moneycap/services/parser_service.dart';

import 'fixtures/sms_fixtures.dart';

void main() {
  final parser = ParserService();
  final when = DateTime(2026, 11, 5, 12);

  group('SMS fixtures', () {
    for (final f in fixtures) {
      test(f.name, () {
        final t = parser.parseFields(f.body, f.sender, when);
        final e = f.expect;
        if (e == null) {
          expect(t, isNull, reason: 'should be ignored but parsed as ${t?.type} ${t?.amount}');
          return;
        }
        expect(t, isNotNull, reason: 'should be a transaction');
        expect(t!.type, e.type, reason: 'type');
        expect(t.amount, e.amount, reason: 'amount');
        expect(t.kind, e.kind, reason: 'kind');
        if (e.merchant != null) expect(t.merchant, e.merchant, reason: 'merchant');
        if (e.account != null) expect(t.account, endsWith(e.account!), reason: 'account');
      });
    }
  });

  test('refund and purchase with the same ref get different dedup keys', () {
    final a = parser.parseFields(
        'Rs 899 debited from A/c XX1234 to Amazon. UPI Ref 412345678901', 'AD-HDFCBK', when);
    final b = parser.parseFields(
        'Rs 899 refund credited to A/c XX1234 from Amazon. UPI Ref 412345678901', 'AD-HDFCBK', when);
    expect(a!.type, 'DEBIT');
    expect(b!.type, 'CREDIT');
    expect(a.dedupKey, isNot(b.dedupKey));
  });

  test('re-delivered SMS gets the same dedup key', () {
    const body = 'Rs 200 debited from a/c XX1234 UPI Ref 123456789012';
    final a = parser.parseFields(body, 'AD-HDFCBK', when);
    final b = parser.parseFields(body, 'VM-HDFCBK', when);
    expect(a!.dedupKey, b!.dedupKey);
  });

  test('merchant names are never cut inside a word', () {
    for (final f in fixtures) {
      final t = parser.parseFields(f.body, f.sender, when);
      if (t == null || t.merchant == 'Unknown') continue;
      // The merchant must appear in the body as whole words.
      final re = RegExp('(^|[^A-Za-z0-9])${RegExp.escape(t.merchant)}(\$|[^A-Za-z0-9])',
          caseSensitive: false);
      expect(re.hasMatch(f.body), isTrue, reason: '${f.name}: "${t.merchant}"');
    }
  });

  test('sender gate', () {
    expect(ParserService.isBankLikeSender('AD-HDFCBK'), isTrue);
    expect(ParserService.isBankLikeSender('JD-SBIUPI-S'), isTrue);
    expect(ParserService.isBankLikeSender('HDFCBK'), isTrue);
    expect(ParserService.isBankLikeSender('AD-HDFCBK-P'), isFalse);
    expect(ParserService.isBankLikeSender('+919876543210'), isFalse);
    expect(ParserService.isBankLikeSender('56767'), isFalse);
    expect(ParserService.isBankLikeSender(null), isFalse);
  });
}
