import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/transaction_provider.dart';
import '../services/category_service.dart';
import '../services/insights_service.dart';
import '../theme/app_theme.dart';
import '../widgets/input_dialogs.dart';

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
    final existing = category != null && provider.budgets.containsKey(category);
    final result = await showDialog<_BudgetResult>(
      context: context,
      builder: (_) => BudgetDialog(category: category, limit: limit, existing: existing),
    );
    if (result == null) return;
    if (result.remove) {
      await provider.deleteBudget(result.category);
    } else {
      await provider.setBudget(result.category, result.limit!);
    }
  }
}

class _BudgetResult {
  final String category;
  final double? limit;
  final bool remove;
  const _BudgetResult(this.category, this.limit, {this.remove = false});
}

/// Add/edit one budget. Save with no limit shows an error and stays open.
@visibleForTesting
class BudgetDialog extends StatefulWidget {
  final String? category;
  final double? limit;
  final bool existing;
  const BudgetDialog({super.key, this.category, this.limit, this.existing = false});

  @override
  State<BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<BudgetDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _limit = TextEditingController(text: widget.limit?.toStringAsFixed(0) ?? '');
  late String _category = widget.category ?? Categories.food;

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _BudgetResult(_category, double.parse(_limit.text.trim())));
  }

  @override
  Widget build(BuildContext context) {
    // A transaction can carry a category outside the expense list (say one
    // set by hand), and a dropdown must contain its own current value.
    final items = {...Categories.expenseCategories, _category};
    return AlertDialog(
      title: Text(widget.existing ? 'Edit budget' : 'New budget'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [for (final x in items) DropdownMenuItem(value: x, child: Text(x))],
              onChanged: widget.existing ? null : (v) => setState(() => _category = v!),
            ),
            TextFormField(
              controller: _limit,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: amountFormatters(),
              decoration: const InputDecoration(labelText: 'Monthly limit', prefixText: '₹ '),
              validator: validateAmount,
              onFieldSubmitted: (_) => _save(),
            ),
          ]),
        ),
      ),
      actions: [
        if (widget.existing)
          TextButton(
            onPressed: () => Navigator.pop(context, _BudgetResult(_category, null, remove: true)),
            child: const Text('Remove'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
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
