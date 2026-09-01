import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/transaction_provider.dart';
import '../models/transaction_model.dart';
import '../theme/app_theme.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late DateTime _monthA; // the month being compared (default: current)
  late DateTime _monthB; // the baseline month (default: previous)

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _monthA = DateTime(now.year, now.month, 1);
    _monthB = DateTime(now.year, now.month - 1, 1);
  }

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

    // Monthly spending trend — last 6 months of expenses (all transactions,
    // independent of the dashboard date filter).
    final now = DateTime.now();
    final months = List.generate(6, (i) => DateTime(now.year, now.month - (5 - i), 1));
    const monthAbbr = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthTotals = months.map((m) {
      return provider.transactions
          .where((t) => t.type == 'DEBIT' && t.timestamp.year == m.year && t.timestamp.month == m.month)
          .fold(0.0, (s, t) => s + t.amount);
    }).toList();
    final maxTotal = monthTotals.fold(0.0, (mx, v) => v > mx ? v : mx);
    final hasTrend = maxTotal > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('Monthly Spending'),
            const SizedBox(height: AppSpacing.lg),
            if (hasTrend)
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxTotal * 1.2,
                    barGroups: [
                      for (int i = 0; i < months.length; i++)
                        BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                            toY: monthTotals[i],
                            color: cs.primary,
                            width: 18,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ]),
                    ],
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= months.length) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                monthAbbr[months[idx].month - 1],
                                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              )
            else
              _emptyState(context, 'No spending data yet'),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.md),
            const _SectionTitle('Compare Months'),
            const SizedBox(height: AppSpacing.md),
            _buildComparison(context, provider),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.md),
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

  // ---- Month comparison (AWS-billing style) ----

  ({double expense, double income, int count}) _monthStats(List<TransactionModel> all, DateTime m) {
    double exp = 0, inc = 0;
    int cnt = 0;
    for (final t in all) {
      if (t.timestamp.year == m.year && t.timestamp.month == m.month) {
        cnt++;
        if (t.type == 'DEBIT') {
          exp += t.amount;
        } else {
          inc += t.amount;
        }
      }
    }
    return (expense: exp, income: inc, count: cnt);
  }

  String _monthLabel(DateTime m) {
    const abbr = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${abbr[m.month - 1]} ${m.year}';
  }

  Widget _buildComparison(BuildContext context, TransactionProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final all = provider.transactions;
    final a = _monthStats(all, _monthA);
    final b = _monthStats(all, _monthB);

    final spendPct = b.expense == 0 ? null : (a.expense - b.expense) / b.expense * 100;
    final insight = spendPct == null
        ? 'No spending in ${_monthLabel(_monthB)} to compare against.'
        : (spendPct.abs() < 0.5
            ? 'Spending is about the same as ${_monthLabel(_monthB)}.'
            : 'You spent ${spendPct.abs().toStringAsFixed(0)}% ${spendPct > 0 ? "more" : "less"} than ${_monthLabel(_monthB)}.');

    final now = DateTime.now();
    final options = List.generate(12, (i) => DateTime(now.year, now.month - i, 1));

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _monthDropdown(options, _monthA, (m) => setState(() => _monthA = m))),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Text('vs'),
                ),
                Expanded(child: _monthDropdown(options, _monthB, (m) => setState(() => _monthB = m))),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(insight, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.md),
            _compareRow(context, 'Spending', a.expense, b.expense, higherIsBad: true),
            const Divider(height: 28),
            _compareRow(context, 'Income', a.income, b.income, higherIsBad: false),
            const Divider(height: 28),
            _compareCountRow(context, 'Transactions', a.count, b.count),
          ],
        ),
      ),
    );
  }

  Widget _monthDropdown(List<DateTime> options, DateTime value, ValueChanged<DateTime> onChanged) {
    return DropdownButtonFormField<DateTime>(
      value: value,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: options.map((m) => DropdownMenuItem(value: m, child: Text(_monthLabel(m)))).toList(),
      onChanged: (m) {
        if (m != null) onChanged(m);
      },
    );
  }

  Widget _compareRow(BuildContext context, String label, double current, double baseline, {required bool higherIsBad}) {
    final cs = Theme.of(context).colorScheme;
    final diff = current - baseline;
    final same = diff.abs() < 0.01;
    final up = diff > 0;
    final favorable = up ? !higherIsBad : higherIsBad;
    final color = same
        ? cs.onSurfaceVariant
        : (favorable ? AppColors.income(cs.brightness) : AppColors.expense(cs.brightness));
    final arrow = same ? Icons.remove : (up ? Icons.arrow_upward : Icons.arrow_downward);
    final pct = baseline == 0 ? null : (diff / baseline * 100).abs();
    final changeText = same ? '—' : (pct == null ? 'new' : '${pct.toStringAsFixed(0)}%');
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 2),
              Text('₹${current.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text('was ₹${baseline.toStringAsFixed(2)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ),
        Icon(arrow, size: 16, color: color),
        const SizedBox(width: 2),
        Text(changeText, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16)),
      ],
    );
  }

  Widget _compareCountRow(BuildContext context, String label, int current, int baseline) {
    final cs = Theme.of(context).colorScheme;
    final diff = current - baseline;
    final arrow = diff == 0 ? Icons.remove : (diff > 0 ? Icons.arrow_upward : Icons.arrow_downward);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 2),
              Text('$current', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text('was $baseline', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ),
        Icon(arrow, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 2),
        Text(diff == 0 ? '—' : '${diff > 0 ? "+" : ""}$diff',
            style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 16)),
      ],
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
