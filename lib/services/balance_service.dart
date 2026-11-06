import 'package:intl/intl.dart';
import 'db_service.dart';

/// Opening/closing balance prompts and reconciliation.
///
/// Reconciliation is per account (`account` = e.g. `HDFC A/c XX1234`), or `''` for
/// all bank accounts combined. Transfers ARE included here: they really moved
/// money in and out of the account (an own-account transfer nets to zero
/// across the combined view). Card rows are excluded from the combined view
/// because a card's dues are not part of a bank balance.
class BalanceService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  /// The next balance to ask for: each active bank account gets its own
  /// opening balance in the first 5 days of the month and closing balance in
  /// the last 3. With no bank account seen yet it asks for one combined figure.
  /// [skip] holds accounts the user skipped this session.
  Future<BalancePrompt?> checkBalancePrompt({DateTime? at, Set<String> skip = const {}}) async {
    final now = at ?? DateTime.now();
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    final isOpening = now.day <= 5;
    if (!isOpening && now.day < lastDay - 2) return null;

    final month = DateFormat('yyyy-MM').format(now);
    final monthName = DateFormat('MMMM yyyy').format(now);
    final found = await _db.activeBankAccounts(now.subtract(const Duration(days: 90)));
    final accounts = found.isEmpty ? const [''] : found;
    final column = isOpening ? 'opening_balance' : 'closing_balance';
    for (final account in accounts) {
      if (skip.contains(account)) continue;
      final balance = await _db.getMonthlyBalance(month, account: account);
      if (balance == null || balance[column] == null) {
        return BalancePrompt(
          type: isOpening ? PromptType.opening : PromptType.closing,
          month: month,
          monthName: monthName,
          account: account,
        );
      }
    }
    return null;
  }

  Future<MonthSummary> getMonthSummary(String month, {String account = ''}) async {
    final rows = await _db.monthRows(month, account: account);
    return MonthSummary.fromRows(month, rows);
  }

  Future<BalanceDiscrepancy?> getDiscrepancy(String month, {String account = ''}) async {
    final balance = await _db.getMonthlyBalance(month, account: account);
    final opening = (balance?['opening_balance'] as num?)?.toDouble();
    final closing = (balance?['closing_balance'] as num?)?.toDouble();
    if (opening == null || closing == null) return null;
    final summary = await getMonthSummary(month, account: account);
    final expected = opening + summary.totalCredits - summary.totalDebits;
    return BalanceDiscrepancy(
      month: month,
      openingBalance: opening,
      closingBalance: closing,
      expectedClosing: expected,
      discrepancy: closing - expected,
      isReconciled: (balance?['is_reconciled'] as int? ?? 0) == 1,
    );
  }
}

enum PromptType { opening, closing }

class BalancePrompt {
  final PromptType type;
  final String month;
  final String monthName;
  /// Which account this is for; '' = all bank accounts combined.
  final String account;
  BalancePrompt({
    required this.type,
    required this.month,
    required this.monthName,
    this.account = '',
  });

  /// Parses a `type:yyyy-MM` notification payload. Returns null for anything
  /// malformed (payloads come from push data, which is untrusted input).
  static BalancePrompt? fromPayload(String payload) {
    final m = RegExp(r'^(opening|closing):(\d{4})-(\d{2})$').firstMatch(payload);
    if (m == null) return null;
    final year = int.parse(m.group(2)!);
    final mon = int.parse(m.group(3)!);
    if (mon < 1 || mon > 12) return null;
    final date = DateTime(year, mon);
    return BalancePrompt(
      type: m.group(1) == 'opening' ? PromptType.opening : PromptType.closing,
      month: '${m.group(2)}-${m.group(3)}',
      monthName: DateFormat('MMMM yyyy').format(date),
    );
  }
}

class BalanceDiscrepancy {
  final String month;
  final double openingBalance;
  final double closingBalance;
  final double expectedClosing;
  final double discrepancy;
  final bool isReconciled;
  BalanceDiscrepancy({
    required this.month,
    required this.openingBalance,
    required this.closingBalance,
    required this.expectedClosing,
    required this.discrepancy,
    required this.isReconciled,
  });
}

class MonthSummary {
  final String month;
  final double totalCredits;
  final double totalDebits;
  final int creditCount;
  final int debitCount;
  MonthSummary({
    required this.month,
    required this.totalCredits,
    required this.totalDebits,
    required this.creditCount,
    required this.debitCount,
  });

  factory MonthSummary.fromRows(String month, List<Map<String, Object?>> rows) {
    double credits = 0, debits = 0;
    int cc = 0, dc = 0;
    for (final r in rows) {
      final amount = (r['amount'] as num).toDouble();
      if (r['type'] == 'CREDIT') {
        credits += amount;
        cc++;
      } else {
        debits += amount;
        dc++;
      }
    }
    return MonthSummary(
        month: month, totalCredits: credits, totalDebits: debits, creditCount: cc, debitCount: dc);
  }
}
