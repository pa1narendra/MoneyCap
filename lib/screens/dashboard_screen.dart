import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/transaction_model.dart';
import '../providers/settings_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/backup_service.dart';
import '../services/balance_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../services/sms_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/balance_prompt_dialog.dart';
import '../widgets/filter_dialog.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/transaction_form.dart';
import '../widgets/transaction_sheet.dart';
import 'budgets_screen.dart';
import 'reconciliation_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
String formatMoney(double v) => _money.format(v);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  StreamSubscription<String>? _notificationSub;
  bool _isBalanceDialogShown = false;
  bool _searching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<TransactionProvider>().start();
      if (!mounted) return;
      await _checkBalancePrompt();
      await _initializeNotifications();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // "Automatic" includes coming back to the app, not just a cold start.
    if (state == AppLifecycleState.resumed) {
      context.read<TransactionProvider>().onResume();
    }
  }

  Future<void> _checkBalancePrompt() async {
    final prompt = await BalanceService().checkBalancePrompt();
    if (prompt == null || !mounted || _isBalanceDialogShown) return;
    _isBalanceDialogShown = true;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BalancePromptDialog(prompt: prompt),
    );
    _isBalanceDialogShown = false;
    if (saved == true && prompt.type == PromptType.closing && mounted) {
      await _handleClosingMismatch(prompt.month);
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      await NotificationService.instance.initialize();
      _notificationSub = NotificationService.instance.onNotificationTap.listen(_handlePayload);
      final initial = await NotificationService.instance.getInitialPayload();
      if (initial != null) _handlePayload(initial);
      if (!mounted) return;
      await PushService.instance.init(enabled: context.read<SettingsProvider>().pushReminders);
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
    }
  }

  void _handlePayload(String payload) {
    final prompt = BalancePrompt.fromPayload(payload);
    if (prompt == null || !mounted || _isBalanceDialogShown) return;
    _isBalanceDialogShown = true;
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BalancePromptDialog(prompt: prompt),
    ).then((saved) {
      _isBalanceDialogShown = false;
      if (saved == true && prompt.type == PromptType.closing && mounted) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => ReconciliationScreen(initialMonth: prompt.month)));
      }
    });
  }

  /// After a closing balance is entered, offer to add the missing
  /// transaction right here if the month doesn't reconcile.
  Future<void> _handleClosingMismatch(String month) async {
    final disc = await BalanceService().getDiscrepancy(month);
    if (disc == null || disc.discrepancy.abs() < 0.01 || !mounted) return;
    final provider = context.read<TransactionProvider>();
    final diff = disc.discrepancy;
    final isMissingCredit = diff > 0;
    final parts = month.split('-');
    final y = int.parse(parts[0]), m = int.parse(parts[1]);
    final draft = await showTransactionForm(
      context,
      title: "Balance doesn't match",
      submitLabel: 'Add',
      message: 'Your records are off by ${formatMoney(diff.abs())}. This looks like a missing '
          '${isMissingCredit ? "income" : "expense"}. Add it to reconcile.',
      amount: diff.abs(),
      type: isMissingCredit ? 'CREDIT' : 'DEBIT',
      date: DateTime(y, m + 1, 0),
      firstDate: DateTime(y, m, 1),
      lastDate: DateTime(y, m + 1, 0),
    );
    if (draft == null) return;
    await provider.addTransaction(draft.amount, draft.type, draft.merchant,
        date: draft.date, category: draft.category, transfer: draft.transfer);
    if (mounted) showToast(context, 'Missing transaction added');
  }

  Future<void> _addManual(TransactionProvider provider) async {
    final draft = await showTransactionForm(context, title: 'Add transaction', submitLabel: 'Add');
    if (draft == null) return;
    await provider.addTransaction(draft.amount, draft.type, draft.merchant,
        date: draft.date, category: draft.category, transfer: draft.transfer);
    if (mounted) showToast(context, 'Transaction added');
  }

  Future<void> _sync(TransactionProvider provider) async {
    final r = await provider.syncSms();
    if (!mounted) return;
    switch (r.status) {
      case SyncStatus.ok:
        showToast(context, r.inserted == 0 ? 'Up to date' : 'Added ${r.inserted} new');
      case SyncStatus.noPermission:
        showToast(context, 'Allow SMS access to sync', isError: true);
      case SyncStatus.error:
        showToast(context, 'Sync failed, try again', isError: true);
    }
  }

  Future<void> _exportCsv(TransactionProvider provider) async {
    if (provider.filteredTransactions.isEmpty) {
      showToast(context, 'Nothing to export in this view', isError: true);
      return;
    }
    try {
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final file = await BackupService.writeExportFile('moneycap_$stamp.csv', provider.buildCsv());
      await Share.shareXFiles([XFile(file.path)], subject: 'MoneyCap transactions');
    } catch (e) {
      if (mounted) showToast(context, 'Export failed', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final settings = context.watch<SettingsProvider>();
    final cs = Theme.of(context).colorScheme;
    final items = provider.filteredTransactions; // memoized; computed once per change

    final range = provider.currentDateRange;
    var rangeLabel = provider.activeFilter.label;
    if (provider.activeFilter == TimeFilter.custom && range != null) {
      rangeLabel = "${DateFormat('MMM d').format(range.start)} - ${DateFormat('MMM d').format(range.end)}";
    }

    final now = DateTime.now();
    final budgetAlerts = provider.budgetStatusFor(DateTime(now.year, now.month))
        .where((b) => b.fraction >= 0.9)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: cs.onSurface, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Search merchant, amount, category…',
                  hintStyle: TextStyle(color: cs.onSurfaceVariant),
                  border: InputBorder.none,
                ),
                onChanged: provider.setSearchQuery,
              )
            : const Text('MoneyCap'),
        bottom: provider.isSyncing
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(value: provider.syncProgress, minHeight: 3),
              )
            : null,
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            tooltip: _searching ? 'Close search' : 'Search',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _searchController.clear();
                provider.setSearchQuery('');
              }
            }),
          ),
          if (!_searching)
            PopupMenuButton<String>(
              onSelected: (value) {
                Widget? page;
                switch (value) {
                  case 'stats':
                    page = const StatsScreen();
                  case 'budgets':
                    page = const BudgetsScreen();
                  case 'reconciliation':
                    page = const ReconciliationScreen();
                  case 'settings':
                    page = const SettingsScreen();
                  case 'export':
                    _exportCsv(provider);
                }
                if (page != null) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => page!));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'stats', child: _MenuRow(Icons.bar_chart, 'Statistics')),
                PopupMenuItem(value: 'budgets', child: _MenuRow(Icons.savings_outlined, 'Budgets')),
                PopupMenuItem(value: 'reconciliation', child: _MenuRow(Icons.account_balance, 'Reconciliation')),
                PopupMenuItem(value: 'export', child: _MenuRow(Icons.download, 'Export CSV')),
                PopupMenuItem(value: 'settings', child: _MenuRow(Icons.settings_outlined, 'Settings')),
              ],
            ),
        ],
      ),
      body: provider.isLoading
          ? const DashboardSkeleton()
          : RefreshIndicator(
              onRefresh: () => _sync(provider),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                      child: Text(settings.greeting(),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  if (provider.lastSyncStatus == SyncStatus.noPermission)
                    SliverToBoxAdapter(child: _permissionBanner(context)),
                  SliverToBoxAdapter(child: _filterRow(context, provider, rangeLabel, items.length)),
                  if (provider.accounts.length > 1)
                    SliverToBoxAdapter(child: _accountChips(provider)),
                  SliverToBoxAdapter(child: _summaryCard(context, provider)),
                  for (final b in budgetAlerts)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                        child: Material(
                          color: b.over ? cs.errorContainer : cs.tertiaryContainer,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.savings_outlined,
                                color: b.over ? cs.onErrorContainer : cs.onTertiaryContainer),
                            title: Text(
                              b.over
                                  ? '${b.category}: over budget by ${formatMoney(b.spent - b.limit)}'
                                  : '${b.category}: ${(b.fraction * 100).round()}% of budget used',
                              style: TextStyle(
                                  color: b.over ? cs.onErrorContainer : cs.onTertiaryContainer),
                            ),
                            onTap: () => Navigator.push(
                                context, MaterialPageRoute(builder: (_) => const BudgetsScreen())),
                          ),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<TypeFilter>(
                          segments: const [
                            ButtonSegment(value: TypeFilter.all, label: Text('All')),
                            ButtonSegment(value: TypeFilter.income, label: Text('Income')),
                            ButtonSegment(value: TypeFilter.expense, label: Text('Expense')),
                          ],
                          selected: {provider.typeFilter},
                          onSelectionChanged: (s) => provider.setTypeFilter(s.first),
                          showSelectedIcon: false,
                        ),
                      ),
                    ),
                  ),
                  if (items.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: Text('No transactions in this period')),
                    )
                  else
                    SliverList.builder(
                      itemCount: items.length,
                      itemBuilder: (context, i) => _TransactionTile(
                        txn: items[i],
                        category: provider.categoryOf(items[i]),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 88)),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add or sync',
        onPressed: () => showModalBottomSheet(
          context: context,
          builder: (ctx) => SafeArea(
            child: Wrap(children: [
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Sync SMS now'),
                onTap: () {
                  Navigator.pop(ctx);
                  _sync(provider);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Add manually'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addManual(provider);
                },
              ),
            ]),
          ),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _permissionBanner(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: Material(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          leading: const Icon(Icons.sms_failed_outlined),
          title: const Text('SMS access is off'),
          subtitle: const Text('Transactions won\'t be captured automatically.'),
          trailing: TextButton(
            onPressed: () async {
              final provider = context.read<TransactionProvider>();
              final s = await Permission.sms.request();
              if (s.isGranted) {
                await provider.syncSms();
              } else if (s.isPermanentlyDenied) {
                await openAppSettings();
              }
            },
            child: const Text('Allow'),
          ),
        ),
      ),
    );
  }

  Widget _filterRow(BuildContext context, TransactionProvider provider, String label, int count) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => FilterDialog.show(context, provider.activeFilter,
                  (f, r) => provider.setFilter(f, customRange: r)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: cs.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                  color: cs.surfaceContainerHighest,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.calendar_today, size: 16, color: cs.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
                ]),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('$count items', style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _accountChips(TransactionProvider provider) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: const Text('All accounts'),
              selected: provider.accountFilter == null,
              onSelected: (_) => provider.setAccountFilter(null),
            ),
          ),
          for (final a in provider.accounts)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label: Text(a),
                selected: provider.accountFilter == a,
                onSelected: (sel) => provider.setAccountFilter(sel ? a : null),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryCard(BuildContext context, TransactionProvider provider) {
    final cs = Theme.of(context).colorScheme;
    Widget item(String label, double amount, Color color) => Column(children: [
          Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(formatMoney(amount),
                maxLines: 1,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
          ),
        ]);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(children: [
          Expanded(child: item('Income', provider.totalIncome, AppColors.income(cs.brightness))),
          Container(height: 40, width: 1, color: cs.outlineVariant),
          Expanded(child: item('Expenses', provider.totalExpense, AppColors.expense(cs.brightness))),
        ]),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuRow(this.icon, this.label);
  @override
  Widget build(BuildContext context) =>
      Row(children: [Icon(icon), const SizedBox(width: 8), Text(label)]);
}

class _TransactionTile extends StatelessWidget {
  final TransactionModel txn;
  final String category;
  const _TransactionTile({required this.txn, required this.category});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = txn.isTransfer
        ? cs.onSurfaceVariant
        : (txn.type == 'DEBIT' ? AppColors.expense(cs.brightness) : AppColors.income(cs.brightness));
    final icon = txn.isTransfer
        ? Icons.swap_horiz
        : (txn.type == 'DEBIT' ? Icons.arrow_upward : Icons.arrow_downward);
    final sign = txn.isTransfer ? '' : (txn.type == 'DEBIT' ? '- ' : '+ ');
    final meta = [
      DateFormat('d MMM, HH:mm').format(txn.timestamp),
      category,
      if (txn.account != null) txn.account!,
    ].join(' · ');
    return ListTile(
      onTap: () => showTransactionSheet(context, txn),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color),
      ),
      title: Text(txn.merchant,
          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Row(children: [
        Icon(txn.source == 'SMS' ? Icons.message : Icons.person, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
      trailing: Text(
        '$sign${formatMoney(txn.amount)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16),
      ),
    );
  }
}
