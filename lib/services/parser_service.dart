import '../models/transaction_model.dart';

/// Turns a bank SMS into a [TransactionModel], or returns null when the
/// message is not a completed transaction on one of the user's accounts.
///
/// Pipeline (each step can reject):
///  1. Sender gate: only DLT alphanumeric headers (e.g. `AD-HDFCBK-S`).
///     Phone numbers are people, and `-P` headers are promotional.
///  2. Non-transaction filters: promos, OTPs, failed/declined, bill-due and
///     statement reminders, future/scheduled debits, money requests.
///  3. Must reference an account/card/wallet, so merchant confirmations
///     ("2 tickets booked, paid Rs 500") don't double count the bank SMS.
///  4. Type: refund/reversal/cashback => CREDIT; card bill payment or
///     own-account transfer => TRANSFER kind; otherwise the EARLIEST
///     debit/credit verb wins ("A/c debited ...; Swiggy credited" is a debit).
///  5. Amount: first currency amount that isn't a balance/limit/due figure.
///  6. Merchant, account suffix, and a type-aware de-dup key.
class ParserService {
  // ---- 1. Sender ----
  // DLT headers: optional 2-letter operator/circle prefix, 3-10 char entity,
  // optional category suffix (S service, T transactional, G govt, P promo).
  static final RegExp _senderRegex = RegExp(
      r'^(?:[A-Z]{2}-)?([A-Z0-9]{3,10})(?:-([A-Z]))?$',
      caseSensitive: false);
  static final RegExp _allDigits = RegExp(r'^\d+$');

  // ---- 2. Non-transaction filters ----
  static final RegExp _spamRegex = RegExp(
      r'\b(?:claim|offer|won|prize|lottery|eligible|apply|marketing)\b',
      caseSensitive: false);
  // Promotional / informational messages. Deliberately does NOT include
  // "via" (real transactions say "debited via UPI" all the time) and filters
  // "convert" (an EMI offer) but not "converted" (a real EMI debit).
  static final RegExp _promoRegex = RegExp(
      r'\bconvert\b'
      r'|\bhurry\b'
      r'|t&c|terms\s*(?:and|&)\s*conditions'
      r'|\bavail\s+(?:now|it|this|the|your|an?|of)\b|\bexclusive\b'
      r'|limited\s*(?:period|time|offer)'
      r'|pre-?approved|pre-?qualified'
      r'|cashback\s+offer'
      r'|\bdiscount\b'
      r'|\d+\s*%\s*off'
      r'|(?:book|shop|buy)\s+now'
      r'|lowest\s+interest|instant\s+(?:loan|approval)|loan\s+offer'
      r'|congratulations|congrats'
      r'|\bbenefits?\b'
      r'|@\s*\d+(?:\.\d+)?\s*%'
      r'|\bunsubscribe\b|opt[-\s]?out|upgrade\s+your',
      caseSensitive: false);
  static final RegExp _otpRegex = RegExp(
      r'\botp\b|one[\s-]?time\s+password|verification\s+code|\bcode\s+is\b|do\s+not\s+share',
      caseSensitive: false);
  static final RegExp _failedRegex = RegExp(
      r'\bfailed\b|\bdeclined\b|\bunsuccessful\b|could\s+not\s+be\s+(?:processed|completed)'
      r'|has\s+not\s+been\s+(?:processed|completed)|\binsufficient\b|\brejected\b',
      caseSensitive: false);
  static final RegExp _reminderRegex = RegExp(
      r'\bis\s+due\b|\bdue\s+(?:on|by|date)\b|(?:min(?:imum)?|total)\s+(?:amount\s+)?due'
      r'|\bstatement\b|\bpay\s+now\b|\boverdue\b'
      r'|will\s+be\s+(?:debited|deducted|charged)|\bscheduled\b|\bupcoming\b'
      r'|has\s+requested|collect\s+request|requested\s+money|\bpayment\s+request\b',
      caseSensitive: false);

  // ---- 3. Account reference ----
  static final RegExp _accountMention = RegExp(
      r'\b(?:a/?c|acct|account|card|wallet)\b|[xX*]{1,}\d{3,6}\b|\.{3}\d{3,6}\b',
      caseSensitive: false);
  // Captures the trailing digits of a masked account/card number.
  static final RegExp _accountRegex = RegExp(
      r'(\ba/?c|\bacct|\baccount|\bcard)(?:\s*(?:no\.?|number|ending(?:\s+(?:with|in))?))?\s*[:\-]?\s*[xX*.]*\s*(\d{3,6})\b',
      caseSensitive: false);
  static final RegExp _maskedRegex = RegExp(r'[xX*]{2,}(\d{3,6})\b');

  // ---- 4. Type ----
  static final RegExp _debitVerb = RegExp(
      r'\b(?:debited|spent|paid|sent|withdrawn|withdrawal|withdraw|purchased|purchase|paying|deducted|charged)\b',
      caseSensitive: false);
  static final RegExp _creditVerb = RegExp(
      r'\b(?:credited|received|deposited|inward|added)\b', caseSensitive: false);
  static final RegExp _refundRegex = RegExp(
      r'\brefund(?:ed)?\b|\brevers(?:ed|al)\b|\bcash\s*back\b',
      caseSensitive: false);
  static final RegExp _transferWord =
      RegExp(r'\b(?:transfer|transferred)\b', caseSensitive: false);
  static final RegExp _cardRegex = RegExp(r'\bcard\b', caseSensitive: false);
  // Paying a credit-card bill, seen from either side:
  //  card side: "Payment of Rs X was credited / received towards your card"
  //  bank side: "debited ... towards HDFC Credit Card payment"
  // A plain card swipe never matches (it has no "payment received/credited"
  // and isn't "towards ... credit card").
  static final RegExp _cardBillRegex = RegExp(
      r'\bcard\s+(?:bill\s+)?payment\b'
      r'|\bpayment\s+(?:of\s+)?(?:rs\.?|inr|₹)?\s*[\d,.]+\s+(?:was\s+|has\s+been\s+|is\s+)?(?:received|credited)\b'
      r'|\btowards\s+(?:your\s+)?(?:[a-z]+\s+){0,3}credit\s*card\b',
      caseSensitive: false);
  static final RegExp _selfTransferRegex = RegExp(
      r'\bself[\s-]*(?:transfer|a/?c|account)\b|\bown\s+(?:a/?c|account)'
      r'|\b(?:transfer(?:red)?|sent|moved)\b[^.;]{0,60}?\bto\s+your\s+(?:other\s+)?(?:a/?c|acct|account)\b',
      caseSensitive: false);

  // ---- 5. Amount ----
  // Currency marker must not be preceded by a letter ("yours 2" is not Rs 2).
  static final RegExp _amountRegex = RegExp(
      r'(?<![A-Za-z])(?:Rs\.?|INR|₹)\s*([0-9]+(?:,[0-9]+)*(?:\.[0-9]{1,2})?)',
      caseSensitive: false);
  static final RegExp _amountSuffixRegex = RegExp(
      r'([0-9]+(?:,[0-9]+)*(?:\.[0-9]{1,2})?)\s*(?:Rs\.?|INR|₹)(?![A-Za-z])',
      caseSensitive: false);
  static final RegExp _contextAmountRegex = RegExp(
      r'(?:debited|credited|sent|paid|transferred)\s+(?:by|of|for|with)?\s*([0-9]+(?:,[0-9]+)*(?:\.[0-9]{1,2})?)\b',
      caseSensitive: false);
  // Figures that are NOT the transaction amount when they precede it.
  static final RegExp _nonAmountContext = RegExp(
      r'(?:bal(?:ance)?|avl|avail(?:able)?|limit|lmt|due|outstanding|o/s)\W*(?:is|of|:|-)?\W*$',
      caseSensitive: false);

  // ---- 6. Merchant / dedup ----
  static final RegExp _stopRegex = RegExp(
      r'\s+(?:on|is|was|has|have|had|been|processed|credited|debited|received|sent|paid|done|successful|with|using|ref|refno|via|through|thru|and|for|upi|imps|neft|rtgs|avl|bal|info|dated|date|at|from|to|in|your|if|not|towards|txn|-)\b'
      r'|[.,;:()!\n]|\s+\d{2}[-/]',
      caseSensitive: false);
  static final RegExp _vpaRegex =
      RegExp(r'\b(?:vpa|upi\s*id)\s*[:\-]?\s*([\w.\-]+)@[\w.\-]+', caseSensitive: false);
  static final RegExp _rawVpaRegex = RegExp(r'\b([A-Za-z][\w.\-]{1,40})@[A-Za-z]{2,}\b');
  static final RegExp _iciciMerchant =
      RegExp(r';\s*([A-Za-z0-9&\x27 .\-]{2,40}?)\s+credited\b', caseSensitive: false);
  static final RegExp _infoMerchant =
      RegExp(r'\binfo[:\-]\s*([A-Za-z0-9&\x27 *\-/]{2,40})', caseSensitive: false);
  // A candidate starting with one of these is the user's own account, an
  // amount, a date or a payment rail, never the counterparty.
  static final RegExp _ownAccountWords = RegExp(
      r'^(?:your|ur|my|a/?c\b|acct|account|card|bank\b|the\b|self|xx|\d|[xX*]+\d|rs\b|rs\.|inr|₹|(?:upi|imps|neft|rtgs|ecs|nach)\b)',
      caseSensitive: false);
  static final RegExp _accountWordsAnywhere =
      RegExp(r'\b(?:card|a/?c|acct|account)\b', caseSensitive: false);
  // "UPI/P2M/412345678906/BLINKIT" or "UPI/412345678911/PVR CINEMAS".
  static final RegExp _upiPathMerchant = RegExp(
      r'\bUPI/(?:[A-Z0-9]{2,4}/)?\d{6,}/([A-Za-z][A-Za-z0-9&\x27 .*\-]{1,40})',
      caseSensitive: false);
  // Card alerts written as "@SPOTIFY" (space before @, so not a VPA).
  static final RegExp _atSignMerchant =
      RegExp(r'(?:^|\s)@\s*([A-Za-z][A-Za-z0-9&\x27 .*\-]{1,40})');
  static final RegExp _refRegex = RegExp(
      r'(?:ref(?:erence)?|rrn|utr|upi|txn|transaction|imps|neft)\s*(?:no\.?|number|id|#)?\s*[:\-#.]?\s*(\d{6,})',
      caseSensitive: false);
  static final RegExp _wsRegex = RegExp(r'\s+');

  /// True for DLT business headers; false for phone numbers, short codes
  /// and promotional (-P) headers.
  static bool isBankLikeSender(String? address) {
    if (address == null) return false;
    final a = address.trim();
    final m = _senderRegex.firstMatch(a);
    if (m == null) return false;
    if (_allDigits.hasMatch(m.group(1)!)) return false;
    final suffix = m.group(2);
    if (suffix != null && suffix.toUpperCase() == 'P') return false;
    return true;
  }

  TransactionModel? parseFields(String? rawBody, String? address, DateTime? date) {
    if (rawBody == null || rawBody.trim().isEmpty) return null;
    final body = rawBody.trim();

    // 1-3. Gates.
    if (!isBankLikeSender(address)) return null;
    if (_spamRegex.hasMatch(body) || _promoRegex.hasMatch(body)) return null;
    if (_otpRegex.hasMatch(body)) return null;
    if (_failedRegex.hasMatch(body)) return null;
    if (_reminderRegex.hasMatch(body)) return null;
    if (!_accountMention.hasMatch(body)) return null;

    // 4. Type + kind.
    String type;
    String kind = TransactionModel.kindNormal;
    final debitAt = _debitVerb.firstMatch(body)?.start;
    final creditAt = _creditVerb.firstMatch(body)?.start;

    if (_refundRegex.hasMatch(body)) {
      type = 'CREDIT';
    } else if (_cardBillRegex.hasMatch(body)) {
      // A card bill payment moves money between the user's own accounts, so
      // it's a transfer: the individual card swipes were already counted.
      type = 'DEBIT';
      kind = TransactionModel.kindTransfer;
    } else if (debitAt != null || creditAt != null) {
      if (debitAt == null) {
        type = 'CREDIT';
      } else if (creditAt == null) {
        type = 'DEBIT';
      } else {
        type = debitAt < creditAt ? 'DEBIT' : 'CREDIT';
      }
    } else if (_transferWord.hasMatch(body)) {
      type = 'DEBIT';
    } else {
      return null;
    }
    if (kind == TransactionModel.kindNormal && _selfTransferRegex.hasMatch(body)) {
      kind = TransactionModel.kindTransfer;
    }

    // 5. Amount.
    final amount = _extractAmount(body);
    if (amount == null || amount <= 0) return null;

    // 6. Merchant, account, dedup.
    final merchant = _extractMerchant(body, type);
    final account = _extractAccount(body);
    final refMatch = _refRegex.firstMatch(body);
    final dedupKey = refMatch != null
        ? 'r:${refMatch.group(1)}:$type:${amount.toStringAsFixed(2)}'
        : 'b:${body.toLowerCase().replaceAll(_wsRegex, ' ')}';

    return TransactionModel(
      amount: amount,
      type: type,
      merchant: merchant,
      timestamp: date ?? DateTime.now(),
      body: body,
      source: 'SMS',
      dedupKey: dedupKey,
      kind: kind,
      account: account,
    );
  }

  double? _extractAmount(String body) {
    for (final re in [_amountRegex, _amountSuffixRegex, _contextAmountRegex]) {
      for (final m in re.allMatches(body)) {
        final lead = body.substring((m.start - 30).clamp(0, m.start), m.start);
        if (_nonAmountContext.hasMatch(lead)) continue;
        final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
        if (v != null) return v;
      }
    }
    return null;
  }

  /// `A/c XX1234` or `Card XX1234` (last 3-4 digits), `Wallet`, or null.
  static String? _extractAccount(String body) {
    String? digits;
    bool isCard;
    final m = _accountRegex.firstMatch(body);
    if (m != null) {
      digits = m.group(2);
      isCard = m.group(1)!.toLowerCase() == 'card';
    } else {
      digits = _maskedRegex.firstMatch(body)?.group(1);
      isCard = _cardRegex.hasMatch(body);
    }
    if (digits == null) {
      return RegExp(r'\bwallet\b', caseSensitive: false).hasMatch(body) ? 'Wallet' : null;
    }
    final tail = digits.length > 4 ? digits.substring(digits.length - 4) : digits;
    return '${isCard ? 'Card' : 'A/c'} XX$tail';
  }

  /// Reads the phrase after [keyword] up to the first stop word/punctuation.
  static String? _phraseAfter(String body, String keyword) {
    final re = RegExp('\\b$keyword\\s+', caseSensitive: false);
    for (final m in re.allMatches(body)) {
      var rest = body.substring(m.end);
      final vpa = _rawVpaRegex.matchAsPrefix(rest);
      if (vpa != null) return vpa.group(1);
      final stop = _stopRegex.firstMatch(rest);
      if (stop != null) rest = rest.substring(0, stop.start);
      rest = rest.trim();
      if (!_isCounterparty(rest)) continue;
      return rest;
    }
    return null;
  }

  static bool _isCounterparty(String s) =>
      s.length >= 2 &&
      !_ownAccountWords.hasMatch(s) &&
      !_accountWordsAnywhere.hasMatch(s);

  /// Cuts [s] at the first stop word, or returns null if nothing usable.
  static String? _clip(String? s) {
    if (s == null) return null;
    final stop = _stopRegex.firstMatch(s);
    final out = (stop != null ? s.substring(0, stop.start) : s).trim();
    return _isCounterparty(out) ? out : null;
  }

  static String _extractMerchant(String body, String type) {
    String? m;
    if (type == 'DEBIT') m = _clip(_iciciMerchant.firstMatch(body)?.group(1));
    m ??= _clip(_upiPathMerchant.firstMatch(body)?.group(1));
    final order = type == 'DEBIT'
        ? const ['at', 'to', 'towards', 'for', 'on']
        : const ['from', 'by'];
    for (final k in order) {
      m ??= _phraseAfter(body, k);
    }
    if (type == 'DEBIT') m ??= _clip(_atSignMerchant.firstMatch(body)?.group(1));
    m ??= _vpaRegex.firstMatch(body)?.group(1);
    m ??= _infoMerchant.firstMatch(body)?.group(1);
    if (m == null) return 'Unknown';
    m = m.replaceAll(_wsRegex, ' ').trim();
    if (m.length > 40) m = m.substring(0, 40).trim();
    return m.isEmpty ? 'Unknown' : m;
  }
}

/// Top-level entry point for `compute()`: parses a batch of raw SMS records
/// on a background isolate and returns ready-to-insert transaction maps.
/// Each input record is `{ 'body': String?, 'address': String?, 'date': int? }`
/// where `date` is millisecondsSinceEpoch.
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
    if (txn != null) out.add(txn.toMap()..remove('id'));
  }
  return out;
}
