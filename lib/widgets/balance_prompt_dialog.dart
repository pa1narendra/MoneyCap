import 'package:flutter/material.dart';
import '../services/balance_service.dart';
import '../services/db_service.dart';
import 'app_toast.dart';
import 'input_dialogs.dart';

/// Asks for one account's opening or closing balance. Returns true if saved.
Future<bool> showBalancePrompt(BuildContext context, BalancePrompt prompt) async {
  final isOpening = prompt.type == PromptType.opening;
  final who = prompt.account.isEmpty ? 'your bank account' : prompt.account;
  final amount = await showAmountDialog(
    context,
    title: isOpening ? 'Opening balance' : 'Closing balance',
    message: isOpening
        ? 'Balance of $who on the 1st of ${prompt.monthName}'
        : 'Balance of $who on the last day of ${prompt.monthName}',
    label: 'Balance',
    allowZero: true,
    allowNegative: true,
    cancelLabel: 'Skip',
    dismissible: false,
  );
  if (amount == null) return false;
  final db = DatabaseHelper.instance;
  try {
    if (isOpening) {
      await db.saveOpeningBalance(prompt.month, amount, account: prompt.account);
    } else {
      await db.saveClosingBalance(prompt.month, amount, account: prompt.account);
    }
  } catch (e) {
    if (context.mounted) showToast(context, "Couldn't save that balance", isError: true);
    return false;
  }
  if (context.mounted) {
    showToast(context, '${isOpening ? "Opening" : "Closing"} balance saved');
  }
  return true;
}
