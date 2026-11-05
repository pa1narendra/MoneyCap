import '../models/transaction_model.dart';

/// Resolves a transaction's category:
///   1. the user's per-transaction override (`txn.category`),
///   2. the user's merchant rules (lowercase substring -> category),
///   3. built-in keyword rules for common Indian merchants,
///   4. a fallback by kind/type.
class Categories {
  Categories._();

  static const food = 'Food & Dining';
  static const groceries = 'Groceries';
  static const shopping = 'Shopping';
  static const transport = 'Transport';
  static const fuel = 'Fuel';
  static const bills = 'Bills & Utilities';
  static const entertainment = 'Entertainment';
  static const health = 'Health';
  static const travel = 'Travel';
  static const rent = 'Rent';
  static const education = 'Education';
  static const emi = 'EMI & Loans';
  static const investments = 'Investments';
  static const cash = 'Cash';
  static const transfers = 'Transfers';
  static const income = 'Income';
  static const other = 'Other';

  /// Categories a user can pick for an expense, in display order.
  static const expenseCategories = [
    food, groceries, shopping, transport, fuel, bills, entertainment, health,
    travel, rent, education, emi, investments, cash, other,
  ];
  static const all = [...expenseCategories, income, transfers];

  // Order matters: the first matching keyword wins.
  static const _builtIn = <String, String>{
    'swiggy': food, 'zomato': food, 'dominos': food, 'domino': food,
    'mcdonald': food, 'kfc': food, 'starbucks': food, 'chai': food,
    'cafe': food, 'restaurant': food, 'eatsure': food, 'burger': food,
    'pizza': food,
    'blinkit': groceries, 'zepto': groceries, 'bigbasket': groceries,
    'instamart': groceries, 'dmart': groceries, 'big bazaar': groceries,
    'reliance fresh': groceries, 'jiomart': groceries, 'more retail': groceries,
    'grocery': groceries, 'kirana': groceries, 'stores': groceries,
    'amazon': shopping, 'flipkart': shopping, 'myntra': shopping,
    'ajio': shopping, 'meesho': shopping, 'nykaa': shopping, 'tata cliq': shopping,
    'croma': shopping, 'decathlon': shopping, 'ikea': shopping,
    'uber': transport, 'ola': transport, 'rapido': transport, 'metro': transport,
    'fastag': transport, 'namma yatri': transport, 'redbus': transport,
    'petrol': fuel, 'fuel': fuel, 'indian oil': fuel, 'iocl': fuel,
    'bharat petroleum': fuel, 'bpcl': fuel, 'hpcl': fuel, 'hp pay': fuel,
    'shell': fuel,
    'airtel': bills, 'jio': bills, 'vodafone': bills, 'vi ': bills, 'bsnl': bills,
    'electricity': bills, 'bescom': bills, 'tata power': bills, 'adani': bills,
    'gas': bills, 'broadband': bills, 'act fibernet': bills, 'recharge': bills,
    'bbps': bills, 'water': bills,
    'netflix': entertainment, 'spotify': entertainment, 'hotstar': entertainment,
    'prime video': entertainment, 'youtube': entertainment, 'pvr': entertainment,
    'inox': entertainment, 'bookmyshow': entertainment, 'cinema': entertainment,
    'apollo': health, 'pharmeasy': health, '1mg': health, 'netmeds': health,
    'medplus': health, 'hospital': health, 'clinic': health, 'pharmacy': health,
    'diagnostic': health,
    'makemytrip': travel, 'goibibo': travel, 'cleartrip': travel, 'irctc': travel,
    'indigo': travel, 'air india': travel, 'akasa': travel, 'oyo': travel,
    'airbnb': travel, 'yatra': travel, 'ixigo': travel,
    'rent': rent, 'nobroker': rent,
    'school': education, 'college': education, 'udemy': education,
    'coursera': education, 'byju': education, 'tuition': education,
    'emi': emi, 'loan': emi, 'bajaj fin': emi,
    'zerodha': investments, 'groww': investments, 'upstox': investments,
    'mutual fund': investments, 'sip': investments, 'kuvera': investments,
    'nps': investments, 'ppf': investments,
    'atm': cash, 'cash': cash,
  };

  /// Lowercased merchant used for grouping, so "AMAZON" and "Amazon" match.
  static String merchantKey(String merchant) =>
      merchant.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static String resolve(TransactionModel t, Map<String, String> userRules) {
    if (t.category != null && t.category!.isNotEmpty) return t.category!;
    if (t.isTransfer) return transfers;
    final m = ' ${merchantKey(t.merchant)} ';
    for (final e in userRules.entries) {
      if (e.key.isNotEmpty && m.contains(e.key)) return e.value;
    }
    if (t.type == 'CREDIT') return income;
    for (final e in _builtIn.entries) {
      // Short keywords must match a whole word ("ola" is not "Motorola").
      final hit = e.key.length <= 4
          ? RegExp('\\b${RegExp.escape(e.key.trim())}\\b').hasMatch(m)
          : m.contains(e.key);
      if (hit) return e.value;
    }
    return other;
  }
}
