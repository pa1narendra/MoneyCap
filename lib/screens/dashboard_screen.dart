import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/transaction_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/filter_dialog.dart';
import '../widgets/balance_prompt_dialog.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/app_toast.dart';
import '../theme/app_theme.dart';
import '../services/balance_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import 'stats_screen.dart';
import 'reconciliation_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  StreamSubscription<String>? _notificationSub;
  bool _isBalanceDialogShown = false;
  bool _namePromptShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TransactionProvider>().loadTransactions();
      _checkBalancePrompt();
      _initializeNotifications();
    });
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  Future<void> _checkBalancePrompt() async {
    final balanceService = BalanceService();
    final prompt = await balanceService.checkBalancePrompt();

    if (prompt != null && mounted && !_isBalanceDialogShown) {
      _isBalanceDialogShown = true;
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => BalancePromptDialog(prompt: prompt),
      );
      _isBalanceDialogShown = false;

      if (saved == true && prompt.type == PromptType.closing && mounted) {
        _navigateToReconciliation(prompt.month);
      }
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      await NotificationService.instance.initialize();

      // Listen for taps (both local foreground notifications and FCM taps are
      // funnelled into this stream) BEFORE init so nothing is missed.
      _notificationSub = NotificationService.instance.onNotificationTap.listen(
        _handleNotificationPayload,
      );

      // App launched by tapping a locally shown notification.
      final initialPayload = await NotificationService.instance.getInitialPayload();
      if (initialPayload != null) {
        _handleNotificationPayload(initialPayload);
      }

      // Reminders are delivered via FCM push (reliable even on OEMs that block
      // local AlarmManager notifications). Subscribe + wire up tap handling.
      await PushService.instance.init();
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
    }
  }

  void _handleNotificationPayload(String payload) {
    final parts = payload.split(':');
    if (parts.length != 2) return;

    final type = parts[0] == 'opening' ? PromptType.opening : PromptType.closing;
    final month = parts[1];
    final monthDate = DateTime.parse('$month-01');
    final monthName = DateFormat('MMMM yyyy').format(monthDate);

    final prompt = BalancePrompt(type: type, month: month, monthName: monthName);

    if (mounted && !_isBalanceDialogShown) {
      _isBalanceDialogShown = true;
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => BalancePromptDialog(prompt: prompt),
      ).then((saved) {
        _isBalanceDialogShown = false;
        if (saved == true && type == PromptType.closing && mounted) {
          _navigateToReconciliation(month);
        }
      });
    }
  }

  void _navigateToReconciliation(String month) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReconciliationScreen(initialMonth: month)),
    );
  }

  void _showThemePicker(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(Icons.brightness_6),
                  SizedBox(width: AppSpacing.sm),
                  Text('Theme', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            for (final entry in const {
              ThemeMode.system: ('System default', Icons.brightness_auto),
              ThemeMode.light: ('Light', Icons.light_mode),
              ThemeMode.dark: ('Dark', Icons.dark_mode),
            }.entries)
              RadioListTile<ThemeMode>(
                value: entry.key,
                groupValue: settings.themeMode,
                onChanged: (m) {
                  settings.setThemeMode(m!);
                  Navigator.pop(ctx);
                },
                title: Text(entry.value.$1),
                secondary: Icon(entry.value.$2),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  void _showNameDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Welcome to MoneyCap 👋'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("What should we call you?"),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveName(ctx, controller.text),
              decoration: const InputDecoration(
                labelText: 'Your name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              context.read<SettingsProvider>().setUserName('');
              Navigator.pop(ctx);
            },
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => _saveName(ctx, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _saveName(BuildContext ctx, String name) {
    if (name.trim().isEmpty) return;
    context.read<SettingsProvider>().setUserName(name);
    Navigator.pop(ctx);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final settings = context.watch<SettingsProvider>();
    final cs = Theme.of(context).colorScheme;

    // First-launch: ask the user's name once (after the frame is built).
    if (settings.needsName && !_namePromptShown) {
      _namePromptShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showNameDialog());
    }

    final currentRange = provider.currentDateRange;
    String rangeLabel = provider.activeFilter.label;

    if (provider.activeFilter == TimeFilter.custom && currentRange != null) {
      rangeLabel = "${DateFormat('MMM d').format(currentRange.start)} - ${DateFormat('MMM d').format(currentRange.end)}";
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('MoneyCap'),
        actions: [
          Switch(
            value: provider.isAutoSync,
            onChanged: (val) {
              provider.toggleAutoSync(val);
              showToast(context, 'Auto Sync ${val ? "Enabled" : "Disabled"}');
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'stats') {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const StatsScreen()));
              } else if (value == 'reconciliation') {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const ReconciliationScreen()));
              } else if (value == 'theme') {
                _showThemePicker(context);
              } else if (value == 'reset') {
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
                          showToast(context, 'Data Reset Complete');
                        },
                        child: Text('Reset', style: TextStyle(color: cs.error)),
                      ),
                    ],
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'stats',
                child: Row(children: [Icon(Icons.bar_chart), SizedBox(width: 8), Text('Statistics')]),
              ),
              const PopupMenuItem(
                value: 'reconciliation',
                child: Row(children: [Icon(Icons.account_balance), SizedBox(width: 8), Text('Reconciliation')]),
              ),
              const PopupMenuItem(
                value: 'theme',
                child: Row(children: [Icon(Icons.brightness_6), SizedBox(width: 8), Text('Theme')]),
              ),
              const PopupMenuItem(
                value: 'reset',
                child: Row(children: [Icon(Icons.delete_forever, color: Colors.red), SizedBox(width: 8), Text('Reset Data')]),
              ),
            ],
          ),
        ],
      ),
      body: provider.isLoading
          ? const DashboardSkeleton()
          : RefreshIndicator(
              onRefresh: provider.syncSms,
              child: Column(
                children: [
                  // Personalized greeting — full width so long names aren't clipped.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        settings.greeting(),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _showFilterDialog(context, provider),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: cs.outlineVariant),
                                borderRadius: BorderRadius.circular(12),
                                color: cs.surfaceContainerHighest,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.calendar_today, size: 16, color: cs.onSurfaceVariant),
                                  const SizedBox(width: AppSpacing.sm),
                                  Flexible(
                                    child: Text(
                                      rangeLabel,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '${provider.filteredTransactions.length} items',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  _buildSummaryCard(context, provider),
                  Expanded(
                    child: provider.filteredTransactions.isEmpty
                        ? const Center(child: Text('No transactions in this period'))
                        : ListView.builder(
                            itemCount: provider.filteredTransactions.length,
                            itemBuilder: (context, index) {
                              final txn = provider.filteredTransactions[index];
                              final isDebit = txn.type == 'DEBIT';
                              final txnColor = isDebit
                                  ? AppColors.expense(cs.brightness)
                                  : AppColors.income(cs.brightness);
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: txnColor.withOpacity(0.15),
                                  child: Icon(
                                    isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                                    color: txnColor,
                                  ),
                                ),
                                title: Text(txn.merchant, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Row(
                                  children: [
                                    Icon(txn.source == 'SMS' ? Icons.message : Icons.person, size: 14, color: cs.onSurfaceVariant),
                                    const SizedBox(width: AppSpacing.xs),
                                    Text(DateFormat('yyyy-MM-dd HH:mm').format(txn.timestamp)),
                                  ],
                                ),
                                trailing: Text(
                                  '${isDebit ? '-' : '+'} ₹${txn.amount.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: txnColor,
                                    fontWeight: FontWeight.w700,
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
    FilterDialog.show(
      context,
      provider.activeFilter,
      (filter, range) {
        provider.setFilter(filter, customRange: range);
      },
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
              showToast(context, 'Synced!');
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
      ),
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
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
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
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, TransactionProvider provider) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: _summaryItem(context, 'Income', provider.totalIncome, AppColors.income(cs.brightness)),
            ),
            Container(height: 40, width: 1, color: cs.outlineVariant),
            Expanded(
              child: _summaryItem(context, 'Expenses', provider.totalExpense, AppColors.expense(cs.brightness)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(BuildContext context, String label, double amount, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '₹${amount.toStringAsFixed(2)}',
            maxLines: 1,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    );
  }
}
