
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/transaction_provider.dart';
import '../widgets/filter_dialog.dart';
import 'stats_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // Load data on start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TransactionProvider>().loadTransactions();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final currentRange = provider.currentDateRange;
    String rangeLabel = provider.activeFilter.label;
    
    // Format Display Date for Custom
    if (provider.activeFilter == TimeFilter.custom && currentRange != null) {
        rangeLabel = "${DateFormat('MMM d').format(currentRange.start)} - ${DateFormat('MMM d').format(currentRange.end)}";
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finance Manager'),
        actions: [
          // Auto Sync Toggle
          Switch(
            value: provider.isAutoSync, 
            onChanged: (val) {
                provider.toggleAutoSync(val);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Auto Sync ${val ? "Enabled" : "Disabled"}')));
            }
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
                if (value == 'stats') {
                    Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const StatsScreen()),
                    );
                } else if (value == 'reset') {
                    // Confirm Dialog
                    showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                            title: const Text('Reset Data?'),
                            content: const Text('This will delete all transactions. You can re-sync from SMS.'),
                            actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                TextButton(
                                    onPressed: () {
                                        provider.clearAll();
                                        Navigator.pop(ctx);
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data Reset Complete')));
                                    }, 
                                    child: const Text('Reset', style: TextStyle(color: Colors.red))
                                ),
                            ],
                        )
                    );
                }
            },
            itemBuilder: (context) => [
                const PopupMenuItem(
                    value: 'stats',
                    child: Row(
                        children: [Icon(Icons.bar_chart), SizedBox(width: 8), Text('Statistics')],
                    ),
                ),
                const PopupMenuItem(
                    value: 'reset',
                    child: Row(
                        children: [Icon(Icons.delete_forever, color: Colors.red), SizedBox(width: 8), Text('Reset Data')],
                    ),
                )
            ]
          )
        ],
      ),
      body: provider.isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : RefreshIndicator(
              onRefresh: provider.syncSms,
              child: Column(
                children: [
                   // Filter Header
                   Padding(
                       padding: const EdgeInsets.all(16.0),
                       child: Row(
                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
                           children: [
                               InkWell(
                                   borderRadius: BorderRadius.circular(8),
                                   onTap: () => _showFilterDialog(context, provider),
                                   child: Container(
                                       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                       decoration: BoxDecoration(
                                           border: Border.all(color: Colors.grey.shade300),
                                           borderRadius: BorderRadius.circular(8),
                                           color: Colors.white,
                                       ),
                                       child: Row(
                                           children: [
                                               const Icon(Icons.calendar_today, size: 16),
                                               const SizedBox(width: 8),
                                               Text(rangeLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
                                               const Icon(Icons.arrow_drop_down),
                                           ],
                                       ),
                                   ),
                               ),
                               Text(
                                   '${provider.filteredTransactions.length} items',
                                   style: TextStyle(color: Colors.grey[600]),
                               ),
                           ],
                       ),
                   ),
                  _buildSummaryCard(provider),
                  Expanded(
                    child: provider.filteredTransactions.isEmpty 
                    ? const Center(child: Text('No transactions in this period'))
                    : ListView.builder(
                      itemCount: provider.filteredTransactions.length,
                      itemBuilder: (context, index) {
                        final txn = provider.filteredTransactions[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: txn.type == 'DEBIT' ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                            child: Icon(
                                txn.type == 'DEBIT' ? Icons.arrow_upward : Icons.arrow_downward,
                                color: txn.type == 'DEBIT' ? Colors.red : Colors.green,
                            ),
                          ),
                          title: Text(txn.merchant, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Row(
                              children: [
                                  Icon(txn.source == 'SMS' ? Icons.message : Icons.person, size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(DateFormat('yyyy-MM-dd HH:mm').format(txn.timestamp)),
                              ],
                          ),
                          trailing: Text(
                            '${txn.type == 'DEBIT' ? '-' : '+'} ₹${txn.amount.toStringAsFixed(2)}',
                            style: TextStyle(
                                color: txn.type == 'DEBIT' ? Colors.red : Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddOptions(context, provider),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showFilterDialog(BuildContext context, TransactionProvider provider) {
      showDialog(
          context: context, 
          builder: (ctx) => FilterDialog(
              initialFilter: provider.activeFilter,
              onApply: (filter, range) {
                  provider.setFilter(filter, customRange: range);
              },
          )
      );
  }

  void _showAddOptions(BuildContext context, TransactionProvider provider) {
      showModalBottomSheet(
          context: context,
          builder: (ctx) => Wrap(
              children: [
                  ListTile(
                      leading: const Icon(Icons.sync),
                      title: const Text('Sync SMS'),
                      onTap: () async {
                          Navigator.pop(ctx);
                          await provider.syncSms();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Synced!')));
                      },
                  ),
                  ListTile(
                      leading: const Icon(Icons.edit),
                      title: const Text('Add Manually'),
                      onTap: () {
                          Navigator.pop(ctx);
                          _showManualEntryDialog(context, provider);
                      },
                  ),
              ],
          )
      );
  }

  void _showManualEntryDialog(BuildContext context, TransactionProvider provider) {
      final amountController = TextEditingController();
      final merchantController = TextEditingController();
      String type = 'DEBIT';

      showDialog(
          context: context,
          builder: (ctx) => StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                  title: const Text('Add Transaction'),
                  content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                                      }
                                  )
                              ],
                          )
                      ],
                  ),
                  actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      ElevatedButton(
                          onPressed: () {
                              final amount = double.tryParse(amountController.text) ?? 0.0;
                              if (amount > 0 && merchantController.text.isNotEmpty) {
                                  provider.addTransaction(amount, type, merchantController.text);
                                  Navigator.pop(ctx);
                              }
                          },
                          child: const Text('Add'),
                      ),
                  ],
              ),
          )
      );
  }

  Widget _buildSummaryCard(TransactionProvider provider) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              children: [
                const Text('Income', style: TextStyle(color: Colors.green)),
                Text(
                    '₹${provider.totalIncome.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)
                ),
              ],
            ),
            Container(height: 40, width: 1, color: Colors.grey),
            Column(
              children: [
                const Text('Expenses', style: TextStyle(color: Colors.red)),
                Text(
                    '₹${provider.totalExpense.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
