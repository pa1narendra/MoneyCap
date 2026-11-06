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
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => RuleDialog(pattern: pattern, category: category),
    );
    if (result != null) await provider.setRule(result.$1, result.$2);
  }
}

/// Add/edit one rule. Returns (pattern, category).
@visibleForTesting
class RuleDialog extends StatefulWidget {
  final String? pattern;
  final String? category;
  const RuleDialog({super.key, this.pattern, this.category});

  @override
  State<RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<RuleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _pattern = TextEditingController(text: widget.pattern ?? '');
  late String _category = widget.category ?? Categories.food;

  @override
  void dispose() {
    _pattern.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, (_pattern.text.trim(), _category));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.pattern == null ? 'New rule' : 'Edit rule'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _pattern,
              enabled: widget.pattern == null,
              autofocus: widget.pattern == null,
              maxLength: 60,
              decoration: const InputDecoration(
                  labelText: 'Merchant name contains', counterText: ''),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Enter part of a merchant name';
                // One letter would match nearly every merchant.
                if (t.length < 2) return 'Use at least 2 characters';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [for (final x in Categories.all) DropdownMenuItem(value: x, child: Text(x))],
              onChanged: (v) => setState(() => _category = v!),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
