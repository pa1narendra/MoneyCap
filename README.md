# MoneyCap

A personal expense tracker that reads payment SMSes to log transactions
automatically — no manual entry required, no banking-app access, no cloud.

Built for my own daily use because every existing expense app made one of
two trade-offs I didn't want: either it demanded I enter every transaction
manually, or it asked for access to my banking / payment apps. I wanted a
third option.

---

## 📥 Download & try it

Want to try the app without building it from source? Grab the latest signed
APK from the **[Releases page](https://github.com/pa1narendra/MoneyCap/releases/latest)**.
It's a normal Android app — it's just distributed here directly instead of
through the Play Store.

### Install steps (Android)

1. On your phone, open the **[latest release](https://github.com/pa1narendra/MoneyCap/releases/latest)** and download the `.apk` file (e.g. `moneycap-v1.0.0.apk`).
2. Tap the downloaded file (from the download notification or your **Files** app).
3. If your phone asks, allow installs from this source (see fixes below), then tap **Install**.
4. Open the app and grant **SMS** and **Notification** permissions when prompted — SMS access is what lets it auto-detect your transactions. Everything stays on your device; nothing is uploaded.

### Common install issues & fixes

Because this isn't a Play Store app, Android may warn you the first time. These are all normal and safe to allow for an app you trust:

- **"For your security, your phone is not allowed to install unknown apps from this source."**
  Tap **Settings** in that prompt and enable **Allow from this source** for the app you're installing from (e.g. Chrome or Files). You can turn it back off afterward.
  *Manual path:* Settings → Apps → Special app access → **Install unknown apps**.
- **"App not installed" / blocked by Play Protect.**
  Tap **More details → Install anyway**. If it still blocks, open Play Store → tap your profile → **Play Protect → Settings** → temporarily turn off *Scan apps with Play Protect*, install, then turn it back on. (It's flagged only because it's not from the Play Store, not because anything is wrong.)
- **"App not installed" because a different version already exists.**
  Uninstall any previous copy first, then install again.
- **Can't find the downloaded file?** Open the **Downloads** notification, or use **Files by Google → Downloads**.

> ⚠️ Only ever install APKs from sources you trust. Every release here is built
> automatically by GitHub Actions straight from the source in this repo — see
> [`.github/workflows/release.yml`](.github/workflows/release.yml).

> ℹ️ **iOS:** not distributed as a download — Apple doesn't allow third-party
> apps to read SMS, so iOS is manual-entry only.

---

## The problem

Every expense tracker I tried put me in the same bind:

- **Manual-entry apps** (Walnut-style) put the work back on me. I'd forget
  for a week, give up, uninstall.
- **Bank-integrated apps** wanted credentials or full access to payment
  apps — a lot of permission surface for a casual tracker.
- **Monthly bank statements** arrived too late and lost context (was that
  ₹450 food or fuel?).

The signal I actually wanted was already on my phone in a narrower, safer
place: **payment SMSes**. Every UPI transaction, card swipe, and wallet
debit triggers one. SMS read access is a single permission prompt with
no credential exposure — a much smaller ask than banking-app integration.

So I built this for myself.

---

## How it works

### 1. Regex-based payment SMS parser

`lib/services/parser_service.dart`

A multi-stage classifier that extracts transactions from raw SMS bodies:

- **Anti-spam filter** first — drops messages containing any of
  `claim | offer | won | prize | lottery | eligible | apply | marketing`.
- **Type detection** with strict priority: explicit credit keywords
  (`credited | received | deposited | refund | inward | added`) beat
  explicit debit keywords (`debited | spent | paid | sent | withdraw |
  purchased | paying`) beat ambiguous `transfer | transferred | txn`
  (defaulted to debit, since that's the common outgoing UPI case).
- **Amount extraction** in three tries: `Rs/INR/₹ <amount>` →
  `<amount> Rs/INR/₹` → contextual fallback that reads amounts after
  "debited by", "sent", etc. when no currency symbol is present.
- **Merchant extraction** via `at | to | from <name>` patterns;
  falls back to the SMS sender address if no pattern matches.

### 2. Incremental SMS sync

`lib/services/sms_service.dart`

First run reads the full SMS inbox. Subsequent runs resume from the
**last-seen transaction timestamp** stored in the DB:

- Queries the inbox in batches of 200, sorted newest-first.
- Stops as soon as it encounters a message older than `lastSync` —
  no need to scan the full inbox every time.
- Hard safety cap of 10,000 messages per sync to prevent runaway
  loops on misbehaving devices.
- 10 ms delay between batches so the UI thread doesn't freeze.

### 3. Monthly reconciliation

`lib/services/balance_service.dart`

The regex pipeline is good, not perfect — cash payments, offline
transactions, and weird issuer message formats will always slip through.
To catch the long tail:

- On the **1st of every month at 9 AM**, a local notification prompts
  for the opening balance. On the **last day at 8 PM**, it prompts for
  the closing balance.
- The app computes the expected closing balance as
  `opening + sum(credits) − sum(debits)` and surfaces the **delta**
  against the user-entered closing.
- If the delta is non-zero, the reconciliation screen lets you add the
  missing transaction(s) directly, then mark the month reconciled.

### 4. Manual-entry fallback

For payments that genuinely produce no SMS (cash, some prepaid wallets,
international cards), a quick manual-entry form with custom date support
keeps nothing from slipping through silently.

---

## Tech stack

| Area                 | Choice                                                       |
|----------------------|--------------------------------------------------------------|
| Framework            | Flutter (Dart SDK `^3.5.0`), Material 3 dark theme           |
| State management     | `provider`                                                   |
| Local storage        | `sqflite` (SQLite) — 2 tables, 2 indices, versioned schema   |
| SMS access           | `flutter_sms_inbox` + `permission_handler`                   |
| Notifications        | `flutter_local_notifications` + `timezone`                   |
| Charts               | `fl_chart`                                                   |
| Preferences          | `shared_preferences` (auto-sync toggle)                      |
| Platforms            | Android (primary) · iOS scaffolded (manual-entry only)       |

### Privacy

All SMS parsing happens on-device. No message content, amount, or
counterparty ever leaves the phone. No analytics, no cloud backup —
the SQLite database is local to the device.

---

## Database schema

`lib/services/db_service.dart` — schema v3, with migrations from v1.

```sql
-- Transactions (one row per detected or manually entered txn)
CREATE TABLE transactions (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  amount    REAL    NOT NULL,
  type      TEXT    NOT NULL,    -- 'CREDIT' | 'DEBIT'
  merchant  TEXT    NOT NULL,
  timestamp INTEGER NOT NULL,    -- ms since epoch
  body      TEXT    NOT NULL,    -- original SMS body (or 'Manual Entry')
  source    TEXT    NOT NULL     -- 'SMS' | 'MANUAL'
);
CREATE INDEX idx_timestamp ON transactions (timestamp);

-- Monthly balances (reconciliation state)
CREATE TABLE monthly_balances (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  month                 TEXT NOT NULL,   -- 'YYYY-MM'
  opening_balance       REAL,
  closing_balance       REAL,
  opening_recorded_at   TEXT,
  closing_recorded_at   TEXT,
  is_reconciled         INTEGER DEFAULT 0
);
CREATE UNIQUE INDEX idx_month ON monthly_balances (month);
```

Migrations handle adding the `source` column (v1→v2) and introducing
the `monthly_balances` table (v2→v3) without losing existing data.

---

## Project layout

```
lib/
├── main.dart                         # entry, MaterialApp, MultiProvider
├── models/
│   └── transaction_model.dart        # TransactionModel + toMap/fromMap
├── providers/
│   └── transaction_provider.dart     # ChangeNotifier, 10 date filters, totals
├── screens/
│   ├── dashboard_screen.dart         # home, totals, recent txns, filters
│   ├── stats_screen.dart             # monthly charts via fl_chart
│   └── reconciliation_screen.dart    # discrepancy view + fix-missing flow
├── services/
│   ├── parser_service.dart           # regex pipeline
│   ├── sms_service.dart              # incremental inbox sync
│   ├── db_service.dart               # sqflite wrapper + migrations
│   ├── balance_service.dart          # monthly balance + discrepancy calc
│   └── notification_service.dart     # schedule 24 reminders (12 months)
└── widgets/
    ├── balance_prompt_dialog.dart
    └── filter_dialog.dart
```

---

## Notable edge cases handled

- **Android 12+ exact alarms** — `flutter_local_notifications` requires
  `SCHEDULE_EXACT_ALARM` on newer Android versions, and many users deny
  it. If the permission is refused, the scheduler **falls back to inexact
  alarms** automatically instead of silently failing.
- **Duplicate balance-prompt dialogs** — the dashboard guards the prompt
  with `_isBalanceDialogShown` so repeated `initState` calls (e.g. on
  return from background) don't stack dialogs on top of each other.
- **Transfer SMS ambiguity** — "Transfer" alone is ambiguous (could be
  incoming or outgoing). The parser treats it as debit by default, on
  the heuristic that unambiguous incoming transfers almost always use
  "credited" or "received" explicitly.

---

## Running locally

Requires Flutter 3.x and Android Studio (or a connected Android device).

```bash
git clone https://github.com/pa1narendra/MoneyCap.git
cd MoneyCap

flutter pub get
flutter run
```

Grant SMS and notification permissions when prompted on first launch.

> iOS builds but supports **manual entry only** — Apple does not allow
> third-party apps to read SMSes by platform design.

---

## What I'd do differently in v2

- **Per-issuer regex sets are brittle.** New payment apps and changing
  SMS formats mean the filter needs constant upkeep. A smarter v2
  would use an on-device classifier (tflite or a small LLM) for
  payment-vs-non-payment detection, with regex as the fast path.
- **Category inference** is missing. Merchant strings are captured but
  never classified. A v2 could map merchants to categories
  (food / transport / bills / entertainment) using a user-editable
  rules table.
- **Encrypted user-held backup** — export to a file the user controls
  (e.g. Drive, iCloud), so device migration doesn't wipe history.
  Cloud sync server-side is still off the table on purpose.

---

## Status

Actively maintained — this is an app I use daily.

Released: `v1.0.0` on 2026-02-10. See `CHANGELOG.md` for details.
