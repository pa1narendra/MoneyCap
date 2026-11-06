import '../models/transaction_model.dart';

/// Turns a bank SMS into a [TransactionModel], or returns null when the
/// message is not a completed transaction on one of the user's accounts.
///
/// Pipeline (each step can reject):
///  1. Sender: a DLT header (not a phone number, not a `-P` promo header) that
///     is either a known bank/payment issuer, or an unknown sender whose text
///     looks like a real bank alert (masked account + debited/credited + bank).
///     This is what keeps gaming wallets, shopping credits, mutual fund and
///     payment gateway notices out: they aren't money in the user's accounts,
///     or they repeat what the bank itself reports.
///  2. Non-transaction filters: promos, OTPs, failed/declined, bill-due and
///     statement reminders, future/scheduled debits, money requests, refunds
///     that have only been initiated.
///  3. Must reference an account/card/wallet.
///  4. Type: refund/reversal => CREDIT; card bill payment or own-account
///     transfer => TRANSFER kind; otherwise the EARLIEST debit/credit verb wins.
///  5. Amount: first currency amount that isn't a balance/limit/due figure.
///  6. Merchant, account suffix, and a type-aware de-dup key.
///
/// One payment can still produce several differently worded SMS. Those are
/// matched across messages by `DuplicateDetector`, after parsing.
class ParserService {
  // ---- 1. Sender ----
  static final RegExp _senderRegex = RegExp(
      r'^(?:[A-Z]{2}-)?([A-Z0-9]{3,10})(?:-([A-Z]))?$',
      caseSensitive: false);
  static final RegExp _allDigits = RegExp(r'^\d+$');
  // Banks, card issuers and payment apps whose SMS report real money movement.
  static final RegExp _knownIssuer = RegExp(
      r'HDFC|ICICI|SBI|SBM|AXIS|KOTAK|PNB|BOB|BARODA|CANBNK|CANARA|UNION|IDFC|INDUS'
      r'|YESB|FEDB|RBL|BANDH|CITI|HSBC|SCB|AMEX|AUBANK|IDBI|BNK|BANK'
      r'|PAYTM|PHONPE|PHONEPE|GPAY|FAMPAY|MOBIKW|SLICE|ONECRD|JUPITR|JUPITER',
      caseSensitive: false);
  // An unknown sender must look unmistakably like a bank alert.
  static final RegExp _maskedDigits = RegExp(r'[xX*]{1,}\d{3,6}\b');
  static final RegExp _strongVerb = RegExp(r'\b(?:debited|credited)\b', caseSensitive: false);
  static final RegExp _bankWord = RegExp(r'\bbank\b|\ba/?c\b', caseSensitive: false);

  // ---- 2. Non-transaction filters ----
  static final RegExp _spamRegex = RegExp(
      r'\b(?:claim|offer|won|prize|lottery|eligible|apply|marketing)\b',
      caseSensitive: false);
  // Deliberately does NOT include "via" (real transactions say "debited via
  // UPI") and filters "convert" (an EMI offer) but not "converted" (a real EMI).
  static final RegExp _promoRegex = RegExp(
      r'\bconvert\b'
      r'|\bhurry\b'
      r'|t&c|\btnc\b|terms\s*(?:and|&)\s*conditions'
      r'|\bavail\s+(?:now|it|this|the|your|an?|of)\b|\bexclusive\b'
      r'|limited\s*(?:period|time|offer)'
      r'|pre-?approved|pre-?qualified|pre-?eligible'
      r'|cashback\s+offer|\bvoucher\b'
      r'|\bdiscount\b'
      r'|\d+\s*%\s*off'
      r'|(?:book|shop|buy|send|play|redeem|click)\s+now'
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
      r'\bis\s+due\b|\bdue\s+(?:on|by|date)\b|\bamount\s+due\b|(?:min(?:imum)?|total)\s*\.?\s*(?:amount\s+)?due'
      r'|\bstatement\b|\bpay\s+now\b|\boverdue\b'
      r'|will\s+be\s+(?:debited|deducted|charged)|\bscheduled\b|\bupcoming\b'
      r'|has\s+requested|requested\s+money|collect\s+request|\bpayment\s+request\b'
      r'|\brefund\b[^.]{0,60}\binitiated\b|\brefund\s+initiated\b'
      r'|\bhold\s+for\b|\bfolio\b',
      caseSensitive: false);

  // ---- 3. Account reference ----
  static final RegExp _accountMention = RegExp(
      r'\b(?:a/?c|acct|account|card|wallet)\b|\ba/?c[xX*.]|[xX*]{1,}\d{3,6}\b|\.{3}\d{3,6}\b',
      caseSensitive: false);
  // Captures the trailing digits of a masked account/card number.
  static final RegExp _accountRegex = RegExp(
      r'(\ba/?c|\bacct|\baccount|\bcard)(?:\s*(?:no\.?|number|ending(?:\s+(?:with|in))?))?\s*[:\-]?\s*[xX*.]*\s*(\d{3,6})\b',
      caseSensitive: false);
  static final RegExp _maskedRegex = RegExp(r'[xX*]{2,}(\d{3,6})\b');
  static final RegExp _walletRegex = RegExp(r'\bwallet\b', caseSensitive: false);
  // "SMS BLOCK DC 5765" (credit cards say CC), "withdrawn from ... Card".
  static final RegExp _debitCardRegex =
      RegExp(r'\bDC\b|\bdebit\s+card\b|\bwithdrawn\b', caseSensitive: false);
  // Longest keys first where one could contain another.
  static const _issuerNames = <String, String>{
    'HDFC': 'HDFC', 'ICICI': 'ICICI', 'SBM': 'SBI', 'SBI': 'SBI', 'AXIS': 'Axis',
    'KOTAK': 'Kotak', 'PNB': 'PNB', 'BOB': 'BoB', 'BARODA': 'BoB', 'CANBNK': 'Canara',
    'CANARA': 'Canara', 'UNION': 'Union', 'IDFC': 'IDFC', 'INDUS': 'IndusInd',
    'YESB': 'Yes', 'FEDB': 'Federal', 'RBL': 'RBL', 'BANDH': 'Bandhan', 'CITI': 'Citi',
    'HSBC': 'HSBC', 'SCB': 'StanChart', 'AMEX': 'Amex', 'AUBANK': 'AU', 'IDBI': 'IDBI',
    'PAYTM': 'Paytm', 'PHONPE': 'PhonePe', 'PHONEPE': 'PhonePe', 'GPAY': 'Google Pay',
    'FAMPAY': 'FamPay', 'MOBIKW': 'MobiKwik',
  };

  // ---- 4. Type ----
  // "Txn Rs.530 On HDFC Bank Card 1234" is how HDFC reports UPI on a credit card.
  static final RegExp _debitVerb = RegExp(
      r'\b(?:debited|spent|paid|sent|withdrawn|withdrawal|withdraw|purchased|purchase|paying|deducted|charged)\b'
      r'|\bdebit\s+by\b|\bhas\s+a\s+debit\b'
      // "Txn Rs.530.00 On HDFC Bank Card 1234": UPI on a credit card.
      r'|^txn\s+(?:rs\.?|inr|₹)',
      caseSensitive: false);
  static final RegExp _creditVerb = RegExp(
      r'\b(?:credited|received|deposited|inward|added)\b|\bhas\s+(?:a\s+)?credit\b',
      caseSensitive: false);
  static final RegExp _refundRegex =
      RegExp(r'\brefund(?:ed)?\b|\brevers(?:ed|al)\b', caseSensitive: false);
  // "Rs 800 was sent to your account by Ravi" is money coming IN. With a masked
  // number after it, it's a move between the user's accounts (see below).
  static final RegExp _incomingRegex = RegExp(
      r'\b(?:sent|transferred|paid)\s+to\s+your\s+(?:a/?c|acct|account|wallet)\b(?!\s*(?:no\.?\s*)?[xX*.]*\d)',
      caseSensitive: false);
  static final RegExp _transferWord =
      RegExp(r'\b(?:transfer|transferred)\b', caseSensitive: false);
  static final RegExp _cardRegex = RegExp(r'\bcard\b', caseSensitive: false);
  // Paying a credit-card bill, seen from either side:
  //  card side: "Payment of Rs X was credited / received towards your card"
  //  bank side: "debited ... towards Credit Card payment", "Sent ... To HDFC
  //  Bank Credit Card Bill". A plain card swipe never matches.
  static final RegExp _cardBillRegex = RegExp(
      r'\bcard\s+(?:bill\s+)?payment\b'
      r'|\bpayment\s+(?:of\s+)?(?:rs\.?|inr|₹)?\s*[\d,.]+\s+(?:was\s+|has\s+been\s+|is\s+)?(?:received|credited)\b'
      r'|\bpayment\b[^\n]{0,70}\bcredited\s+to\s+your\s+(?:credit\s+)?card\b'
      r'|\btowards\s+(?:your\s+)?(?:[a-z]+\s+){0,3}credit\s*card\b'
      r'|\bto\s+(?:[a-z]+\s+){0,3}credit\s*card\s*bil',
      caseSensitive: false);
  static final RegExp _selfTransferRegex = RegExp(
      r'\bself[\s-]*(?:transfer|a/?c|account)\b|\bown\s+(?:a/?c|account)'
      r'|\b(?:transfer(?:red)?|sent|moved)\b[^.;]{0,60}?\bto\s+your\s+(?:other\s+)?(?:a/?c|acct|account)\s*(?:no\.?\s*)?[xX*.]*\d',
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
  // Everything from here on is the bank's "not you? call us" footer, which
  // contains words like "to block UPI" that aren't a counterparty.
  static final RegExp _footerRegex = RegExp(
      r'\bnot\s+(?:you|u|done)\b|\bif\s+not\b|\bto\s+block\b|\bfwd\s+this\b|\bforward\s+this\b'
      r'|\bcall\s+(?:us\s+)?(?:on\s+)?\d',
      caseSensitive: false);
  static final RegExp _stopRegex = RegExp(
      r'\s+(?:on|is|was|has|have|had|been|processed|credited|debited|received|sent|paid|done|successful|with|using|ref|refno|via|through|thru|by|for|upi|imps|neft|rtgs|avl|info|dated|date|at|from|to|in|your|if|not|towards|txn|-)\b'
      // "bal" only as a balance figure: "M BAL RAJ" is someone's name.
      r'|\s+bal\b(?=\W*(?:rs|inr|₹))'
      r'|[.,;:()!\n]|\s+\d{2}[-/]',
      caseSensitive: false);
  static final RegExp _leadingNoise = RegExp(r'^[.\s+*]+');
  static final RegExp _trailingNoise = RegExp(r'[\s_.\-]+$');
  static final RegExp _vpaPrefix = RegExp(r'^vpa\s+', caseSensitive: false);
  static final RegExp _vpaRegex =
      RegExp(r'\b(?:vpa|upi\s*id)\s*[:\-]?\s*([\w.\-]+)@[\w.\-]+', caseSensitive: false);
  static final RegExp _rawVpaRegex = RegExp(r'([A-Za-z][\w.\-]{1,40})@[A-Za-z]{2,}\b');
  static final RegExp _iciciMerchant =
      RegExp(r';\s*([A-Za-z0-9&\x27 .\-]{2,40}?)\s+credited\b', caseSensitive: false);
  static final RegExp _infoMerchant =
      RegExp(r'\binfo[:\-]\s*([A-Za-z0-9&\x27 *\-/]{2,40})', caseSensitive: false);
  // A candidate starting with one of these is the user's own account, an
  // amount, a date or a payment rail, never the counterparty.
  static final RegExp _ownAccountWords = RegExp(
      r'^(?:your\b|ur\b|my\b|you\b|u\b|a/?c\b|acct\b|account\b|card\b|bank\b|the\b|self\b|xx|\d|[xX*]+\d|rs\.?\s*\d|inr\b|₹|(?:upi|imps|neft|rtgs|ecs|nach)\b)',
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
  // "NEFT Cr-IDFB0081188-ACME PAYROLL ACCOUNT-Your Name-IDFB6308M..."
  static final RegExp _neftMerchant = RegExp(
      r'\bNEFT\s+Cr-(?:[A-Z]{4}0[A-Z0-9]{6}-)?([A-Za-z][^-.\n]{1,100})',
      caseSensitive: false);
  // "by a/c linked to mobile 6XXXXXX214-Ravi Kumar (IMPS Ref no ...)"
  static final RegExp _linkedMobileMerchant = RegExp(
      r'linked\s+to\s+mobile\s+\S*?-([A-Za-z][A-Za-z .]{1,60})',
      caseSensitive: false);
  // HDFC hides most of a UPI ID ("from VPA *9795@superyes"). It's all the SMS
  // says about the person, and the same person shows the same text every time.
  static final RegExp _maskedVpaMerchant = RegExp(r'\*[A-Za-z0-9._\-]+@[A-Za-z]+');
  // "For: DEBIT CARD ANNUAL FEE-Jul-2026"
  static final RegExp _feeMerchant =
      RegExp(r'\bfor:\s*([A-Za-z][A-Za-z ]{2,60})', caseSensitive: false);
  // SBI: "Debited INR 4.70 on 14/12/21 -ATM PENDING AMC. Avl Bal"
  static final RegExp _chargeMerchant = RegExp(r'-\s*([A-Z][A-Z ]{3,60})\.\s*Avl\b');
  // "debited from a/c *1234 on 01/01/26 to a/c **5678"
  static final RegExp _otherAccountMerchant =
      RegExp(r'\bto\s+a/?c\s+[*xX.]*(\d{3,6})\b', caseSensitive: false);
  // "...-TPT-salary-ACME LABS (OPC) PRIVATE LIMITED.Avl bal"
  static final RegExp _salaryMerchant =
      RegExp(r'\bsalary[-:\s]+([A-Za-z][A-Za-z&\x27 ]{2,40})', caseSensitive: false);
  static final RegExp _salaryWord = RegExp(r'\bsalary\b', caseSensitive: false);
  // Bank references can be alphanumeric ("Ref# 093BB59S003H826", "UTR IN1234567").
  static final RegExp _refRegex = RegExp(
      r'(?:ref(?:erence)?|refno|rrn|utr|upi|txn|transaction|imps|neft)\s*(?:no\.?|number|id|#)?\s*[:\-#.]?\s*((?=[A-Z0-9]*\d)[A-Z0-9]{6,})',
      caseSensitive: false);
  static final RegExp _wsRegex = RegExp(r'\s+');

  /// Merchant label for a credit-card bill payment.
  static const cardBillMerchant = 'Credit card bill';

  /// True for DLT business headers; false for phone numbers, short codes
  /// and promotional (-P) headers.
  static bool isBankLikeSender(String? address) {
    if (address == null) return false;
    final m = _senderRegex.firstMatch(address.trim());
    if (m == null) return false;
    if (_allDigits.hasMatch(m.group(1)!)) return false;
    final suffix = m.group(2);
    return suffix == null || suffix.toUpperCase() != 'P';
  }

  /// A DLT sender we believe reports money in the user's own accounts.
  static bool isTrustedSender(String? address, String body) {
    if (!isBankLikeSender(address)) return false;
    final entity = _senderRegex.firstMatch(address!.trim())!.group(1)!;
    if (_knownIssuer.hasMatch(entity)) return true;
    return _maskedDigits.hasMatch(body) && _strongVerb.hasMatch(body) && _bankWord.hasMatch(body);
  }

  TransactionModel? parseFields(String? rawBody, String? address, DateTime? date) {
    if (rawBody == null || rawBody.trim().isEmpty) return null;
    final body = rawBody.trim();

    // 1-3. Gates.
    if (!isTrustedSender(address, body)) return null;
    if (_spamRegex.hasMatch(body) || _promoRegex.hasMatch(body)) return null;
    if (_otpRegex.hasMatch(body)) return null;
    if (_failedRegex.hasMatch(body)) return null;
    if (_reminderRegex.hasMatch(body)) return null;
    if (!_accountMention.hasMatch(body)) return null;

    // 4. Type + kind.
    String type;
    String kind = TransactionModel.kindNormal;
    var isCardBill = false;
    final debitAt = _debitVerb.firstMatch(body)?.start;
    final creditAt = _creditVerb.firstMatch(body)?.start;

    if (_refundRegex.hasMatch(body) || _incomingRegex.hasMatch(body)) {
      type = 'CREDIT';
    } else if (_cardBillRegex.hasMatch(body)) {
      // A card bill payment moves money between the user's own accounts, so
      // it's a transfer: the individual card swipes were already counted.
      type = 'DEBIT';
      kind = TransactionModel.kindTransfer;
      isCardBill = true;
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
    final merchant = isCardBill ? cardBillMerchant : _extractMerchant(body, type);
    final account = _extractAccount(body, address);
    final ref = _refRegex.firstMatch(body)?.group(1)?.toUpperCase();
    final dedupKey = ref != null
        ? 'r:$ref:$type:${amount.toStringAsFixed(2)}'
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

  /// The bank or app name behind a sender header, e.g. `AD-HDFCBN-S` => HDFC.
  static String? issuerOf(String? address) {
    final entity = _senderRegex.firstMatch((address ?? '').trim())?.group(1)?.toUpperCase();
    if (entity == null) return null;
    for (final e in _issuerNames.entries) {
      if (entity.contains(e.key)) return e.value;
    }
    return null;
  }

  static const _walletIssuers = {'PhonePe', 'Paytm', 'FamPay', 'MobiKwik', 'Google Pay'};

  /// `HDFC A/c XX1234`, `HDFC Card XX1234` (credit card), `HDFC Debit XX1234`
  /// (a debit card: its spending comes out of the bank account), `Paytm
  /// Wallet`, or null. The bank name comes from the sender, so two banks are
  /// told apart even if their last digits match.
  static String? _extractAccount(String body, String? address) {
    final issuer = issuerOf(address);
    final prefix = issuer == null ? '' : '$issuer ';
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
      if (_walletIssuers.contains(issuer)) return '${issuer!} Wallet';
      return _walletRegex.hasMatch(body) ? '${prefix}Wallet' : null;
    }
    final tail = digits.length > 4 ? digits.substring(digits.length - 4) : digits;
    if (isCard) {
      return '$prefix${_debitCardRegex.hasMatch(body) ? 'Debit' : 'Card'} XX$tail';
    }
    return '${prefix}A/c XX$tail';
  }

  /// Reads the phrase after [keyword] up to the first stop word/punctuation.
  static String? _phraseAfter(String body, String keyword) {
    final re = RegExp('\\b$keyword\\s+', caseSensitive: false);
    for (final m in re.allMatches(body)) {
      var rest = body
          .substring(m.end)
          .replaceFirst(_leadingNoise, '')
          .replaceFirst(_vpaPrefix, '')
          .replaceFirst(_leadingNoise, '');
      final vpa = _rawVpaRegex.matchAsPrefix(rest);
      if (vpa != null) return vpa.group(1);
      final stop = _stopRegex.firstMatch(rest);
      if (stop != null) rest = rest.substring(0, stop.start);
      rest = rest.replaceFirst(_trailingNoise, '').trim();
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

  static String _extractMerchant(String fullBody, String type) {
    final footer = _footerRegex.firstMatch(fullBody);
    final body = footer != null ? fullBody.substring(0, footer.start) : fullBody;
    String? m;
    // Names that sit in a fixed slot of the bank's format.
    m = _neftMerchant.firstMatch(body)?.group(1)?.trim();
    m ??= _linkedMobileMerchant.firstMatch(body)?.group(1)?.trim();
    m ??= _maskedVpaMerchant.firstMatch(body)?.group(0);
    m ??= _feeMerchant.firstMatch(body)?.group(1)?.trim();
    m ??= _chargeMerchant.firstMatch(body)?.group(1)?.trim();
    final otherAccount = _otherAccountMerchant.firstMatch(body)?.group(1);
    if (otherAccount != null) m ??= 'A/c XX$otherAccount';
    if (type == 'DEBIT') m ??= _clip(_iciciMerchant.firstMatch(body)?.group(1));
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
    m ??= _salaryMerchant.firstMatch(body)?.group(1)?.trim();
    if (m == null && _salaryWord.hasMatch(body)) return 'Salary';
    if (m == null && _refundRegex.hasMatch(body)) {
      return RegExp(r'revers', caseSensitive: false).hasMatch(body) ? 'Reversal' : 'Refund';
    }
    if (m == null) return 'Unknown';
    // Kept whole: the list shows one line, the details sheet shows all of it.
    m = m.replaceAll(_wsRegex, ' ').trim();
    if (m.length > 120) m = m.substring(0, 120).trim();
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
