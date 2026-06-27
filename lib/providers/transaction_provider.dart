
import 'package:flutter/material.dart';
import '../models/transaction_model.dart';
import '../services/db_service.dart';
import '../services/sms_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class TransactionProvider with ChangeNotifier {
  final SmsService _smsService = SmsService();
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<TransactionModel> _transactions = [];
  bool _isLoading = false;
  
  TimeFilter _activeFilter = TimeFilter.all;
  DateTimeRange? _customDateRange;

  bool _isAutoSync = false;

  List<TransactionModel> get transactions => _transactions;
  bool get isLoading => _isLoading;
  TimeFilter get activeFilter => _activeFilter;
  bool get isAutoSync => _isAutoSync;
  
  // Computed Date Range based on filter
  DateTimeRange? get currentDateRange {
    if (_activeFilter == TimeFilter.custom) return _customDateRange;
    if (_activeFilter == TimeFilter.all) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_activeFilter) {
      case TimeFilter.today:
        return DateTimeRange(start: today, end: today.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1)));
      case TimeFilter.yesterday:
        final start = today.subtract(const Duration(days: 1));
        return DateTimeRange(start: start, end: today.subtract(const Duration(milliseconds: 1)));
      case TimeFilter.thisWeek:
        // Assume Monday start
        final start = today.subtract(Duration(days: today.weekday - 1));
        final end = start.add(const Duration(days: 7)).subtract(const Duration(milliseconds: 1));
        return DateTimeRange(start: start, end: end);
      case TimeFilter.lastWeek:
        final start = today.subtract(Duration(days: today.weekday - 1 + 7));
        final end = start.add(const Duration(days: 7)).subtract(const Duration(milliseconds: 1));
        return DateTimeRange(start: start, end: end);
      case TimeFilter.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 1).subtract(const Duration(milliseconds: 1));
        return DateTimeRange(start: start, end: end);
      case TimeFilter.lastMonth:
        final start = DateTime(now.year, now.month - 1, 1);
        final end = DateTime(now.year, now.month, 1).subtract(const Duration(milliseconds: 1));
        return DateTimeRange(start: start, end: end);
      case TimeFilter.thisYear:
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year + 1, 1, 1).subtract(const Duration(milliseconds: 1));
        return DateTimeRange(start: start, end: end);
      case TimeFilter.lastYear:
        final start = DateTime(now.year - 1, 1, 1);
        final end = DateTime(now.year, 1, 1).subtract(const Duration(milliseconds: 1));
        return DateTimeRange(start: start, end: end);
      default:
        return null;
    }
  }

  TransactionProvider() {
     _loadAutoSync();
  }

  // Load AutoSync pref
  Future<void> _loadAutoSync() async {
      final prefs = await SharedPreferences.getInstance();
      _isAutoSync = prefs.getBool('auto_sync') ?? false;
      notifyListeners();
      
      if (_isAutoSync) {
          syncSms();
      }
  }

  // Toggle AutoSync
  Future<void> toggleAutoSync(bool value) async {
      // Reflect the switch immediately, BEFORE persisting/syncing, so the
      // toggle never appears to hang while the sync runs.
      _isAutoSync = value;
      notifyListeners();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_sync', value);

      if (value) {
          syncSms();
      }
  }

  // Manual Transaction
  Future<void> addTransaction(double amount, String type, String merchant, {DateTime? date}) async {
      final txn = TransactionModel(
          amount: amount,
          type: type,
          merchant: merchant,
          timestamp: date ?? DateTime.now(),
          body: 'Manual Entry',
          source: 'MANUAL',
      );
      await _db.create(txn);
      await loadTransactions();
  }

  Future<void> clearAll() async {
      await _db.deleteAll();
      _transactions.clear();
      notifyListeners();
  }

  // Filtered List
  List<TransactionModel> get filteredTransactions {
    final range = currentDateRange;
    if (range == null) return _transactions;

    return _transactions.where((txn) {
      return txn.timestamp.isAfter(range.start.subtract(const Duration(milliseconds: 1))) && 
             txn.timestamp.isBefore(range.end.add(const Duration(milliseconds: 1)));
    }).toList();
  }

  double get totalIncome => filteredTransactions
      .where((t) => t.type == 'CREDIT')
      .fold(0.0, (sum, item) => sum + item.amount);

  double get totalExpense => filteredTransactions
      .where((t) => t.type == 'DEBIT')
      .fold(0.0, (sum, item) => sum + item.amount);
      
  void setFilter(TimeFilter filter, {DateTimeRange? customRange}) {
    _activeFilter = filter;
    if (filter == TimeFilter.custom && customRange != null) {
        _customDateRange = customRange;
    }
    notifyListeners();
  }

  Future<void> loadTransactions() async {
    _isLoading = true;
    notifyListeners();
    try {
        _transactions = await _db.readAllTransactions();
    } catch (e) {
        debugPrint(e.toString());
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> syncSms() async {
    _isLoading = true;
    notifyListeners();
    try {
        await _smsService.syncSms();
        await loadTransactions();
    } catch (e) {
        debugPrint(e.toString());
    }
    _isLoading = false;
    notifyListeners();
  }
}
