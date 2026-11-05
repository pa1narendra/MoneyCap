import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/transaction_provider.dart';
import '../services/balance_service.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/transaction_form.dart';

/// Monthly reconciliation, per bank account or for all bank accounts
/// combined. Card accounts are excluded from the combined view because card
/// dues aren't part of a bank balance.
class ReconciliationScreen extends StatefulWidget {
  final String? initialMonth;
  const ReconciliationScreen({super.key, this.initialMonth});

  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> {
  final _balanceService = BalanceService();
  final _db = DatabaseHelper.instance;
  late String _month = widget.initialMonth ?? DateFormat('yyyy-MM').format(DateTime.now());
  String _account = ''; // '' = all bank accounts
  Map<String, dynamic>? _monthlyBalance;
  BalanceDiscrepancy? _discrepancy;
  MonthSummary? _summary;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final balance = await _db.getMonthlyBalance(_month, account: _account);
      final discrepancy = await _balanceService.getDiscrepancy(_month, account: _account);
      final summary = await _balanceService.getMonthSummary(_month, account: _account);
      if (!mounted) return;
      setState(() {
        _monthlyBalance = balance;
        _discrepancy = discrepancy;
        _summary = summary;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markReconciled() async {
    await _db.markReconciled(_month, account: _account);
    await _loadData();
    if (mounted) showToast(context, 'Month marked as reconciled');
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse('$_month-01'),
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked == null) return;
    setState(() => _month = DateFormat('yyyy-MM').format(picked));
    await _loadData();
  }

  Future<void> _showBalanceEntryDialog({required bool isOpening}) async {
    final cs = Theme.of(context).colorScheme;
    final current = (_monthlyBalance?[isOpening ? 'opening_balance' : 'closing_balance'] as num?)?.toDouble();
    final controller = TextEditingController(text: current?.toStringAsFixed(2) ?? '');
    final monthName = DateFormat('MMMM yyyy').format(DateTime.parse('$_month-01'));
    final who = _account.isEmpty ? 'all your bank accounts combined' : _account;

    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isOpening ? 'Opening Balance' : 'Closing Balance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Balance of $who at the ${isOpening ? 'start' : 'end'} of $monthName',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,2}'))],
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Balance',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
                hintText: '0.00',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim());
              if (v == null) {
                showToast(ctx, 'Please enter a valid amount', isError: true);
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null) return;
    if (isOpening) {
      await _db.saveOpeningBalance(_month, amount, account: _account);
    } else {
      await _db.saveClosingBalance(_month, amount, account: _account);
    }
    if (!mounted) return;
    showToast(context, '${isOpening ? "Opening" : "Closing"} balance saved');
    await _loadData();
  }

  Future<void> _addMissingTransaction() async {
    final provider = context.read<TransactionProvider>();
    final parts = _month.split('-');
    final y = int.parse(parts[0]), m = int.parse(parts[1]);
    final diff = _discrepancy?.discrepancy ?? 0;
    final draft = await showTransactionForm(
      context,
      title: 'Add missing transaction',
      submitLabel: 'Add',
      amount: diff.abs() >= 0.01 ? diff.abs() : null,
      type: diff > 0 ? 'CREDIT' : 'DEBIT',
      date: DateTime(y, m + 1, 0),
      firstDate: DateTime(y, m, 1),
      lastDate: DateTime(y, m + 1, 0),
    );
    if (draft == null) return;
    await provider.addTransaction(draft.amount, draft.type, draft.merchant,
        date: draft.date,
        category: draft.category,
        transfer: draft.transfer,
        account: _account.isEmpty ? null : _account);
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bankAccounts = context
        .watch<TransactionProvider>()
        .accounts
        .where((a) => !a.startsWith('Card'))
        .toList();
    final hasOpening = _monthlyBalance?['opening_balance'] != null;
    final hasClosing = _monthlyBalance?['closing_balance'] != null;
    final hasBoth = hasOpening && hasClosing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Balance Reconciliation'),
        actions: [
          if (_discrepancy != null && !_discrepancy!.isReconciled)
            IconButton(
              icon: const Icon(Icons.check_circle_outline),
              tooltip: 'Mark as reconciled',
              onPressed: _markReconciled,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _card(
                    child: ListTile(
                      leading: Icon(Icons.calendar_month, color: cs.primary),
                      title: Text(DateFormat('MMMM yyyy').format(DateTime.parse('$_month-01')),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.arrow_drop_down),
                      onTap: _pickMonth,
                    ),
                  ),
                  if (bankAccounts.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: bankAccounts.contains(_account) ? _account : '',
                            isExpanded: true,
                            icon: const Icon(Icons.arrow_drop_down),
                            items: [
                              const DropdownMenuItem(value: '', child: Text('All bank accounts')),
                              for (final a in bankAccounts) DropdownMenuItem(value: a, child: Text(a)),
                            ],
                            onChanged: (a) {
                              setState(() => _account = a ?? '');
                              _loadData();
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  _buildBalanceEntryCard(
                    title: 'Opening Balance',
                    subtitle: 'Balance at the start of the month',
                    value: (_monthlyBalance?['opening_balance'] as num?)?.toDouble(),
                    icon: Icons.login,
                    color: cs.primary,
                    onTap: () => _showBalanceEntryDialog(isOpening: true),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildBalanceEntryCard(
                    title: 'Closing Balance',
                    subtitle: 'Balance at the end of the month',
                    value: (_monthlyBalance?['closing_balance'] as num?)?.toDouble(),
                    icon: Icons.logout,
                    color: cs.tertiary,
                    onTap: () => _showBalanceEntryDialog(isOpening: false),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_summary != null) _buildTransactionSummary(),
                  const SizedBox(height: AppSpacing.md),
                  if (hasBoth && _discrepancy != null) ...[
                    _buildReconciliationCard(),
                    const SizedBox(height: AppSpacing.md),
                    if (_discrepancy!.discrepancy.abs() > 0.01) _buildDiscrepancyAlert(),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _addMissingTransaction,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Missing Transaction'),
                      ),
                    ),
                  ] else
                    _buildInfoCard(
                      !hasOpening && !hasClosing
                          ? 'Enter both opening and closing balances to see reconciliation.'
                          : !hasOpening
                              ? 'Enter the opening balance to see reconciliation.'
                              : 'Enter the closing balance to see reconciliation.',
                    ),
                  if (bankAccounts.length > 1 && _account.isEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Tip: you have ${bankAccounts.length} bank accounts. Reconciling each one '
                      'separately pinpoints which account is missing a transaction.',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _card({required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: child,
    );
  }

  Widget _buildBalanceEntryCard({
    required String title,
    required String subtitle,
    required double? value,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return _card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: value != null
            ? Text('₹${value.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color))
            : Text(subtitle, style: TextStyle(color: cs.onSurfaceVariant)),
        trailing: Icon(value != null ? Icons.edit : Icons.add_circle_outline, color: color),
        onTap: onTap,
      ),
    );
  }

  Widget _buildReconciliationCard() {
    final cs = Theme.of(context).colorScheme;
    final income = AppColors.income(cs.brightness);
    final expense = AppColors.expense(cs.brightness);
    return _card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reconciliation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const Divider(),
            _row('Opening Balance', _discrepancy!.openingBalance, cs.primary),
            const SizedBox(height: AppSpacing.sm),
            _row('+ Money in', _summary?.totalCredits ?? 0, income),
            const SizedBox(height: AppSpacing.sm),
            _row('- Money out', _summary?.totalDebits ?? 0, expense),
            const Divider(),
            _row('Expected Closing', _discrepancy!.expectedClosing, cs.onSurfaceVariant, bold: true),
            const SizedBox(height: AppSpacing.sm),
            _row('Actual Closing', _discrepancy!.closingBalance, cs.tertiary, bold: true),
            const Divider(),
            _row('Discrepancy', _discrepancy!.discrepancy,
                _discrepancy!.discrepancy.abs() < 0.01 ? income : expense,
                bold: true),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, double amount, Color color, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
        Text('₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
              fontSize: bold ? 18 : 16,
            )),
      ],
    );
  }

  Widget _buildTransactionSummary() {
    final cs = Theme.of(context).colorScheme;
    final income = AppColors.income(cs.brightness);
    final expense = AppColors.expense(cs.brightness);
    return _card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Transaction Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Includes transfers, since they move money in and out of the account.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            const Divider(),
            Row(children: [
              Expanded(child: _summaryColumn('Money in', _summary!.totalCredits, _summary!.creditCount, income)),
              Container(height: 60, width: 1, color: cs.outlineVariant),
              Expanded(child: _summaryColumn('Money out', _summary!.totalDebits, _summary!.debitCount, expense)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _summaryColumn(String label, double amount, int count, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Text(label, style: TextStyle(color: color)),
      const SizedBox(height: AppSpacing.xs),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('₹${amount.toStringAsFixed(2)}',
            maxLines: 1, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text('$count transactions', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
    ]);
  }

  Widget _buildInfoCard(String message) {
    final cs = Theme.of(context).colorScheme;
    return _card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(children: [
          Icon(Icons.info_outline, color: cs.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(message, style: TextStyle(color: cs.onSurfaceVariant))),
        ]),
      ),
    );
  }

  Widget _buildDiscrepancyAlert() {
    final cs = Theme.of(context).colorScheme;
    final d = _discrepancy!.discrepancy;
    return Card(
      elevation: 0,
      color: cs.errorContainer,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(children: [
          Icon(Icons.warning_amber, color: cs.onErrorContainer, size: 32),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Discrepancy Detected',
                  style: TextStyle(fontWeight: FontWeight.w700, color: cs.onErrorContainer)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                d > 0
                    ? 'Your actual balance is ₹${d.toStringAsFixed(2)} higher than expected. You may have missing credits.'
                    : 'Your actual balance is ₹${d.abs().toStringAsFixed(2)} lower than expected. You may have missing debits.',
                style: TextStyle(color: cs.onErrorContainer),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
