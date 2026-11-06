import '../models/transaction_model.dart';
import 'parser_service.dart';

/// What to change after comparing a sync's new rows with their neighbours.
class DuplicatePlan {
  /// Rows that repeat another row's payment: hidden, not deleted, so a wrong
  /// match can be restored from Settings.
  final Set<int> hide;

  /// Bank-side debits that turn out to be a credit-card bill payment.
  final Set<int> markTransfer;
  const DuplicatePlan(this.hide, this.markTransfer);
}

/// Finds one payment reported by several differently worded SMS.
///
/// A byte-identical or same-reference re-delivery never gets this far (the
/// unique dedup key stops it at insert). This handles the rest:
///
///  1. **Card bill payment:** the bank says "Sent Rs X to CRED" and the card
///     says "Payment of Rs X received", sometimes twice. One row survives, the
///     bank's when there is one, as a transfer.
///  2. **Same amount, direction and account, compatible merchant, close in
///     time,** when at least one message has no bank reference (for example
///     SBI's "debit by transfer" next to its own detailed alert).
///
/// Two messages with DIFFERENT bank references are never merged. Real inbox
/// data shows those are genuinely separate payments (₹30 at the same stall
/// several times in a minute), and hiding them would silently lose real spend.
class DuplicateDetector {
  DuplicateDetector._();

  static const cardBillWindow = Duration(hours: 72);
  static const cardBillNoHintWindow = Duration(minutes: 30);
  static const sameMerchantWindow = Duration(minutes: 10);
  static const unknownMerchantWindow = Duration(hours: 6);

  static final RegExp _billPayee =
      RegExp(r'\bcred\b|credit\s*card|\bcard\s*bil', caseSensitive: false);

  /// [rows] sorted by timestamp, each with id, amount, type, kind, account,
  /// merchant, timestamp and dedup_key. Only pairs involving an id in [fresh]
  /// are considered, so a pair the user restored is never re-hidden.
  static DuplicatePlan plan(List<Map<String, Object?>> rows, Set<int> fresh) {
    final hide = <int>{};
    final markTransfer = <int>{};

    for (var i = 0; i < rows.length; i++) {
      final a = rows[i];
      final aId = a['id'] as int;
      if (hide.contains(aId)) continue;
      for (var j = i + 1; j < rows.length; j++) {
        final b = rows[j];
        final dt = Duration(milliseconds: (b['timestamp'] as int) - (a['timestamp'] as int));
        if (dt > cardBillWindow) break;
        final bId = b['id'] as int;
        if (hide.contains(bId)) continue;
        if (!fresh.contains(aId) && !fresh.contains(bId)) continue;
        if (((a['amount'] as num) - (b['amount'] as num)).abs() >= 0.005) continue;

        final bill = _cardBillMatch(a, b, dt);
        if (bill != null) {
          hide.add(bill.hide);
          if (bill.transfer != null) markTransfer.add(bill.transfer!);
          if (bill.hide == aId) break;
          continue;
        }
        if (_sameEvent(a, b, dt)) {
          final drop = _lessDetailed(a, b);
          hide.add(drop);
          if (drop == aId) break;
        }
      }
    }
    return DuplicatePlan(hide, markTransfer);
  }

  static ({int hide, int? transfer})? _cardBillMatch(
      Map<String, Object?> a, Map<String, Object?> b, Duration dt) {
    final aCard = _isCardSideBill(a), bCard = _isCardSideBill(b);
    if (!aCard && !bCard) return null;
    // Two acknowledgements of the same bill payment on one card.
    if (aCard && bCard) {
      return a['account'] == b['account'] ? (hide: b['id'] as int, transfer: null) : null;
    }
    final card = aCard ? a : b;
    final bank = aCard ? b : a;
    if (bank['type'] != 'DEBIT' || !_isBankAccount(bank)) return null;
    final alreadyBill = bank['merchant'] == ParserService.cardBillMerchant;
    final hinted = alreadyBill || _billPayee.hasMatch(bank['merchant'] as String);
    if (dt > (hinted ? cardBillWindow : cardBillNoHintWindow)) return null;
    return (hide: card['id'] as int, transfer: alreadyBill ? null : bank['id'] as int);
  }

  static bool _isCardSideBill(Map<String, Object?> r) =>
      r['merchant'] == ParserService.cardBillMerchant &&
      TransactionModel.isCardAccount(r['account'] as String?);

  static bool _isBankAccount(Map<String, Object?> r) =>
      TransactionModel.isBankAccount(r['account'] as String?);

  static bool _sameEvent(Map<String, Object?> a, Map<String, Object?> b, Duration dt) {
    if (a['type'] != b['type'] || a['kind'] != b['kind']) return false;
    final accA = a['account'], accB = b['account'];
    if (accA != null && accB != null && accA != accB) return false;
    final refA = refOf(a), refB = refOf(b);
    if (refA != null && refB != null) return refA == refB;
    final mA = _merchant(a), mB = _merchant(b);
    // Nothing ties two anonymous messages together: two ₹2 credits a few hours
    // apart, each with its own rising balance, are two real credits.
    if (mA == 'unknown' && mB == 'unknown') return false;
    if (mA == 'unknown' || mB == 'unknown') return dt <= unknownMerchantWindow;
    return mA == mB && dt <= sameMerchantWindow;
  }

  /// The bank reference inside a `r:<ref>:<type>:<amount>` dedup key.
  static String? refOf(Map<String, Object?> r) {
    final key = r['dedup_key'] as String?;
    if (key == null || !key.startsWith('r:')) return null;
    return key.split(':')[1];
  }

  static String _merchant(Map<String, Object?> r) =>
      (r['merchant'] as String).toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Keep the row that says more: a known merchant, then a reference.
  static int _lessDetailed(Map<String, Object?> a, Map<String, Object?> b) {
    int score(Map<String, Object?> r) =>
        (_merchant(r) == 'unknown' ? 0 : 2) + (refOf(r) == null ? 0 : 1);
    return score(a) >= score(b) ? b['id'] as int : a['id'] as int;
  }
}
