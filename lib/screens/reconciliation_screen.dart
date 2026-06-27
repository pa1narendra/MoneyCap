import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/balance_service.dart';
import '../services/db_service.dart';
import '../providers/transaction_provider.dart';
import 'package:provider/provider.dart';
import '../widgets/app_toast.dart';

class ReconciliationScreen extends StatefulWidget {
  final String? initialMonth;

  const ReconciliationScreen({super.key, this.initialMonth});

  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> {
  final _balanceService = BalanceService();
  final _db = DatabaseHelper.instance;
  String? _selectedMonth;
  Map<String, dynamic>? _monthlyBalance;
  BalanceDiscrepancy? _discrepancy;
  MonthSummary? _summary;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedMonth = widget.initialMonth ?? DateFormat('yyyy-MM').format(DateTime.now());
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final balance = await _db.getMonthlyBalance(_selectedMonth!);
      final discrepancy = await _balanceService.getDiscrepancy(_selectedMonth!);
      final summary = await _balanceService.getMonthSummary(_selectedMonth!);
      setState(() {
        _monthlyBalance = balance;
        _discrepancy = discrepancy;
        _summary = summary;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markReconciled() async {
    await _db.markReconciled(_selectedMonth!);
    _loadData();
    if (!mounted) return;
    showToast(context, 'Month marked as reconciled');
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse('${_selectedMonth!}-01'),
      firstDate: DateTime(2020),
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked != null) {
      setState(() {
        _selectedMonth = DateFormat('yyyy-MM').format(picked);
      });
      _loadData();
    }
  }

  void _showBalanceEntryDialog({required bool isOpening}) {
    final controller = TextEditingController();
    final currentValue = isOpening
        ? (_monthlyBalance != null ? _monthlyBalance!['opening_balance'] : null)
        : (_monthlyBalance != null ? _monthlyBalance!['closing_balance'] : null);
    if (currentValue != null) {
      controller.text = (currentValue as double).toStringAsFixed(2);
    }

    final monthDate = DateTime.parse('${_selectedMonth!}-01');
    final monthName = DateFormat('MMMM yyyy').format(monthDate);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isOpening ? 'Opening Balance' : 'Closing Balance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isOpening
                  ? 'Enter your account balance at the start of $monthName'
                  : 'Enter your account balance at the end of $monthName',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Balance Amount',
                prefixText: '₹ ',
                border: OutlineInputBorder(),
                hintText: '0.00',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(controller.text);
              if (amount == null || amount < 0) {
                showToast(context, 'Please enter a valid amount', isError: true);
                return;
              }
              if (isOpening) {
                await _db.saveOpeningBalance(_selectedMonth!, amount);
              } else {
                await _db.saveClosingBalance(_selectedMonth!, amount);
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              showToast(context, '${isOpening ? "Opening" : "Closing"} balance saved!');
              _loadData();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddTransactionDialog() {
    final amountController = TextEditingController();
    final merchantController = TextEditingController();
    String type = 'DEBIT';

    final parts = _selectedMonth!.split('-');
    final year = int.parse(parts[0]);
    final monthNum = int.parse(parts[1]);
    final monthStart = DateTime(year, monthNum, 1);
    final monthEnd = DateTime(year, monthNum + 1, 0);
    final now = DateTime.now();
    DateTime selectedDate = now.isAfter(monthEnd) ? monthEnd : (now.isBefore(monthStart) ? monthStart : now);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Missing Transaction'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text(DateFormat('MMM d, yyyy').format(selectedDate)),
                  subtitle: const Text('Transaction date'),
                  trailing: const Icon(Icons.edit),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: monthStart,
                      lastDate: monthEnd,
                    );
                    if (picked != null) {
                      setState(() => selectedDate = picked);
                    }
                  },
                ),
                const Divider(),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '₹ ',
                  ),
                ),
                TextField(
                  controller: merchantController,
                  decoration: const InputDecoration(labelText: 'Merchant / Description'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Type: '),
                    DropdownButton<String>(
                      value: type,
                      items: const [
                        DropdownMenuItem(value: 'DEBIT', child: Text('Expense')),
                        DropdownMenuItem(value: 'CREDIT', child: Text('Income')),
                      ],
                      onChanged: (val) {
                        setState(() => type = val!);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text) ?? 0.0;
                if (amount > 0 && merchantController.text.isNotEmpty) {
                  await context.read<TransactionProvider>().addTransaction(
                    amount,
                    type,
                    merchantController.text,
                    date: selectedDate,
                  );
                  Navigator.pop(ctx);
                  _loadData();
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasOpening = _monthlyBalance?['opening_balance'] != null;
    final hasClosing = _monthlyBalance?['closing_balance'] != null;
    final hasBothBalances = hasOpening && hasClosing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Balance Reconciliation'),
        actions: [
          if (_discrepancy != null && !_discrepancy!.isReconciled)
            IconButton(
              icon: const Icon(Icons.check_circle_outline),
              tooltip: 'Mark as Reconciled',
              onPressed: _markReconciled,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Month selector - always visible
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.calendar_month),
                      title: Text(
                        DateFormat('MMMM yyyy').format(
                          DateTime.parse('${_selectedMonth!}-01'),
                        ),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: const Icon(Icons.arrow_drop_down),
                      onTap: _pickMonth,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Balance entry cards
                  _buildBalanceEntryCard(
                    title: 'Opening Balance',
                    subtitle: 'Balance at the start of the month',
                    value: _monthlyBalance?['opening_balance'] as double?,
                    icon: Icons.login,
                    color: Colors.blue,
                    onTap: () => _showBalanceEntryDialog(isOpening: true),
                  ),
                  const SizedBox(height: 12),
                  _buildBalanceEntryCard(
                    title: 'Closing Balance',
                    subtitle: 'Balance at the end of the month',
                    value: _monthlyBalance?['closing_balance'] as double?,
                    icon: Icons.logout,
                    color: Colors.orange,
                    onTap: () => _showBalanceEntryDialog(isOpening: false),
                  ),
                  const SizedBox(height: 16),

                  // Transaction Summary - always show
                  if (_summary != null) _buildTransactionSummary(),
                  const SizedBox(height: 16),

                  // Full reconciliation - only when both balances exist
                  if (hasBothBalances && _discrepancy != null) ...[
                    _buildReconciliationCard(),
                    const SizedBox(height: 16),

                    if (_discrepancy!.discrepancy.abs() > 0.01)
                      _buildDiscrepancyAlert(),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _showAddTransactionDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Missing Transaction'),
                          ),
                        ),
                      ],
                    ),
                  ] else if (!hasBothBalances) ...[
                    Card(
                      color: Colors.amber.withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.amber),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                !hasOpening && !hasClosing
                                    ? 'Enter both opening and closing balances to see reconciliation.'
                                    : !hasOpening
                                        ? 'Enter the opening balance to see reconciliation.'
                                        : 'Enter the closing balance to see reconciliation.',
                                style: const TextStyle(color: Colors.amber),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: value != null
            ? Text(
                '₹${value.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              )
            : Text(subtitle, style: TextStyle(color: Colors.grey.shade500)),
        trailing: Icon(
          value != null ? Icons.edit : Icons.add_circle_outline,
          color: color,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildReconciliationCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reconciliation',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            _buildBalanceRow('Opening Balance', _discrepancy!.openingBalance, Colors.blue),
            const SizedBox(height: 8),
            _buildBalanceRow('+ Credits', _summary?.totalCredits ?? 0, Colors.green),
            const SizedBox(height: 8),
            _buildBalanceRow('- Debits', _summary?.totalDebits ?? 0, Colors.red),
            const Divider(),
            _buildBalanceRow('Expected Closing', _discrepancy!.expectedClosing, Colors.grey, isBold: true),
            const SizedBox(height: 8),
            _buildBalanceRow('Actual Closing', _discrepancy!.closingBalance, Colors.orange, isBold: true),
            const Divider(),
            _buildBalanceRow(
              'Discrepancy',
              _discrepancy!.discrepancy,
              _discrepancy!.discrepancy.abs() < 0.01 ? Colors.green : Colors.red,
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceRow(String label, double amount, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          '₹${amount.toStringAsFixed(2)}',
          style: TextStyle(
            color: color,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isBold ? 18 : 16,
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionSummary() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Transaction Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Credits', style: TextStyle(color: Colors.green)),
                    Text(
                      '₹${_summary!.totalCredits.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    Text('${_summary!.creditCount} transactions'),
                  ],
                ),
                Container(height: 60, width: 1, color: Colors.grey),
                Column(
                  children: [
                    const Text('Debits', style: TextStyle(color: Colors.red)),
                    Text(
                      '₹${_summary!.totalDebits.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    Text('${_summary!.debitCount} transactions'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscrepancyAlert() {
    final isPositive = _discrepancy!.discrepancy > 0;
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red.shade700, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Discrepancy Detected',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                  Text(
                    isPositive
                        ? 'Your actual balance is ₹${_discrepancy!.discrepancy.toStringAsFixed(2)} higher than expected. You may have missing credit transactions.'
                        : 'Your actual balance is ₹${_discrepancy!.discrepancy.abs().toStringAsFixed(2)} lower than expected. You may have missing debit transactions.',
                    style: TextStyle(color: Colors.red.shade900),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
