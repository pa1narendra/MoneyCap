import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Rules for every money field in the app, so they all behave the same.
/// Returns an error message, or null when [text] is acceptable.
String? validateAmount(
  String? text, {
  bool allowZero = false,
  bool allowNegative = false,
}) {
  final t = (text ?? '').trim();
  if (t.isEmpty) return 'Enter an amount';
  final v = double.tryParse(t);
  if (v == null || !v.isFinite) return 'Enter a valid number';
  if (v < 0 && !allowNegative) return "Amount can't be negative";
  if (v == 0 && !allowZero) return 'Enter an amount above 0';
  if (v.abs() > 1e12) return 'That amount looks too large';
  return null;
}

/// Keeps a money field to digits, one dot and two decimals.
List<TextInputFormatter> amountFormatters({bool allowNegative = false}) => [
      FilteringTextInputFormatter.allow(
          RegExp(allowNegative ? r'^-?\d*\.?\d{0,2}' : r'^\d*\.?\d{0,2}')),
    ];

/// Asks for one amount. Returns null if cancelled. An invalid value shows its
/// error under the field and keeps the dialog open.
///
/// Dialogs own their controllers in a State, because a controller disposed
/// right after `showDialog` returns is still in use by the closing animation.
Future<double?> showAmountDialog(
  BuildContext context, {
  required String title,
  String? message,
  String label = 'Amount',
  double? initial,
  bool allowZero = false,
  bool allowNegative = false,
  String submitLabel = 'Save',
  String cancelLabel = 'Cancel',
  bool dismissible = true,
}) {
  return showDialog<double>(
    context: context,
    barrierDismissible: dismissible,
    builder: (_) => _AmountDialog(
      title: title,
      message: message,
      label: label,
      initial: initial,
      allowZero: allowZero,
      allowNegative: allowNegative,
      submitLabel: submitLabel,
      cancelLabel: cancelLabel,
    ),
  );
}

class _AmountDialog extends StatefulWidget {
  final String title;
  final String? message;
  final String label;
  final double? initial;
  final bool allowZero;
  final bool allowNegative;
  final String submitLabel;
  final String cancelLabel;
  const _AmountDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.initial,
    required this.allowZero,
    required this.allowNegative,
    required this.submitLabel,
    required this.cancelLabel,
  });

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller =
      TextEditingController(text: widget.initial?.toStringAsFixed(2) ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, double.parse(_controller.text.trim()));
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
                Text(widget.message!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
                const SizedBox(height: AppSpacing.md),
              ],
              TextFormField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.numberWithOptions(
                    decimal: true, signed: widget.allowNegative),
                inputFormatters: amountFormatters(allowNegative: widget.allowNegative),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: widget.label,
                  prefixText: '₹ ',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => validateAmount(v,
                    allowZero: widget.allowZero, allowNegative: widget.allowNegative),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.cancelLabel)),
        FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
      ],
    );
  }
}

/// Gives a name to a UPI ID or payee. Returns (name, isSelf), or null if
/// cancelled. Saving an empty name with "This is me" off removes the entry.
class NameDialog extends StatefulWidget {
  final String smsName;
  final String name;
  final bool isSelf;
  const NameDialog({super.key, required this.smsName, this.name = '', this.isSelf = false});

  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  late final _controller = TextEditingController(text: widget.name);
  late bool _isSelf = widget.isSelf;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, (_controller.text.trim(), _isSelf));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Who is this?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The SMS says "${widget.smsName}". Your name for it shows on all its '
                'transactions.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Name (optional)',
                hintText: 'Leave empty to show the SMS text',
                counterText: '',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _isSelf,
              onChanged: (v) => setState(() => _isSelf = v ?? false),
              title: const Text('This is me'),
              subtitle: const Text('My own account: count as a transfer'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// Asks for a line of text. Returns null if cancelled. Pass [validator] to
/// require something; without one an empty answer is allowed.
Future<String?> showTextDialog(
  BuildContext context, {
  required String title,
  String label = '',
  String initial = '',
  String? Function(String)? validator,
  TextCapitalization capitalization = TextCapitalization.sentences,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextDialog(
      title: title,
      label: label,
      initial: initial,
      validator: validator,
      capitalization: capitalization,
    ),
  );
}

class _TextDialog extends StatefulWidget {
  final String title;
  final String label;
  final String initial;
  final String? Function(String)? validator;
  final TextCapitalization capitalization;
  const _TextDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.validator,
    required this.capitalization,
  });

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: widget.capitalization,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: widget.label.isEmpty ? null : widget.label,
            counterText: '',
          ),
          validator: widget.validator == null ? null : (v) => widget.validator!((v ?? '').trim()),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
