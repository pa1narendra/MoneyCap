import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/category_service.dart';
import '../theme/app_theme.dart';
import 'input_dialogs.dart';

/// Result of [showTransactionForm].
class TransactionDraft {
  final double amount;
  final String type; // CREDIT / DEBIT
  final String merchant;
  final DateTime date;
  final String? category; // null = automatic (merchant rules)
  final bool transfer;
  const TransactionDraft({
    required this.amount,
    required this.type,
    required this.merchant,
    required this.date,
    required this.category,
    required this.transfer,
  });
}

/// One add/edit form used everywhere (manual entry, edit, reconciliation),
/// so validation is identical: amount > 0 with up to 2 decimals, non-blank
/// merchant, date within [firstDate]..[lastDate].
Future<TransactionDraft?> showTransactionForm(
  BuildContext context, {
  required String title,
  String submitLabel = 'Save',
  double? amount,
  String type = 'DEBIT',
  String merchant = '',
  DateTime? date,
  String? category,
  bool transfer = false,
  DateTime? firstDate,
  DateTime? lastDate,
  String? message,
}) {
  return showDialog<TransactionDraft>(
    context: context,
    builder: (_) => _TransactionFormDialog(
      title: title,
      submitLabel: submitLabel,
      amount: amount,
      type: type,
      merchant: merchant,
      date: date ?? DateTime.now(),
      category: category,
      transfer: transfer,
      firstDate: firstDate ?? DateTime(2015),
      lastDate: lastDate ?? DateTime.now(),
      message: message,
    ),
  );
}

class _TransactionFormDialog extends StatefulWidget {
  final String title;
  final String submitLabel;
  final double? amount;
  final String type;
  final String merchant;
  final DateTime date;
  final String? category;
  final bool transfer;
  final DateTime firstDate;
  final DateTime lastDate;
  final String? message;
  const _TransactionFormDialog({
    required this.title,
    required this.submitLabel,
    required this.amount,
    required this.type,
    required this.merchant,
    required this.date,
    required this.category,
    required this.transfer,
    required this.firstDate,
    required this.lastDate,
    required this.message,
  });

  @override
  State<_TransactionFormDialog> createState() => _TransactionFormDialogState();
}

class _TransactionFormDialogState extends State<_TransactionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount = TextEditingController(
      text: widget.amount == null ? '' : widget.amount!.toStringAsFixed(2));
  late final TextEditingController _merchant = TextEditingController(text: widget.merchant);
  late String _type = widget.type;
  late DateTime _date = _clampDate(widget.date);
  late String? _category = widget.category;
  late bool _transfer = widget.transfer;

  DateTime _clampDate(DateTime d) =>
      d.isBefore(widget.firstDate) ? widget.firstDate : (d.isAfter(widget.lastDate) ? widget.lastDate : d);

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      TransactionDraft(
        amount: double.parse(_amount.text.trim()),
        type: _type,
        merchant: _merchant.text.trim(),
        date: _date,
        category: _category,
        transfer: _transfer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.message != null) ...[
                Text(widget.message!, style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: AppSpacing.md),
              ],
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'DEBIT', label: Text('Expense')),
                  ButtonSegment(value: 'CREDIT', label: Text('Income')),
                ],
                selected: {_type},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _amount,
                autofocus: widget.amount == null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: amountFormatters(),
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                validator: validateAmount,
              ),
              TextFormField(
                controller: _merchant,
                textCapitalization: TextCapitalization.words,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Merchant / description', counterText: ''),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a description' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: widget.firstDate,
                    lastDate: widget.lastDate,
                  );
                  if (picked != null) {
                    setState(() => _date = DateTime(picked.year, picked.month, picked.day,
                        _date.hour, _date.minute));
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(children: [
                    const Icon(Icons.calendar_today, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Text(DateFormat('MMM d, yyyy').format(_date)),
                    const Spacer(),
                    const Icon(Icons.edit, size: 16),
                  ]),
                ),
              ),
              DropdownButtonFormField<String?>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Automatic')),
                  for (final c in Categories.all) DropdownMenuItem<String?>(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _transfer,
                onChanged: (v) => setState(() => _transfer = v ?? false),
                title: const Text('Transfer between my accounts'),
                subtitle: const Text('Not counted as income or expense'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
      ],
    );
  }
}
