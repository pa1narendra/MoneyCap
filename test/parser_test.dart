import 'package:flutter_test/flutter_test.dart';
import 'package:moneycap/services/parser_service.dart';

void main() {
  final parser = ParserService();

  // --- Credit-card bill payment classification ---

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

  // --- Promotional / informational filtering ---

  test('EMI-conversion offer is NOT a transaction', () {
    final t = parser.parseFields(
      'Convert spends of Rs.15610 on HDFC Bank Credit Card xx0853 to simple monthly EMIs via PayZapp. Check details http://hdfc.bank/x T&C',
      'HDFCBK',
      DateTime.now(),
    );
    expect(t, isNull);
  });

  test('smart-EMI offer is NOT a transaction', () {
    final t = parser.parseFields(
      'Convert your spends of Rs.24999 on HDFC Bank Credit Card xx0853 to smart EMI. T&C apply',
      'HDFCBK',
      DateTime.now(),
    );
    expect(t, isNull);
  });

  test('HURRY / % off promo is NOT a transaction', () {
    final t = parser.parseFields(
      'HURRY! Flat 30% off up to Rs 2000 on your HDFC Card at Myntra. Shop now',
      'HDFCBK',
      DateTime.now(),
    );
    expect(t, isNull);
  });

  test('promo that also contains a txn keyword ("spent") is still ignored', () {
    final t = parser.parseFields(
      'You spent Rs 15610 on your HDFC Card. Convert to easy EMI now! T&C apply',
      'HDFCBK',
      DateTime.now(),
    );
    expect(t, isNull);
  });

  // --- Real transactions must still parse ---

  test('genuine EMI installment debit IS recorded (DEBIT)', () {
    final t = parser.parseFields(
      'Rs 5000 EMI debited from a/c XX1234 towards HDFC loan. Ref 998877',
      'HDFCBK',
      DateTime.now(),
    );
    expect(t, isNotNull);
    expect(t!.type, 'DEBIT');
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
    expect(t.dedupKey!.startsWith('r:'), isTrue);
  });

  test('"Congratulations! New Benefit added on your card" is ignored', () {
    final t = parser.parseFields(
      'Congratulations! New Benefit is added on your HDFC Bank Credit Card xx0853. Enjoy!',
      'HDFCBK',
      DateTime.now(),
    );
    expect(t, isNull);
  });

  test('pre-approved loan offer with @rate is ignored', () {
    final t = parser.parseFields(
      'Congratulations! You have a pre-approved personal loan of Rs 500000 @10.5% p.a. Avail now!',
      'HDFCBK',
      DateTime.now(),
    );
    expect(t, isNull);
  });

  test('genuine loan EMI debit IS recorded (bare "loan" not filtered)', () {
    final t = parser.parseFields(
      'Rs 5000 loan EMI debited from a/c XX1234. Ref 445566',
      'HDFCBK',
      DateTime.now(),
    );
    expect(t, isNotNull);
    expect(t!.type, 'DEBIT');
  });

  test('savings interest credit IS recorded (no @rate)', () {
    final t = parser.parseFields(
      'Rs 250 interest credited to your savings account XX1234',
      'HDFCBK',
      DateTime.now(),
    );
    expect(t, isNotNull);
    expect(t!.type, 'CREDIT');
  });
}
