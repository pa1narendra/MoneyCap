
class TransactionModel {
  int? id;
  double amount;
  String type; // 'CREDIT' or 'DEBIT'
  String merchant;
  DateTime timestamp;
  String body;
  String source; // 'SMS' or 'MANUAL'
  String? dedupKey; // stable signature so re-delivered SMS collapse to one row

  TransactionModel({
    this.id,
    required this.amount,
    required this.type,
    required this.merchant,
    required this.timestamp,
    required this.body,
    this.source = 'SMS', // Default to SMS for backward compatibility if needed, but we will migrate DB
    this.dedupKey,
  });

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
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      amount: map['amount'],
      type: map['type'],
      merchant: map['merchant'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      body: map['body'],
      source: map['source'] ?? 'SMS', // Default for old records
      dedupKey: map['dedup_key'],
    );
  }
}
