import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneycap/services/db_service.dart';
import 'package:moneycap/services/parser_service.dart';

import 'helpers.dart';

/// Parses SMS the way a sync does, then runs duplicate resolution.
Future<void> importSms(List<(String, String, DateTime)> sms) async {
  final parser = ParserService();
  final maps = [
    for (final s in sms)
      if (parser.parseFields(s.$2, s.$1, s.$3) case final t?) t.toMap()..remove('id'),
  ];
  final db = DatabaseHelper.instance;
  final ids = await db.createAllRaw(maps);
  await db.resolveDuplicates(ids);
  await db.pairTransfers(ids);
}

void main() {
  late Directory dir;
  final db = DatabaseHelper.instance;
  setUp(() async => dir = await setUpTestDb());
  tearDown(() async => tearDownTestDb(dir));
  final t0 = DateTime(2026, 11, 6, 2, 29);

  const bankBill =
      'Sent Rs.35874.00 From HDFC Bank A/C *4444 To HDFC Bank Credit Card Bil On 06/11/26 Ref 123456789018 Not You? Call 18002586161';
  const cardBill =
      'DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 35874.00 RECEIVED TOWARDS YOUR CREDIT CARD ENDING WITH 9921 ON 6-11-2026.YOUR AVAILABLE LIMIT IS RS. 100000.46';

  test('one card bill payment reported by bank and card is one row, not an expense', () async {
    await importSms([
      ('AD-HDFCBK-T', bankBill, t0),
      ('AD-HDFCBK-S', cardBill, t0.add(const Duration(seconds: 1))),
    ]);
    final rows = await db.readAllTransactions();
    expect(rows, hasLength(1));
    expect(rows.single.account, 'HDFC A/c XX4444');
    expect(rows.single.isTransfer, isTrue);
    expect(rows.single.isExpense, isFalse);
    expect(await db.readHiddenDuplicates(), hasLength(1));
  });

  test('card bill paid through an app: bank row becomes the transfer', () async {
    await importSms([
      ('AD-HDFCBK', 'Sent Rs.1031.00 From HDFC Bank A/C *4444 To CRED On 10/05/26 Ref 123456789020 Not You? Call 18002586161', t0),
      ('AD-HDFCBK', 'DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 1031.00 RECEIVED TOWARDS YOUR CREDIT CARD ENDING WITH 9921 ON 10-5-2026.', t0.add(const Duration(seconds: 26))),
      ('AD-HDFCBK', 'HDFC Bank Cardmember, Online Payment of Rs.1031 vide Ref# 093BB59S003H826 was credited to your card ending 9921 On 10/MAY/2026', t0.add(const Duration(hours: 20))),
    ]);
    final rows = await db.readAllTransactions();
    expect(rows.map((r) => r.merchant), ['CRED']);
    expect(rows.single.isTransfer, isTrue);
    expect(await db.readHiddenDuplicates(), hasLength(2));
  });

  test('card bill paid from a bank without SMS keeps the card-side row', () async {
    await importSms([('AD-HDFCBK', cardBill, t0)]);
    expect((await db.readAllTransactions()).single.isTransfer, isTrue);
  });

  test('an unrelated same-amount expense far from a card bill stays an expense', () async {
    await importSms([
      ('AD-HDFCBK', 'Sent Rs.35874.00 From HDFC Bank A/C *4444 To SOME LANDLORD On 04/11/26 Ref 123456789021 Not You? Call 18002586161', t0.subtract(const Duration(hours: 40))),
      ('AD-HDFCBK', cardBill, t0),
    ]);
    final rows = await db.readAllTransactions();
    expect(rows, hasLength(2));
    expect(rows.firstWhere((r) => r.merchant == 'SOME LANDLORD').isExpense, isTrue);
  });

  test('same SMS re-delivered with the same reference is one row', () async {
    const sms = 'Dear SBI User, your A/c X1111-debited by Rs20.0 on 20Jul22 transfer to A SHOP Ref No 123456789022. If not done by u, fwd this SMS';
    await importSms([
      ('AD-SBIUPI', sms, t0),
      ('VM-SBIUPI', sms, t0.add(const Duration(hours: 2))),
    ]);
    expect(await db.readAllTransactions(), hasLength(1));
  });

  test('two real payments with different references are BOTH kept', () async {
    String sms(String ref) =>
        'Dear SBI User, your A/c X1111-debited by Rs30.0 on 04Dec22 transfer to A CANTEEN Ref No $ref. If not done by u, fwd this SMS';
    await importSms([
      ('AD-SBIUPI', sms('123456789023'), t0),
      ('AD-SBIUPI', sms('123456789024'), t0.add(const Duration(seconds: 11))),
    ]);
    expect(await db.readAllTransactions(), hasLength(2));
    expect(await db.readHiddenDuplicates(), isEmpty);
  });

  test('bank charge reported by two SBI systems is one row, keeping the detailed one', () async {
    await importSms([
      ('AD-SBIBNK', 'Dear Customer, Your A/C ending with 2222 has been debited for INR 147.5 on 16-12-23 towards annual maintenance charges for your SBI Debit Card ending with 3040', t0),
      ('AD-CBSSBI', 'Dear Customer, Your A/C XXXXX222222 has a debit by transfer of Rs 147.50 on 16/12/23. Avl Bal Rs 5,342.79.-SBI', t0.add(const Duration(minutes: 20))),
    ]);
    final rows = await db.readAllTransactions();
    expect(rows.single.merchant, 'annual maintenance charges');
  });

  test('two card swipes at different merchants are both kept', () async {
    await importSms([
      ('AD-HDFCBK', 'Spent Rs.200 On HDFC Bank Card 9921 At SHOP ONE On 2026-11-06:02:29:00.Not You?', t0),
      ('AD-HDFCBK', 'Spent Rs.200 On HDFC Bank Card 9921 At SHOP TWO On 2026-11-06:02:31:00.Not You?', t0.add(const Duration(minutes: 2))),
    ]);
    expect(await db.readAllTransactions(), hasLength(2));
  });

  test('restoring a hidden row brings it back and it stays', () async {
    await importSms([('AD-HDFCBK-T', bankBill, t0), ('AD-HDFCBK-S', cardBill, t0)]);
    await db.restoreDuplicate((await db.readHiddenDuplicates()).single);
    expect(await db.readAllTransactions(), hasLength(2));
    await db.resolveDuplicates([]); // nothing new: nothing re-hidden
    expect(await db.readHiddenDuplicates(), isEmpty);
  });

  test('hidden rows count nowhere, including reconciliation', () async {
    await importSms([('AD-HDFCBK-T', bankBill, t0), ('AD-HDFCBK-S', cardBill, t0)]);
    expect(await db.monthRows('2026-11', account: 'HDFC Card XX9921'), isEmpty);
    expect(await db.monthRowsAllAccounts('2026-11'), hasLength(1));
  });
}
