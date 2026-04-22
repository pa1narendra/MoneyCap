import 'package:intl/intl.dart';
import 'db_service.dart';

class BalanceService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  // Check if we need to prompt for opening/closing balance
  Future<BalancePrompt?> checkBalancePrompt() async {
    final now = DateTime.now();
    final month = DateFormat('yyyy-MM').format(now);
    final balance = await _db.getMonthlyBalance(month);
    
    // Check if it's the 1st of the month
    if (now.day == 1) {
      if (balance == null || balance['opening_balance'] == null) {
        return BalancePrompt(
          type: PromptType.opening,
          month: month,
          monthName: DateFormat('MMMM yyyy').format(now),
        );
      }
    }
    
    // Check if it's the last day of the month
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    if (now.day == lastDay) {
      if (balance == null || balance['closing_balance'] == null) {
        return BalancePrompt(
          type: PromptType.closing,
          month: month,
          monthName: DateFormat('MMMM yyyy').format(now),
        );
      }
    }
    
    return null;
  }

  // Calculate expected balance from transactions
  Future<double> calculateExpectedBalance(String month, double openingBalance) async {
    final db = await _db.database;
    
    // Parse month to get start and end dates
    final parts = month.split('-');
    final year = int.parse(parts[0]);
    final monthNum = int.parse(parts[1]);
    final startDate = DateTime(year, monthNum, 1);
    final endDate = DateTime(year, monthNum + 1, 0, 23, 59, 59);
    
    final startTimestamp = startDate.millisecondsSinceEpoch;
    final endTimestamp = endDate.millisecondsSinceEpoch;
    
    // Get all transactions for the month
    final transactions = await db.query(
      'transactions',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [startTimestamp, endTimestamp],
    );
    
    double totalCredits = 0;
    double totalDebits = 0;
    
    for (var txn in transactions) {
      final amount = txn['amount'] as double;
      if (txn['type'] == 'CREDIT') {
        totalCredits += amount;
      } else {
        totalDebits += amount;
      }
    }
    
    return openingBalance + totalCredits - totalDebits;
  }

  // Get discrepancy between expected and actual closing
  Future<BalanceDiscrepancy?> getDiscrepancy(String month) async {
    final balance = await _db.getMonthlyBalance(month);
    
    if (balance == null || 
        balance['opening_balance'] == null || 
        balance['closing_balance'] == null) {
      return null;
    }
    
    final openingBalance = balance['opening_balance'] as double;
    final closingBalance = balance['closing_balance'] as double;
    final expected = await calculateExpectedBalance(month, openingBalance);
    
    return BalanceDiscrepancy(
      month: month,
      openingBalance: openingBalance,
      closingBalance: closingBalance,
      expectedClosing: expected,
      discrepancy: closingBalance - expected,
      isReconciled: (balance['is_reconciled'] as int) == 1,
    );
  }

  // Get transaction summary for a month
  Future<MonthSummary> getMonthSummary(String month) async {
    final db = await _db.database;
    
    final parts = month.split('-');
    final year = int.parse(parts[0]);
    final monthNum = int.parse(parts[1]);
    final startDate = DateTime(year, monthNum, 1);
    final endDate = DateTime(year, monthNum + 1, 0, 23, 59, 59);
    
    final startTimestamp = startDate.millisecondsSinceEpoch;
    final endTimestamp = endDate.millisecondsSinceEpoch;
    
    final transactions = await db.query(
      'transactions',
      where: 'timestamp >= ? AND timestamp <= ?',
      whereArgs: [startTimestamp, endTimestamp],
    );
    
    double totalCredits = 0;
    double totalDebits = 0;
    int creditCount = 0;
    int debitCount = 0;
    
    for (var txn in transactions) {
      final amount = txn['amount'] as double;
      if (txn['type'] == 'CREDIT') {
        totalCredits += amount;
        creditCount++;
      } else {
        totalDebits += amount;
        debitCount++;
      }
    }
    
    return MonthSummary(
      month: month,
      totalCredits: totalCredits,
      totalDebits: totalDebits,
      creditCount: creditCount,
      debitCount: debitCount,
    );
  }
}

// Data classes
enum PromptType { opening, closing }

class BalancePrompt {
  final PromptType type;
  final String month;
  final String monthName;

  BalancePrompt({
    required this.type,
    required this.month,
    required this.monthName,
  });
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
}
