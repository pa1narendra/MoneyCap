import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/transaction_model.dart';
import '../providers/transaction_provider.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';

/// SMS that repeat a payment already recorded. They count nowhere, but stay
/// here so a wrong match can be put back.
class HiddenDuplicatesScreen extends StatefulWidget {
  const HiddenDuplicatesScreen({super.key});

  @override
  State<HiddenDuplicatesScreen> createState() => _HiddenDuplicatesScreenState();
}

class _HiddenDuplicatesScreenState extends State<HiddenDuplicatesScreen> {
  final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  List<TransactionModel>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await DatabaseHelper.instance.readHiddenDuplicates();
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _restore(TransactionModel t) async {
    final provider = context.read<TransactionProvider>();
    await DatabaseHelper.instance.restoreDuplicate(t);
    await provider.loadTransactions();
    await _load();
    if (mounted) showToast(context, 'Transaction restored');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: const Text('Hidden duplicates')),
      body: rows == null
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text('No duplicate messages found.',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: rows.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Text(
                        'These messages repeat a payment that is already recorded, so they '
                        'aren\'t counted. If one is really a separate payment, tap Restore.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      );
                    }
                    final t = rows[i - 1];
                    return Card(
                      elevation: 0,
                      margin: EdgeInsets.zero,
                      color: cs.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: Text(_money.format(t.amount),
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                            ),
                            Text(DateFormat('d MMM yyyy, HH:mm').format(t.timestamp),
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                          ]),
                          const SizedBox(height: AppSpacing.xs),
                          Text(t.body, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(onPressed: () => _restore(t), child: const Text('Restore')),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}
