import 'package:flutter_test/flutter_test.dart';
import 'package:moneycap/services/parser_service.dart';

void main() {
  final parser = ParserService();

  test('credit-card bill payment ("credited to your card") is DEBIT', () {
    final t = parser.parseFields(
      'HDFC Bank Cardmember, Payment of Rs 96475.04 was credited to your card ending 0853 on09/JUL/2026',
      'HDFCBK',
      DateTime(2026, 7, 9),
    );
    expect(t, isNotNull);
    expect(t!.type, 'DEBIT');
    expect(t.amount, 96475.04);
  });

  test('credit-card payment ("received towards your card") is DEBIT', () {
    final t = parser.parseFields(
      'Payment of Rs 5000 received towards your Credit Card ending 1234',
      'ICICI',
      DateTime.now(),
    );
    expect(t!.type, 'DEBIT');
  });

  test('card refund stays CREDIT', () {
    final t = parser.parseFields(
      'Rs 500 refund credited to your card ending 0853',
      'HDFCBK',
      DateTime.now(),
    );
    expect(t!.type, 'CREDIT');
  });

  test('card cashback stays CREDIT', () {
    final t = parser.parseFields(
      'Rs 50 cashback credited to your card ending 0853',
      'HDFCBK',
      DateTime.now(),
    );
    expect(t!.type, 'CREDIT');
  });

  test('normal debit (spent) is DEBIT', () {
    final t = parser.parseFields(
      'Rs 200 spent on your card at Amazon',
      'HDFCBK',
      DateTime.now(),
    );
    expect(t!.type, 'DEBIT');
  });

  test('normal credit (salary) is CREDIT', () {
    final t = parser.parseFields(
      'Rs 50000 credited to your a/c XX towards salary',
      'HDFCBK',
      DateTime.now(),
    );
    expect(t!.type, 'CREDIT');
  });

  test('SMS transactions get a dedup key', () {
    final t = parser.parseFields(
      'Rs 200 debited from a/c XX UPI Ref 123456789012',
      'HDFCBK',
      DateTime.now(),
    );
    expect(t!.dedupKey, isNotNull);
    expect(t.dedupKey!.startsWith('r:'), isTrue); // used the reference number
  });
}
