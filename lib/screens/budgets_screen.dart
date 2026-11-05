import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/transaction_provider.dart';
import '../services/category_service.dart';
import '../services/insights_service.dart';
import '../theme/app_theme.dart';

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Monthly spending limits per category, with this month's progress.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final statuses = provider.budgetStatusFor(month);
    final spent = Insights.spendByCategory(provider.transactions, provider.categoryRules, month: month);
    final unbudgeted = spent.entries.where((e) => !provider.budgets.containsKey(e.key)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final cs = Theme.of(context).colorScheme;
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day;

    return Scaffold(
      appBar: AppBar(title: Text('Budgets · ${DateFormat('MMMM').format(now)}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, provider),
        icon: const Icon(Icons.add),
        label: const Text('Set budget'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 96),
        children: [
          if (statuses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'Set a monthly limit for a category and MoneyCap will warn you on the dashboard '
                'when you reach 90% of it.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          for (final b in statuses) _BudgetCard(status: b, daysLeft: daysLeft, onTap: () =>
              _edit(context, provider, category: b.category, limit: b.limit)),
          if (unbudgeted.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text('Spent this month without a budget',
                style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.sm),
            for (final e in unbudgeted)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.key),
                trailing: Text(_money.format(e.value)),
                onTap: () => _edit(context, provider, category: e.key, limit: null),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, TransactionProvider provider,
      {String? category, double? limit}) async {
    var cat = category ?? Categories.food;
    final c = TextEditingController(text: limit?.toStringAsFixed(0) ?? '');
    final existing = category != null && provider.budgets.containsKey(category);
    final result = await showDialog<String>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: Text(existing ? 'Edit budget' : 'New budget'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: cat,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final x in Categories.expenseCategories) DropdownMenuItem(value: x, child: Text(x))
              ],
              onChanged: existing ? null : (v) => setState(() => cat = v!),
            ),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
              decoration: const InputDecoration(labelText: 'Monthly limit', prefixText: '₹ '),
            ),
          ]),
          actions: [
            if (existing)
              TextButton(onPressed: () => Navigator.pop(d, 'delete'), child: const Text('Remove')),
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, 'save'), child: const Text('Save')),
          ],
        ),
      ),
    );
    final value = double.tryParse(c.text.trim());
    c.dispose();
    if (result == 'delete') await provider.deleteBudget(cat);
    if (result == 'save' && value != null && value > 0) await provider.setBudget(cat, value);
  }
}

class _BudgetCard extends StatelessWidget {
  final BudgetStatus status;
  final int daysLeft;
  final VoidCallback onTap;
  const _BudgetCard({required this.status, required this.daysLeft, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = status.over
        ? AppColors.expense(cs.brightness)
        : (status.fraction >= 0.9 ? cs.tertiary : AppColors.income(cs.brightness));
    final left = status.limit - status.spent;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(status.category, style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${_money.format(status.spent)} / ${_money.format(status.limit)}'),
            ]),
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(
              value: status.fraction.clamp(0.0, 1.0),
              minHeight: 8,
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              status.over
                  ? 'Over by ${_money.format(-left)}'
                  : '${_money.format(left)} left · $daysLeft day${daysLeft == 1 ? '' : 's'} to go',
              style: TextStyle(color: status.over ? color : cs.onSurfaceVariant, fontSize: 12),
            ),
          ]),
        ),
      ),
    );
  }
}
