import 'package:flutter/material.dart';
import '../services/balance_service.dart';
import '../services/db_service.dart';
import 'app_toast.dart';

class BalancePromptDialog extends StatefulWidget {
  final BalancePrompt prompt;

  const BalancePromptDialog({super.key, required this.prompt});

  @override
  State<BalancePromptDialog> createState() => _BalancePromptDialogState();
}

class _BalancePromptDialogState extends State<BalancePromptDialog> {
  final _amountController = TextEditingController();
  final _db = DatabaseHelper.instance;
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _saveBalance() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount < 0) {
      showToast(context, 'Please enter a valid amount', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (widget.prompt.type == PromptType.opening) {
        await _db.saveOpeningBalance(widget.prompt.month, amount);
      } else {
        await _db.saveClosingBalance(widget.prompt.month, amount);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      showToast(
        context,
        '${widget.prompt.type == PromptType.opening ? "Opening" : "Closing"} balance saved!',
      );
    } catch (e) {
      if (!mounted) return;
      showToast(context, 'Error saving balance: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOpening = widget.prompt.type == PromptType.opening;

    return AlertDialog(
      title: Text(
        isOpening ? 'Opening Balance' : 'Closing Balance',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isOpening
                ? 'Enter your account balance as of the 1st of ${widget.prompt.monthName}'
                : 'Enter your account balance as of the last day of ${widget.prompt.monthName}',
            style: TextStyle(color: Colors.grey[700]),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Balance Amount',
              prefixText: '₹ ',
              border: OutlineInputBorder(),
              hintText: '0.00',
            ),
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Skip'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveBalance,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
