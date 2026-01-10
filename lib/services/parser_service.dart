
import '../models/transaction_model.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';

class ParserService {
  
  // Regex patterns
  // 1. Amount: Matches Rs. 100, INR 100, 100 INR, 100.00 etc.
  static final RegExp _amountRegex = RegExp(r'(?:Rs\.?|INR|₹)\s*(\d+(?:,\d+)*(?:\.\d{2})?)', caseSensitive: false);
  static final RegExp _amountRegex2 = RegExp(r'(\d+(?:,\d+)*(?:\.\d{2})?)\s*(?:Rs\.?|INR|₹)', caseSensitive: false);
  
  // 2. Debit keywords
  static final RegExp _debitRegex = RegExp(r'\b(debited|spent|paid|sent|withdraw|purchased|txn|payment|dr|transfer|transferred|paying)\b', caseSensitive: false);

  // 3. Credit keywords
  static final RegExp _creditRegex = RegExp(r'\b(credited|received|deposited|refund|added|cr|inward)\b', caseSensitive: false);

  // 4. Merchant patterns (at, to, from)
  static final RegExp _merchantRegex = RegExp(r'(?:\bat\b|\bto\b|\bfrom\b)\s+([A-Za-z0-9\s\*\-]+?)(?:\.|,|is|on|with|using|ref|via|through|and|$)', caseSensitive: false);
  
  // Account/Bank info (optional, ensuring it's a bank sms)
  // static final RegExp _bankRegex = RegExp(r'\b(ac|a/c|account|bank|upi|wallet|card)\b', caseSensitive: false);

  // 5. Spam/Marketing keywords (To ignore)
  static final RegExp _spamRegex = RegExp(r'\b(claim|offer|won|prize|lottery|eligible|apply|marketing)\b', caseSensitive: false);

  TransactionModel? parseSms(SmsMessage message) {
    if (message.body == null || message.body!.isEmpty) return null;
    String body = message.body!;

    // 1. Anti-Spam Check
    if (_spamRegex.hasMatch(body)) {
        // Double check: if it has "spent" or "debited", it might be real (e.g. "spent 500 on loan payment")
        // But usually "Claim 5000 loan" is spam.
        // Let's be safe: if it has "claim" or "offer", it's 99% spam.
        return null;
    }

    // 2. Determine Type (Strict Priority)
    
    // Explicit keywords
    bool hasDebitKeyword = RegExp(r'\b(debited|spent|paid|sent|withdraw|purchased|paying)\b', caseSensitive: false).hasMatch(body);
    bool hasCreditKeyword = RegExp(r'\b(credited|received|deposited|refund|inward|added)\b', caseSensitive: false).hasMatch(body);
    
    // Ambiguous keywords
    bool hasTransfer = RegExp(r'\b(transfer|transferred|txn)\b', caseSensitive: false).hasMatch(body);
    
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
            var contextRegex = RegExp(r'(?:debited|credited|sent|paid|transfer|transferred)\s+(?:by|of)?\s*(?:Rs\.?|INR|₹)?\s*(\d+(?:,\d+)*(?:\.\d{2})?)', caseSensitive: false);
            var amountMatch3 = contextRegex.firstMatch(body);
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
       if (message.address != null && !RegExp(r'^\+?\d+$').hasMatch(message.address!)) {
           merchant = message.address!;
       }
    }
    
    if (merchant.length > 20) {
        merchant = '${merchant.substring(0, 20)}...';
    }

    return TransactionModel(
      amount: amount,
      type: type,
      merchant: merchant,
      timestamp: message.date ?? DateTime.now(),
      body: body,
      source: 'SMS',
    );
  }
}
