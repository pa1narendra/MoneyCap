import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/transaction_model.dart';
import '../providers/transaction_provider.dart';
import '../services/category_service.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';
import 'input_dialogs.dart';
import 'transaction_form.dart';

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// Details + actions for one transaction. The original SMS text is loaded on
/// demand (it isn't kept in memory with the list).
Future<void> showTransactionSheet(BuildContext context, TransactionModel txn) {
  final provider = context.read<TransactionProvider>();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final category = provider.categoryOf(txn);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(txn.merchant, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                if (txn.originalMerchant != null)
                  Text('SMS says ${txn.originalMerchant}',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${txn.isTransfer ? 'Transfer' : (txn.type == 'DEBIT' ? 'Expense' : 'Income')} · '
                  '${_money.format(txn.amount)}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
                  Chip(label: Text(DateFormat('d MMM yyyy, HH:mm').format(txn.timestamp))),
                  Chip(label: Text(category)),
                  if (txn.account != null) Chip(label: Text(txn.account!)),
                  Chip(label: Text(txn.source == 'SMS' ? 'From SMS' : 'Manual')),
                ]),
                if (txn.source == 'SMS') ...[
                  const SizedBox(height: AppSpacing.sm),
                  FutureBuilder<String>(
                    future: provider.bodyOf(txn),
                    builder: (_, snap) => Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        snap.data ?? '…',
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
                const Divider(height: AppSpacing.lg),
                if (provider.canName(txn))
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(txn.originalMerchant == null && !provider.isSelf(txn)
                        ? 'Name this person or payee'
                        : 'Change name'),
                    subtitle: Text('Applies to all of "${provider.smsNameOf(txn)}", past and future'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final r = await showDialog<(String, bool)>(
                        context: context,
                        builder: (_) => NameDialog(
                          smsName: provider.smsNameOf(txn),
                          name: txn.originalMerchant == null ? '' : txn.merchant,
                          isSelf: provider.isSelf(txn),
                        ),
                      );
                      if (r == null) return;
                      await provider.setMerchantName(txn, r.$1, isSelf: r.$2);
                      if (context.mounted) showToast(context, 'Saved');
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Change category'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _pickCategory(context, provider, txn, category);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(txn.isTransfer ? 'Count as income/expense' : 'Mark as transfer between my accounts'),
                  subtitle: txn.isTransfer ? null : const Text('Excluded from income and expense totals'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await provider.updateTransaction(txn.copyWith(
                        kind: txn.isTransfer ? TransactionModel.kindNormal : TransactionModel.kindTransfer));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final d = await showTransactionForm(
                      context,
                      title: 'Edit transaction',
                      amount: txn.amount,
                      type: txn.type,
                      merchant: txn.merchant,
                      date: txn.timestamp,
                      category: txn.category,
                      transfer: txn.isTransfer,
                    );
                    if (d == null) return;
                    // Changing a name the user gave changes it everywhere.
                    if (txn.originalMerchant != null && d.merchant != txn.merchant) {
                      await provider.setMerchantName(txn, d.merchant, isSelf: provider.isSelf(txn));
                    }
                    // Build a new object; the in-memory list is only replaced
                    // once the DB write succeeds.
                    await provider.updateTransaction(txn.copyWith(
                      amount: d.amount,
                      type: d.type,
                      merchant: d.merchant,
                      timestamp: d.date,
                      category: d.category,
                      clearCategory: d.category == null,
                      kind: d.transfer ? TransactionModel.kindTransfer : TransactionModel.kindNormal,
                    ));
                    if (context.mounted) showToast(context, 'Transaction updated');
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline, color: cs.error),
                  title: Text('Delete', style: TextStyle(color: cs.error)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: const Text('Delete transaction?'),
                        content: Text(
                          '${txn.merchant} · ${_money.format(txn.amount)}'
                          '${txn.source == 'SMS' ? '\n\nThis SMS won\'t be imported again.' : ''}',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: cs.error),
                            onPressed: () => Navigator.pop(d, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true && txn.id != null) {
                      await provider.deleteTransaction(txn.id!);
                      if (context.mounted) showToast(context, 'Transaction deleted');
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<void> _pickCategory(BuildContext context, TransactionProvider provider,
    TransactionModel txn, String current) async {
  var applyAll = txn.merchant != 'Unknown';
  final picked = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (txn.merchant != 'Unknown')
              CheckboxListTile(
                value: applyAll,
                onChanged: (v) => setState(() => applyAll = v ?? false),
                title: Text('Apply to all from "${txn.merchant}"'),
                subtitle: const Text('Also applies to future transactions'),
              ),
            const Divider(height: 1),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final c in Categories.all)
                  ListTile(
                    title: Text(c),
                    trailing: c == current ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(ctx, c),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
  if (picked == null) return;
  await provider.setCategory(txn, picked, applyToMerchant: applyAll);
  if (context.mounted) showToast(context, 'Category set to $picked');
}
