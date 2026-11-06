import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';
import '../services/background_sync.dart';
import '../services/backup_service.dart';
import '../services/category_service.dart';
import '../services/parser_service.dart';
import '../services/db_service.dart';
import '../services/insights_service.dart';
import '../services/sms_service.dart';
import '../services/widget_service.dart';

enum TimeFilter {
  all('All'),
  today('Today'),
  yesterday('Yesterday'),
  thisWeek('This Week'),
  lastWeek('Last Week'),
  thisMonth('This Month'),
  lastMonth('Last Month'),
  thisYear('This Year'),
  lastYear('Last Year'),
  custom('Custom Range');

  final String label;
  const TimeFilter(this.label);
}

/// Quick income/expense toggle for the transaction list.
enum TypeFilter { all, income, expense }

class TransactionProvider with ChangeNotifier {
  static const _kAutoSync = 'auto_sync';

  final SmsService _smsService;
  final DatabaseHelper _db = DatabaseHelper.instance;

  TransactionProvider({SmsService? smsService, bool loadPrefs = true})
      : _smsService = smsService ?? SmsService() {
    _prefsReady = loadPrefs ? _loadPrefs() : Future.value();
  }

  late final Future<void> _prefsReady;

  List<TransactionModel> _transactions = const [];
  Map<String, String> _rules = const {};
  Map<String, ({String name, bool isSelf})> _names = const {};
  Map<String, double> _budgets = const {};
  bool _isLoading = false;
  bool _isSyncing = false;
  double? _syncProgress;
  SyncStatus? _lastSyncStatus;

  TimeFilter _activeFilter = TimeFilter.thisMonth;
  DateTimeRange? _customDateRange;
  String _searchQuery = '';
  TypeFilter _typeFilter = TypeFilter.all;
  String? _accountFilter; // null = all accounts
  bool _isAutoSync = true;

  // ---- memoized views (invalidated whenever data or filters change) ----
  List<TransactionModel>? _baseCache;
  List<TransactionModel>? _filteredCache;
  List<String>? _accountsCache;
  ({double income, double expense})? _totalsCache;

  void _invalidate() {
    _baseCache = null;
    _filteredCache = null;
    _totalsCache = null;
  }

  @override
  void notifyListeners() {
    _invalidate();
    super.notifyListeners();
  }

  List<TransactionModel> get transactions => _transactions;
  Map<String, String> get categoryRules => _rules;
  Map<String, double> get budgets => _budgets;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  double? get syncProgress => _syncProgress;
  SyncStatus? get lastSyncStatus => _lastSyncStatus;
  TimeFilter get activeFilter => _activeFilter;
  String get searchQuery => _searchQuery;
  TypeFilter get typeFilter => _typeFilter;
  String? get accountFilter => _accountFilter;
  bool get isAutoSync => _isAutoSync;

  /// Distinct accounts seen in the data, most used first.
  List<String> get accounts {
    if (_accountsCache != null) return _accountsCache!;
    final counts = <String, int>{};
    for (final t in _transactions) {
      if (t.account != null) counts[t.account!] = (counts[t.account!] ?? 0) + 1;
    }
    return _accountsCache = (counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!)));
  }

  String categoryOf(TransactionModel t) => Categories.resolve(t, _rules);

  DateTimeRange? get currentDateRange {
    if (_activeFilter == TimeFilter.custom) return _customDateRange;
    if (_activeFilter == TimeFilter.all) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTimeRange r(DateTime s, DateTime e) =>
        DateTimeRange(start: s, end: e.subtract(const Duration(milliseconds: 1)));
    switch (_activeFilter) {
      case TimeFilter.today:
        return r(today, today.add(const Duration(days: 1)));
      case TimeFilter.yesterday:
        return r(today.subtract(const Duration(days: 1)), today);
      case TimeFilter.thisWeek:
        final s = today.subtract(Duration(days: today.weekday - 1));
        return r(s, s.add(const Duration(days: 7)));
      case TimeFilter.lastWeek:
        final s = today.subtract(Duration(days: today.weekday - 1 + 7));
        return r(s, s.add(const Duration(days: 7)));
      case TimeFilter.thisMonth:
        return r(DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
      case TimeFilter.lastMonth:
        return r(DateTime(now.year, now.month - 1), DateTime(now.year, now.month));
      case TimeFilter.thisYear:
        return r(DateTime(now.year), DateTime(now.year + 1));
      case TimeFilter.lastYear:
        return r(DateTime(now.year - 1), DateTime(now.year));
      default:
        return null;
    }
  }

  // ---------------- prefs / auto-sync ----------------

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isAutoSync = prefs.getBool(_kAutoSync) ?? true;
    notifyListeners();
  }

  /// Sync when the app comes back to the foreground (if auto-sync is on).
  Future<void> onResume() async {
    await _prefsReady;
    if (_isAutoSync && !_isSyncing && await SmsService.hasPermission()) await syncSms();
  }

  /// Called once the dashboard is visible: loads data and, if enabled and
  /// permitted, syncs.
  ///
  /// [beforeRescan] runs first when an update needs to re-read the inbox, so
  /// the user can back up before SMS rows are cleared.
  Future<void> start({Future<void> Function()? beforeRescan}) async {
    await _prefsReady;
    await Future.wait([loadTransactions(), _loadRulesAndBudgets()]);
    if (await SmsService.isRescanPending()) {
      await beforeRescan?.call();
      await SmsService.confirmRescan();
    }
    if (_isAutoSync && await SmsService.hasPermission()) await syncSms();
    await BackgroundSync.setEnabled(_isAutoSync && await SmsService.hasPermission());
  }

  Future<void> toggleAutoSync(bool value) async {
    _isAutoSync = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoSync, value);
    await BackgroundSync.setEnabled(value && await SmsService.hasPermission());
    if (value) await syncSms();
  }

  // ---------------- loading / syncing ----------------

  Future<void> loadTransactions() async {
    final firstLoad = _transactions.isEmpty;
    if (firstLoad) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      _transactions = await _db.readAllTransactions();
      _accountsCache = null;
    } catch (e) {
      debugPrint('loadTransactions failed: $e');
    }
    _isLoading = false;
    notifyListeners();
    WidgetService.refresh();
  }

  Future<void> _loadRulesAndBudgets() async {
    _names = await _db.getMerchantNames();
    _rules = await _db.getCategoryRules();
    _budgets = await _db.getBudgets();
    notifyListeners();
  }

  /// Returns the sync outcome so the UI can explain a missing permission.
  Future<SyncResult> syncSms() async {
    if (_isSyncing) return const SyncResult(SyncStatus.ok);
    _isSyncing = true;
    _syncProgress = null;
    notifyListeners();
    final result = await _smsService.syncSms(onProgress: (p) {
      _syncProgress = p;
      notifyListeners();
    });
    _lastSyncStatus = result.status;
    if (result.status == SyncStatus.ok) await loadTransactions();
    _isSyncing = false;
    _syncProgress = null;
    notifyListeners();
    return result;
  }

  // ---------------- editing ----------------

  Future<void> addTransaction(double amount, String type, String merchant,
      {DateTime? date, String? category, String? account, bool transfer = false}) async {
    await _db.create(TransactionModel(
      amount: amount,
      type: type,
      merchant: merchant.trim(),
      timestamp: date ?? DateTime.now(),
      body: 'Manual Entry',
      source: 'MANUAL',
      category: category,
      account: account,
      kind: transfer ? TransactionModel.kindTransfer : TransactionModel.kindNormal,
    ));
    await loadTransactions();
  }

  Future<void> updateTransaction(TransactionModel txn) async {
    await _db.update(txn);
    await loadTransactions();
  }

  Future<void> deleteTransaction(int id) async {
    await _db.delete(id);
    await loadTransactions();
  }

  Future<String> bodyOf(TransactionModel t) async =>
      t.id == null ? t.body : await _db.readBody(t.id!);

  /// Deletes SMS-imported rows only, then re-imports from the inbox.
  /// Manual entries, balances, categories and budgets are kept.
  Future<void> resetSmsData() async {
    await _db.deleteSmsTransactions();
    await SmsService.clearWatermark();
    await loadTransactions();
    if (await SmsService.hasPermission()) await syncSms();
  }

  // ---------------- names ----------------

  /// Text the SMS uses for this transaction's merchant.
  String smsNameOf(TransactionModel t) => t.originalMerchant ?? t.merchant;

  /// Labels the app made up rather than read, and rows with no name at all,
  /// have nothing that identifies a person, so a name can't follow them.
  bool canName(TransactionModel t) =>
      t.source == 'SMS' &&
      !const {'Unknown', 'Refund', 'Reversal', 'Salary', ParserService.cardBillMerchant}
          .contains(smsNameOf(t));

  /// Is this merchant marked as the user's own account?
  bool isSelf(TransactionModel t) => _names[Categories.merchantKey(smsNameOf(t))]?.isSelf ?? false;

  /// Names every transaction from this merchant, past and future. [isSelf]
  /// makes them transfers, because it's the user's own account.
  Future<void> setMerchantName(TransactionModel t, String name, {required bool isSelf}) async {
    await _db.setMerchantName(smsNameOf(t), name, isSelf: isSelf);
    await _loadRulesAndBudgets();
    await loadTransactions();
  }

  // ---------------- categories & budgets ----------------

  /// Sets [category] on [txn]. With [applyToMerchant] it becomes a rule for
  /// every transaction from that merchant (current and future) instead.
  Future<void> setCategory(TransactionModel txn, String category,
      {bool applyToMerchant = false}) async {
    if (applyToMerchant && txn.merchant != 'Unknown') {
      await _db.setCategoryRule(Categories.merchantKey(txn.merchant), category);
      if (txn.category != null) await _db.update(txn.copyWith(clearCategory: true));
      await _loadRulesAndBudgets();
      await loadTransactions();
    } else {
      await updateTransaction(txn.copyWith(category: category));
    }
  }

  Future<void> setRule(String pattern, String category) async {
    if (pattern.trim().isEmpty) return;
    await _db.setCategoryRule(pattern, category);
    await _loadRulesAndBudgets();
  }

  Future<void> deleteRule(String pattern) async {
    await _db.deleteCategoryRule(pattern);
    await _loadRulesAndBudgets();
  }

  Future<void> setBudget(String category, double limit) async {
    await _db.setBudget(category, limit);
    await _loadRulesAndBudgets();
  }

  Future<void> deleteBudget(String category) async {
    await _db.deleteBudget(category);
    await _loadRulesAndBudgets();
  }

  List<BudgetStatus> budgetStatusFor(DateTime month) => Insights.budgetStatus(
      _budgets, Insights.spendByCategory(_transactions, _rules, month: month));

  // ---------------- filters ----------------

  void setFilter(TimeFilter filter, {DateTimeRange? customRange}) {
    _activeFilter = filter;
    if (filter == TimeFilter.custom && customRange != null) {
      // The date picker's end is midnight; include all of that last day.
      final e = customRange.end;
      _customDateRange = DateTimeRange(
          start: customRange.start, end: DateTime(e.year, e.month, e.day, 23, 59, 59, 999));
    }
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setTypeFilter(TypeFilter type) {
    _typeFilter = type;
    notifyListeners();
  }

  void setAccountFilter(String? account) {
    _accountFilter = account;
    notifyListeners();
  }

  /// Date range + account + search. Totals use this, so both income and
  /// expense always show regardless of the list's income/expense toggle.
  List<TransactionModel> get _baseFiltered {
    if (_baseCache != null) return _baseCache!;
    final range = currentDateRange;
    final startMs = range?.start.millisecondsSinceEpoch;
    final endMs = range?.end.millisecondsSinceEpoch;
    final q = _searchQuery.trim().toLowerCase();
    return _baseCache = _transactions.where((t) {
      if (range != null) {
        final ms = t.timestamp.millisecondsSinceEpoch;
        if (ms < startMs! || ms > endMs!) return false;
      }
      if (_accountFilter != null && t.account != _accountFilter) return false;
      if (q.isNotEmpty &&
          !t.merchant.toLowerCase().contains(q) &&
          !t.amount.toStringAsFixed(2).contains(q) &&
          !(t.originalMerchant?.toLowerCase().contains(q) ?? false) &&
          !categoryOf(t).toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  /// Everything in the current date/account/search view, ignoring the
  /// income/expense toggle (used by Statistics).
  List<TransactionModel> get periodTransactions => _baseFiltered;

  /// What the list shows: base filter + the income/expense toggle. Transfers
  /// show under "All" only.
  List<TransactionModel> get filteredTransactions {
    if (_filteredCache != null) return _filteredCache!;
    final base = _baseFiltered;
    return _filteredCache = switch (_typeFilter) {
      TypeFilter.income => base.where((t) => t.isIncome).toList(growable: false),
      TypeFilter.expense => base.where((t) => t.isExpense).toList(growable: false),
      TypeFilter.all => base,
    };
  }

  ({double income, double expense}) get _totals {
    if (_totalsCache != null) return _totalsCache!;
    double inc = 0, exp = 0;
    for (final t in _baseFiltered) {
      if (t.isIncome) inc += t.amount;
      if (t.isExpense) exp += t.amount;
    }
    return _totalsCache = (income: inc, expense: exp);
  }

  double get totalIncome => _totals.income;
  double get totalExpense => _totals.expense;

  // ---------------- export / backup ----------------

  /// CSV of the current date/account/search view. Text cells that start with
  /// = + - @ are prefixed with ' so spreadsheet apps don't run them as
  /// formulas (CSV injection).
  String buildCsv() {
    String cell(String s) {
      var v = s;
      if (v.isNotEmpty && '=+-@\t\r'.contains(v[0])) v = "'$v";
      return '"${v.replaceAll('"', '""')}"';
    }

    final buf = StringBuffer('Date,Type,Kind,Category,Merchant,Account,Amount,Source\n');
    for (final t in _baseFiltered) {
      buf.writeln([
        t.timestamp.toIso8601String(),
        t.type,
        t.kind,
        cell(categoryOf(t)),
        cell(t.merchant),
        cell(t.account ?? ''),
        t.amount.toStringAsFixed(2),
        t.source,
      ].join(','));
    }
    return buf.toString();
  }

  Future<String> exportBackupJson() => BackupService.encode();

  Future<void> restoreBackup(String json) async {
    await BackupService.restore(json);
    // Re-scan the inbox afterwards: dedup keys skip what's restored, and
    // anything that arrived after the backup was taken comes back.
    await SmsService.clearWatermark();
    await _loadRulesAndBudgets();
    await loadTransactions();
  }
}
