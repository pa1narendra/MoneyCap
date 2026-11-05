import '../models/transaction_model.dart';
import 'category_service.dart';

enum Cadence { weekly, monthly, yearly }

class RecurringPayment {
  final String merchant;
  final double typicalAmount;
  final Cadence cadence;
  final int occurrences;
  final DateTime lastPaid;
  final DateTime nextExpected;
  const RecurringPayment({
    required this.merchant,
    required this.typicalAmount,
    required this.cadence,
    required this.occurrences,
    required this.lastPaid,
    required this.nextExpected,
  });

  /// Rough monthly cost, for "your subscriptions cost ₹X a month".
  double get monthlyCost => switch (cadence) {
        Cadence.weekly => typicalAmount * 52 / 12,
        Cadence.monthly => typicalAmount,
        Cadence.yearly => typicalAmount / 12,
      };
}

class BudgetStatus {
  final String category;
  final double limit;
  final double spent;
  const BudgetStatus(this.category, this.limit, this.spent);
  double get fraction => limit <= 0 ? 0 : spent / limit;
  bool get over => spent > limit;
}

class Insights {
  Insights._();

  /// Finds payments that repeat at a steady interval with a steady amount
  /// (subscriptions, rent, EMIs, SIPs). Needs >= 3 payments to the same
  /// merchant whose gaps all sit in one cadence band and whose amounts stay
  /// within 15% of the median.
  static List<RecurringPayment> detectRecurring(Iterable<TransactionModel> txns) {
    final groups = <String, List<TransactionModel>>{};
    for (final t in txns) {
      if (!t.isExpense || t.merchant == 'Unknown') continue;
      groups.putIfAbsent(Categories.merchantKey(t.merchant), () => []).add(t);
    }
    final out = <RecurringPayment>[];
    for (final list in groups.values) {
      if (list.length < 3) continue;
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final amounts = list.map((t) => t.amount).toList()..sort();
      final median = amounts[amounts.length ~/ 2];
      // Use the payments close to the median amount (ignores one-off extras).
      final steady = list.where((t) => (t.amount - median).abs() <= median * 0.15).toList();
      if (steady.length < 3) continue;
      final gaps = <int>[];
      for (var i = 1; i < steady.length; i++) {
        gaps.add(steady[i].timestamp.difference(steady[i - 1].timestamp).inDays);
      }
      final cadence = _cadenceOf(gaps);
      if (cadence == null) continue;
      final last = steady.last.timestamp;
      out.add(RecurringPayment(
        merchant: steady.last.merchant,
        typicalAmount: median,
        cadence: cadence,
        occurrences: steady.length,
        lastPaid: last,
        nextExpected: switch (cadence) {
          Cadence.weekly => last.add(const Duration(days: 7)),
          // Clamp so Jan 31 -> Feb 28/29, not Mar 3.
          Cadence.monthly => DateTime(last.year, last.month + 1,
              last.day.clamp(1, DateTime(last.year, last.month + 2, 0).day)),
          Cadence.yearly => DateTime(last.year + 1, last.month, last.day),
        },
      ));
    }
    out.sort((a, b) => b.monthlyCost.compareTo(a.monthlyCost));
    return out;
  }

  static Cadence? _cadenceOf(List<int> gaps) {
    bool all(int lo, int hi) => gaps.every((g) => g >= lo && g <= hi);
    if (all(6, 8)) return Cadence.weekly;
    if (all(26, 35)) return Cadence.monthly;
    if (all(350, 380)) return Cadence.yearly;
    return null;
  }

  /// Spend per category in [month] (expenses only; transfers excluded).
  static Map<String, double> spendByCategory(Iterable<TransactionModel> txns,
      Map<String, String> rules, {DateTime? month}) {
    final out = <String, double>{};
    for (final t in txns) {
      if (!t.isExpense) continue;
      if (month != null &&
          (t.timestamp.year != month.year || t.timestamp.month != month.month)) {
        continue;
      }
      final c = Categories.resolve(t, rules);
      out[c] = (out[c] ?? 0) + t.amount;
    }
    return out;
  }

  static List<BudgetStatus> budgetStatus(Map<String, double> budgets,
      Map<String, double> spentByCategory) {
    final out = budgets.entries
        .map((e) => BudgetStatus(e.key, e.value, spentByCategory[e.key] ?? 0))
        .toList()
      ..sort((a, b) => b.fraction.compareTo(a.fraction));
    return out;
  }
}
