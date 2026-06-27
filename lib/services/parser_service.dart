
import '../models/transaction_model.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';

class ParserService {
  
  // Regex patterns
  // 1. Amount: Matches Rs. 100, INR 100, 100 INR, 100.00 etc.
  static final RegExp _amountRegex = RegExp(r'(?:Rs\.?|INR|₹)\s*(\d+(?:,\d+)*(?:\.\d{2})?)', caseSensitive: false);
  static final RegExp _amountRegex2 = RegExp(r'(\d+(?:,\d+)*(?:\.\d{2})?)\s*(?:Rs\.?|INR|₹)', caseSensitive: false);
  
  // 2. Type keywords — compiled ONCE (these run for every message, so building
  // them per-call was wasted work).
  static final RegExp _debitRegex = RegExp(r'\b(debited|spent|paid|sent|withdraw|purchased|paying)\b', caseSensitive: false);
  static final RegExp _creditRegex = RegExp(r'\b(credited|received|deposited|refund|inward|added)\b', caseSensitive: false);
  static final RegExp _transferRegex = RegExp(r'\b(transfer|transferred|txn)\b', caseSensitive: false);

  // Contextual amount fallback (e.g. "debited by 50") and numeric-sender check.
  static final RegExp _contextAmountRegex = RegExp(r'(?:debited|credited|sent|paid|transfer|transferred)\s+(?:by|of)?\s*(?:Rs\.?|INR|₹)?\s*(\d+(?:,\d+)*(?:\.\d{2})?)', caseSensitive: false);
  static final RegExp _numericAddressRegex = RegExp(r'^\+?\d+$');

  // 4. Merchant patterns (at, to, from)
  static final RegExp _merchantRegex = RegExp(r'(?:\bat\b|\bto\b|\bfrom\b)\s+([A-Za-z0-9\s\*\-]+?)(?:\.|,|is|on|with|using|ref|via|through|and|$)', caseSensitive: false);
  
  // Account/Bank info (optional, ensuring it's a bank sms)
  // static final RegExp _bankRegex = RegExp(r'\b(ac|a/c|account|bank|upi|wallet|card)\b', caseSensitive: false);

  // 5. Spam/Marketing keywords (To ignore)
  static final RegExp _spamRegex = RegExp(r'\b(claim|offer|won|prize|lottery|eligible|apply|marketing)\b', caseSensitive: false);

  TransactionModel? parseSms(SmsMessage message) =>
      parseFields(message.body, message.address, message.date);

  /// Plugin-free parse so it can run in a background isolate (via [compute]).
  TransactionModel? parseFields(String? rawBody, String? address, DateTime? date) {
    if (rawBody == null || rawBody.isEmpty) return null;
    String body = rawBody;

    // 1. Anti-Spam Check
    if (_spamRegex.hasMatch(body)) {
        // Double check: if it has "spent" or "debited", it might be real (e.g. "spent 500 on loan payment")
        // But usually "Claim 5000 loan" is spam.
        // Let's be safe: if it has "claim" or "offer", it's 99% spam.
        return null;
    }

    // 2. Determine Type (Strict Priority)
    
    // Explicit keywords
    bool hasDebitKeyword = _debitRegex.hasMatch(body);
    bool hasCreditKeyword = _creditRegex.hasMatch(body);

    // Ambiguous keywords
    bool hasTransfer = _transferRegex.hasMatch(body);
    
    String type = '';

    if (hasCreditKeyword) {
        type = 'CREDIT';
    } else if (hasDebitKeyword) {
        type = 'DEBIT';
    } else if (hasTransfer) {
        // "Transfer" is tricky. "Transfer to" = Debit, "Transfer from" = Credit (usually).
        // But often "Transfer from your account" = Debit.
        // Heuristic: If we lack explicit "debited/credited", "transfer" usually implies outgoing for a user checking their own phone.
        // OR we can check context. 
        // For now, let's treat generic "transfer" as DEBIT (standard BHIM/UPI behavior).
        type = 'DEBIT';
        
        // Exception: "Transfer from" + NOT "your account" -> Credit? Too risky.
        // Let's rely on the fact that most incoming transfers say "Received" or "Credited".
    } else {
        return null; // Not a transaction
    }

    // 3. Extract Amount
    double amount = 0.0;
    var amountMatch = _amountRegex.firstMatch(body);
    if (amountMatch != null) {
      String raw = amountMatch.group(1)!.replaceAll(',', '');
      amount = double.tryParse(raw) ?? 0.0;
    } else {
        var amountMatch2 = _amountRegex2.firstMatch(body);
        if (amountMatch2 != null) {
            String raw = amountMatch2.group(1)!.replaceAll(',', '');
            amount = double.tryParse(raw) ?? 0.0;
        } else {
            // Contextual fallback (for "debited by 50")
            var amountMatch3 = _contextAmountRegex.firstMatch(body);
            if (amountMatch3 != null) {
                String raw = amountMatch3.group(1)!.replaceAll(',', '');
                amount = double.tryParse(raw) ?? 0.0;
            } else {
                return null;
            }
        }
    }

    // 4. Extract Merchant
    String merchant = 'Unknown';
    var merchantMatch = _merchantRegex.firstMatch(body);
    if (merchantMatch != null) {
        merchant = merchantMatch.group(1)!.trim();
    } else {
       if (address != null && !_numericAddressRegex.hasMatch(address)) {
           merchant = address;
       }
    }
    
    if (merchant.length > 20) {
        merchant = '${merchant.substring(0, 20)}...';
    }

    return TransactionModel(
      amount: amount,
      type: type,
      merchant: merchant,
      timestamp: date ?? DateTime.now(),
      body: body,
      source: 'SMS',
    );
  }
}

/// Top-level entry point for `compute()` — parses a batch of raw SMS records
/// on a background isolate and returns ready-to-insert transaction maps.
/// Each input record is `{ 'body': String?, 'address': String?, 'date': int? }`
/// where `date` is millisecondsSinceEpoch. Runs off the UI thread so a large
/// first-time import doesn't freeze the app.
List<Map<String, dynamic>> parseSmsBatch(List<Map<String, dynamic>> raw) {
  final parser = ParserService();
  final out = <Map<String, dynamic>>[];
  for (final r in raw) {
    final dateMs = r['date'] as int?;
    final txn = parser.parseFields(
      r['body'] as String?,
      r['address'] as String?,
      dateMs != null ? DateTime.fromMillisecondsSinceEpoch(dateMs) : null,
    );
    if (txn != null) {
      final map = txn.toMap()..remove('id');
      out.add(map);
    }
  }
  return out;
}
