import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/transaction_provider.dart';
import '../theme/app_theme.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<TransactionProvider>();
    final txns = provider.filteredTransactions.where((t) => t.type == 'DEBIT').toList();

    // Group expenses by merchant.
    final Map<String, double> merchantExpenses = {};
    final Map<String, int> merchantCounts = {};
    for (var txn in txns) {
      merchantExpenses[txn.merchant] = (merchantExpenses[txn.merchant] ?? 0) + txn.amount;
      merchantCounts[txn.merchant] = (merchantCounts[txn.merchant] ?? 0) + 1;
    }

    final sortedExpenses = merchantExpenses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final repeatedPayments = merchantCounts.entries
        .where((e) => e.value > 1)
        .map((e) => _RepeatedPayment(
              merchant: e.key,
              count: e.value,
              totalAmount: merchantExpenses[e.key] ?? 0.0,
            ))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    final topExpenses = sortedExpenses.take(5).toList();
    final totalExpense = provider.totalExpense;

    Color colorFor(int i) => AppColors.chartPalette[i % AppColors.chartPalette.length];

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('Top Spending'),
            const SizedBox(height: AppSpacing.lg),
            if (totalExpense > 0)
              SizedBox(
                height: 240,
                child: PieChart(
                  PieChartData(
                    sections: topExpenses.asMap().entries.map((entry) {
                      final color = colorFor(entry.key);
                      final pct = entry.value.value / totalExpense * 100;
                      // Pick readable label color for this slice.
                      final onColor =
                          ThemeData.estimateBrightnessForColor(color) == Brightness.dark
                              ? Colors.white
                              : Colors.black87;
                      return PieChartSectionData(
                        color: color,
                        value: entry.value.value,
                        title: '${pct.toStringAsFixed(0)}%',
                        radius: 58,
                        titleStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: onColor,
                        ),
                      );
                    }).toList(),
                    sectionsSpace: 3,
                    centerSpaceRadius: 48,
                  ),
                ),
              ),
            if (topExpenses.isEmpty) _emptyState(context, 'No expenses to chart yet'),
            const SizedBox(height: AppSpacing.md),
            // Legend
            ...topExpenses.asMap().entries.map((entry) {
              final e = entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: colorFor(entry.key), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Text(e.key, overflow: TextOverflow.ellipsis)),
                    Text('₹${e.value.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }),

            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.md),

            const _SectionTitle('Repeated Payments'),
            const SizedBox(height: AppSpacing.xs),
            Text('Merchants you have paid multiple times.',
                style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.md),
            if (repeatedPayments.isEmpty) _emptyState(context, 'No repeated payments found'),
            ...repeatedPayments.map((rp) {
              return Card(
                elevation: 0,
                color: cs.surfaceContainerHighest,
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.primary.withOpacity(0.15),
                    foregroundColor: cs.primary,
                    child: Text('${rp.count}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  title: Text(rp.merchant, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${rp.count} transactions'),
                  trailing: Text(
                    '₹${rp.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              );
            }),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context, String message) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(child: Text(message, style: TextStyle(color: cs.onSurfaceVariant))),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700));
  }
}

class _RepeatedPayment {
  final String merchant;
  final int count;
  final double totalAmount;
  _RepeatedPayment({required this.merchant, required this.count, required this.totalAmount});
}
