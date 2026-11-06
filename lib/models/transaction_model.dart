class TransactionModel {
  static const kindNormal = 'NORMAL';
  static const kindTransfer = 'TRANSFER';
  /// Another SMS already reports this payment. Hidden everywhere and counted
  /// nowhere, but kept so it can be restored from Settings.
  static const kindDuplicate = 'DUPLICATE';

  int? id;
  double amount;
  String type; // 'CREDIT' or 'DEBIT' (direction of money for the account)
  String merchant;
  DateTime timestamp;
  String body;
  String source; // 'SMS' or 'MANUAL'
  String? dedupKey; // stable signature so re-delivered SMS collapse to one row
  /// NORMAL counts toward income/expense. TRANSFER (own-account moves, card
  /// bill payments) is shown but excluded from totals so nothing is counted
  /// twice.
  String kind;
  /// Masked account/card suffix from the SMS, e.g. `XX1234`. Null when the
  /// message doesn't name one (or for manual entries without an account).
  String? account;
  /// User-chosen category override. Null means "use the merchant rules".
  String? category;
  /// When the user named this merchant: the text the SMS actually says. Then
  /// [merchant] holds the given name. Never stored on the row itself.
  String? originalMerchant;

  TransactionModel({
    this.id,
    required this.amount,
    required this.type,
    required this.merchant,
    required this.timestamp,
    required this.body,
    this.source = 'SMS',
    this.dedupKey,
    this.kind = kindNormal,
    this.account,
    this.category,
    this.originalMerchant,
  });

  /// A credit card: spending here isn't in any bank balance until the bill is
  /// paid. Debit cards are labelled `Debit`, because they are bank money.
  static bool isCardAccount(String? account) => account?.contains('Card ') ?? false;

  /// A bank account you can reconcile a balance against.
  static bool isBankAccount(String? account) => account?.contains('A/c ') ?? false;

  bool get isTransfer => kind == kindTransfer;
  bool get isExpense => type == 'DEBIT' && kind == kindNormal;
  bool get isIncome => type == 'CREDIT' && kind == kindNormal;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'type': type,
      'merchant': merchant,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'body': body,
      'source': source,
      'dedup_key': dedupKey,
      'kind': kind,
      'account': account,
      'category': category,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      type: map['type'] as String,
      merchant: map['merchant'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      body: map['body'] as String,
      source: (map['source'] as String?) ?? 'SMS',
      dedupKey: map['dedup_key'] as String?,
      kind: (map['kind'] as String?) ?? kindNormal,
      account: map['account'] as String?,
      category: map['category'] as String?,
    );
  }

  TransactionModel copyWith({
    double? amount,
    String? type,
    String? merchant,
    DateTime? timestamp,
    String? kind,
    String? account,
    String? category,
    bool clearCategory = false,
  }) {
    return TransactionModel(
      id: id,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      merchant: merchant ?? this.merchant,
      timestamp: timestamp ?? this.timestamp,
      body: body,
      source: source,
      dedupKey: dedupKey,
      kind: kind ?? this.kind,
      account: account ?? this.account,
      category: clearCategory ? null : (category ?? this.category),
      originalMerchant: originalMerchant,
    );
  }
}
