
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/transaction_provider.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    // Use filtered transactions or all? Usually analytics is on all or filtered. Let's use filtered.
    final txns = provider.filteredTransactions.where((t) => t.type == 'DEBIT').toList();
    
    // 1. Group by merchant for Pie Chart (Total Cost)
    final Map<String, double> merchantExpenses = {};
    // 2. Group by merchant for Repeated Payments (Count + Total)
    final Map<String, int> merchantCounts = {};

    for (var txn in txns) {
        merchantExpenses[txn.merchant] = (merchantExpenses[txn.merchant] ?? 0) + txn.amount;
        merchantCounts[txn.merchant] = (merchantCounts[txn.merchant] ?? 0) + 1;
    }

    // Sort for Pie Chart
    final sortedExpenses = merchantExpenses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    // Sort for Repeated Payments (Frequency > 1, sort by frequency desc)
    final repeatedPayments = merchantCounts.entries
        .where((e) => e.value > 1)
        .map((e) {
            return _RepeatedPayment(
                merchant: e.key,
                count: e.value,
                totalAmount: merchantExpenses[e.key] ?? 0.0,
            );
        })
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    final topExpenses = sortedExpenses.take(5).toList();
    final totalExpense = provider.totalExpense;

    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             _buildSectionTitle('Top Spending Categories'),
             const SizedBox(height: 20),
            if (totalExpense > 0)
            SizedBox(
              height: 250,
              child: PieChart(
                PieChartData(
                  sections: topExpenses.map((e) {
                    final color = Colors.primaries[topExpenses.indexOf(e) % Colors.primaries.length];
                    
                    return PieChartSectionData(
                      color: color,
                      value: e.value,
                      title: '${(e.value / totalExpense * 100).toStringAsFixed(0)}%',
                      radius: 60,
                      titleStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    );
                  }).toList(),
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
             const SizedBox(height: 20),
            // Legend
            ...topExpenses.map((e) {
                 final color = Colors.primaries[topExpenses.indexOf(e) % Colors.primaries.length];
                 return ListTile(
                     leading: CircleAvatar(backgroundColor: color, radius: 10),
                     title: Text(e.key),
                     trailing: Text('₹${e.value.toStringAsFixed(2)}'),
                 );
            }),
            if (topExpenses.isEmpty) const Center(child: Text("No expenses to chart")),
            
            const Divider(height: 40),
            
            _buildSectionTitle('Repeated Payments'),
            const Text('Merchants you have paid multiple times.'),
            const SizedBox(height: 10),
            if (repeatedPayments.isEmpty) 
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(child: Text('No repeated payments found.')),
                ),
            
            ...repeatedPayments.map((rp) {
                return Card(
                    child: ListTile(
                        leading: CircleAvatar(
                            backgroundColor: Colors.blue.withOpacity(0.2),
                            foregroundColor: Colors.blue,
                            child: Text(rp.count.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        title: Text(rp.merchant, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${rp.count} transactions'),
                        trailing: Text(
                            '₹${rp.totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                    ),
                );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
      return Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold));
  }
}

class _RepeatedPayment {
    final String merchant;
    final int count;
    final double totalAmount;

    _RepeatedPayment({required this.merchant, required this.count, required this.totalAmount});
}
