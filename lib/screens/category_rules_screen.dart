import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/transaction_provider.dart';
import '../services/category_service.dart';
import '../theme/app_theme.dart';

/// Editable merchant -> category rules. A rule matches when the merchant
/// name contains the rule text (case-insensitive). Rules beat the built-in
/// keywords; a category set on a single transaction beats both.
class CategoryRulesScreen extends StatelessWidget {
  const CategoryRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final rules = provider.categoryRules.entries.toList();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Category rules')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, provider),
        icon: const Icon(Icons.add),
        label: const Text('Add rule'),
      ),
      body: rules.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'No custom rules yet.\n\nTip: tap any transaction, choose "Change category" '
                  'and keep "Apply to all" ticked to create one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: rules.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = rules[i];
                return ListTile(
                  title: Text('Merchant contains "${r.key}"'),
                  subtitle: Text(r.value),
                  onTap: () => _edit(context, provider, pattern: r.key, category: r.value),
                  trailing: IconButton(
                    tooltip: 'Delete rule',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => provider.deleteRule(r.key),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _edit(BuildContext context, TransactionProvider provider,
      {String? pattern, String? category}) async {
    final c = TextEditingController(text: pattern ?? '');
    var cat = category ?? Categories.food;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: Text(pattern == null ? 'New rule' : 'Edit rule'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: c,
              enabled: pattern == null,
              decoration: const InputDecoration(labelText: 'Merchant name contains'),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: cat,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [for (final x in Categories.all) DropdownMenuItem(value: x, child: Text(x))],
              onChanged: (v) => setState(() => cat = v!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) await provider.setRule(c.text, cat);
    c.dispose();
  }
}
