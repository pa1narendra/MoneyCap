import 'dart:io';

import 'package:moneycap/models/transaction_model.dart';
import 'package:moneycap/services/db_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fresh on-disk SQLite DB (ffi) + empty prefs for each test.
Future<Directory> setUpTestDb({Map<String, Object> prefs = const {}}) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  SharedPreferences.setMockInitialValues(prefs);
  await DatabaseHelper.resetForTest();
  final dir = await Directory.systemTemp.createTemp('moneycap_test');
  DatabaseHelper.pathOverride = '${dir.path}/moneycap.db';
  return dir;
}

Future<void> tearDownTestDb(Directory dir) async {
  await DatabaseHelper.resetForTest();
  DatabaseHelper.pathOverride = null;
  try {
    await dir.delete(recursive: true);
  } catch (_) {}
}

TransactionModel txn({
  double amount = 100,
  String type = 'DEBIT',
  String merchant = 'Shop',
  DateTime? at,
  String source = 'SMS',
  String? key,
  String kind = 'NORMAL',
  String? account,
  String? category,
}) =>
    TransactionModel(
      amount: amount,
      type: type,
      merchant: merchant,
      timestamp: at ?? DateTime(2026, 11, 5, 12),
      body: 'body of $merchant',
      source: source,
      dedupKey: key,
      kind: kind,
      account: account,
      category: category,
    );
