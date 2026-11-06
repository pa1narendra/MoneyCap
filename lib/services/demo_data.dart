import 'db_service.dart';

/// Screenshot mode: `flutter build apk --debug --dart-define=DEMO=true
/// --android-project-arg=demo=true` makes a separate app (`...demo`) that runs
/// made-up SMS through the real parser and duplicate check. It never asks for
/// or reads the real inbox: this constant compiles that code path out of
/// normal builds and the real one out of the demo.
const bool kDemoMode = bool.fromEnvironment('DEMO');

class DemoData {
  DemoData._();

  /// Fake SMS in the same `{body, address, date}` shape as the real inbox.
  static List<Map<String, dynamic>> sms(DateTime now) {
    final out = <Map<String, dynamic>>[];
    var ref = 412345670000;
    void add(String sender, String body, DateTime at) =>
        out.add({'address': sender, 'body': body, 'date': at.millisecondsSinceEpoch});
    String r() => '${ref++}';
    String ymd(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year % 100}';
    void upi(DateTime at, double amount, String to) => add('AD-HDFCBK-S',
        'Sent Rs.${amount.toStringAsFixed(2)} From HDFC Bank A/C *4821 To $to On ${ymd(at)} Ref ${r()} Not You? Call 18002586161',
        at);
    void card(DateTime at, double amount, String at_) => add('AD-ICICIB-S',
        'INR ${amount.toStringAsFixed(2)} spent using ICICI Bank Card XX7302 on ${ymd(at)} at $at_. If not you, call 18002662',
        at);
    void credit(DateTime at, double amount, String from) => add('AD-HDFCBK-S',
        'Update! INR ${amount.toStringAsFixed(2)} credited to HDFC Bank A/c XX4821 on ${ymd(at)} from $from. UPI Ref ${r()}',
        at);

    for (var back = 5; back >= 0; back--) {
      DateTime day(int d, [int h = 12]) {
        final last = DateTime(now.year, now.month - back + 1, 0).day;
        return DateTime(now.year, now.month - back, d.clamp(1, last), h, 12);
      }

      final grow = (5 - back) * 120.0;
      final items = <void Function()>[
        () => credit(day(1, 10), 62000, 'ACME TECHNOLOGIES'),
        () => upi(day(2, 9), 15000, 'SUNRISE APARTMENTS RENT'),
        () => card(day(3, 21), 649, 'NETFLIX'),
        () => card(day(5, 13), 1240 + grow, 'AMAZON'),
        () => upi(day(6, 20), 420 + grow / 4, 'SWIGGY'),
        () => upi(day(9, 19), 1860 + grow, 'BIGBASKET'),
        () => upi(day(11, 8), 240, 'UBER INDIA'),
        () => upi(day(14, 20), 560, 'ZOMATO'),
        () => upi(day(18, 18), 2100, 'INDIAN OIL PETROL'),
        () => card(day(22, 16), 899, 'PVR CINEMAS'),
        () => upi(day(25, 11), 1450, 'AIRTEL BROADBAND'),
        () => add('AD-SBIUPI-S',
            'Dear UPI user A/C X9034 debited by ${(180 + back * 15).toStringAsFixed(1)} on date ${ymd(day(4))} trf to CHAI POINT Refno ${r()}. If not u? call 1800111109. -SBI',
            day(4, 17)),
        () => add('AD-SBIUPI-S',
            'Dear SBI User, your A/c X9034-credited by Rs.2500 on ${ymd(day(4))} transfer from RAVI KUMAR Ref No ${r()} -SBI',
            day(4, 19)),
      ];
      for (var i = 0; i < items.length; i++) {
        // In the current month only what has already happened.
        if (back == 0 && [1, 2, 3, 5, 6, 9, 11, 14, 18, 22, 25, 4, 4][i] > now.day) continue;
        items[i]();
      }

      // One card bill reported three times: this is what duplicate detection
      // collapses to a single transfer.
      if (back > 0) {
        final at = day(20, 10);
        final amount = 3000.0 + back * 111;
        upi(at, amount, 'ICICI Bank Credit Card Bill');
        add('AD-ICICIB-S',
            'Payment of Rs ${amount.toStringAsFixed(2)} received towards your Credit Card ending 7302.',
            at.add(const Duration(seconds: 2)));
        add('AD-ICICIB-T',
            'ICICI Bank Cardmember, Online Payment of Rs.${amount.toStringAsFixed(2)} vide Ref# 0${r()}A was credited to your card ending 7302',
            at.add(const Duration(hours: 5)));
      }
    }

    // Noise that must not appear in the app.
    final t = DateTime(now.year, now.month, 1, 9);
    add('AD-MPLPRO', 'Rs. 50 Deposit Cash is added to your wallet. Play Now and win upto Rs. 60 lakhs!', t);
    add('AX-HDFCBN', 'Dear Customer, Get a Credit Card + Rs.1500 Amazon Voucher. Apply now. T&C', t);
    add('AD-HDFCBK', '482913 is your OTP for txn of Rs 2,500.00 on HDFC Bank card xx4821. Do not share.', t);
    add('+919000000000', 'bro I paid Rs 400 for the cab', t);
    return out;
  }

  static Future<void> seedExtras(DateTime now) async {
    final db = DatabaseHelper.instance;
    await db.setBudget('Food & Dining', 1500);
    await db.setBudget('Groceries', 4000);
    await db.setBudget('Entertainment', 1000);
    await db.setCategoryRule('sunrise apartments', 'Rent');
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    await db.saveOpeningBalance(month, 48250, account: 'HDFC A/c XX4821');
  }
}
