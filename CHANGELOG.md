# Changelog
All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [Unreleased]

## [3.1.0] - 2026-11-07
Tested against a real inbox of 11,000+ messages, which found problems the sample messages in 3.0.0 missed. On first launch after updating, SMS transactions are rebuilt once with the improved parser. A reminder offers a backup first. Manual entries, balances, categories and budgets are kept, but edits made to SMS transactions are not.

### Fixed
- **One payment noted two or three times.** A credit card bill reported by both the bank and the card now shows as a single transfer, and it no longer counts as income or expense. Other repeats of the same payment are matched across messages too. Two messages with different bank references stay separate, because they are real separate payments.
- Gaming wallet bonuses, food-app credits, shopping gift cards, mutual fund notices, payment gateway refund notices and cashback promos were counted as income or expense. Senders must now be a bank or payment issuer, or look unmistakably like a bank alert.
- Refunds that were only "initiated" were counted, then counted again when completed.
- Missed real transactions: SBI's "has credit for", and "Txn Rs" UPI payments on a credit card. FamPay's "sent to your account" read as money going out.
- Merchant names were cut at 40 characters, and many showed Unknown or a wrong word ("block", "report") when the SMS did name someone: NEFT payers, IMPS senders, masked UPI IDs like `*1234@ybl`, bank fees, and names like "URS PHARMA", "M BAL RAJ" and "L and T Metro". The list shows one line and the details show the whole name. Unknown now only appears when the SMS really has no name.
- Input errors: closing a balance, budget, rule or name dialog threw an error, and leaving a field empty gave no visible message or just closed the dialog. Every field now shows what's wrong under it and stays open.
- A debit card was treated like a credit card, which threw off its bank's reconciliation.
- A custom date range left out its last day, and couldn't reach back before 2020.
- The first-import count no longer includes repeated messages.

### Added
- **Name a UPI ID or payee** once and it shows on all its past and future payments, with the SMS text kept underneath.
- **"This is me":** mark your own accounts so everything to or from them is a transfer, for the ones automatic matching misses.
- **Hidden duplicates** in Settings: review the messages treated as repeats and restore any that were really separate payments.
- **A backup reminder** before anything that clears or replaces data: re-importing SMS, restoring a backup, and the one-time rebuild after updating. Backing up is offered, never required.

### Changed
- **Each bank keeps its own balances.** Accounts are named from the SMS (`HDFC A/c XX1234`, `SBI A/c XX5678`, `HDFC Card XX9012`, `HDFC Debit XX3456`). Reconciliation opens on one bank, the monthly prompt asks for each bank, and a combined view is still available. Balances entered under 3.0.0's labels move to the new ones.
- Debug builds install next to the signed app as `com.moneycap.app.debug`, and a demo build with made-up data produces the README screenshots, which are now in the README.
- 198 automated tests (was 107), including 100+ SMS fixtures, many following formats from a real inbox with names and numbers changed.

## [3.0.0] - 2026-11-05
Accuracy, privacy and a lot of new features. On first launch after updating, SMS
transactions are re-imported once with the new parser (manual entries, balances,
name and theme are kept), because the old parser had the errors fixed below.

### Fixed
- ICICI-style debits ("Acct debited ...; Swiggy credited") were recorded as income. The first debit/credit word now decides.
- Merchant names were cut inside words ("Amazon" became "Amaz", "Krishna" became "Kr"), and "sent from Kotak AC X5678 to Krishna" picked the user's own account as the merchant.
- OTPs, failed/declined payments, bill-due and statement reminders, scheduled debits and money requests were recorded as spends. Reversals and refunds now count as income.
- Personal SMS ("bro I paid Rs 400") were recorded. Only bank-style sender IDs are accepted, and promotional senders are skipped.
- Wrong amounts: `Rs.100.5` read as 100, "yours 2 tickets" read as Rs 2, a balance quoted first was taken as the amount, and ₹0 rows were saved.
- A refund with the same reference as its purchase was silently dropped as a duplicate.
- Credit-card spend was counted twice (swipe + bill payment), and own-account transfers showed as both expense and income. These are now transfers, excluded from totals.
- Reconciliation mixed every account into one balance. It now works per bank account or across all bank accounts (cards excluded).
- Deleting the newest SMS transaction brought it back on the next sync. Deleted SMS transactions now never return.
- "Reset data" deleted manual entries. It's now "Re-import SMS transactions" and keeps manual entries, balances, categories and budgets.
- The app crashed on start in builds without a Firebase config, and malformed push data could crash the reminder handler.
- Two syncs could run at once (startup + pull-to-refresh).
- Editing a transaction changed it on screen before it was saved. Manual entry had no decimal key, wasn't awaited, and accepted a blank merchant.

### Security & privacy
- Android cloud auto-backup is off; the database (which holds bank SMS text) no longer goes to Google Drive.
- A disclosure screen explains exactly what's read before the SMS permission is requested.
- Push reminders can be turned off in Settings (unsubscribes and deletes the push token).
- CSV export guards against spreadsheet formula injection, and exported files no longer linger in the cache.
- Backup restore validates every table, column and value before writing, in one all-or-nothing transaction.

### Added
- Onboarding with a progress bar for the first import.
- Categories with built-in rules for common merchants and your own editable merchant rules.
- Budgets per category, with a dashboard warning at 90%.
- Recurring payment and subscription detection on Statistics, plus a category breakdown.
- Per-account tracking from the `A/c XX1234` / `Card XX1234` suffix, with an account filter on the dashboard.
- Mark any transaction as a transfer; matching debit/credit pairs across your accounts are detected automatically.
- Background sync every few hours (WorkManager), plus sync when you return to the app. Automatic sync is on by default.
- Full backup and restore to a file you keep.
- Home-screen widget with this month's spend and income.
- Settings screen (sync, reminders, name, theme, category rules, backup, re-import).
- Transaction details sheet showing the original SMS.

### Changed
- The transaction list is computed once per change instead of once per row, and the SMS text isn't held in memory with the list.
- Fresh clones build without secrets: no Firebase config means no push reminders, no keystore means debug signing. The release workflow refuses to publish without signing secrets.
- CI runs analyze, tests and a debug APK build on every push; releases run analyze and tests first and use Flutter 3.41.6.
- Android Gradle Plugin 8.9.1, Kotlin 2.1.0, Gradle 8.11.1; min SDK 23.
- 107 automated tests (was 16), including 60+ real-world SMS fixtures across 14 banks.
- README rewritten; analyzer warnings fixed; the template widget test replaced.

## [2.2.0] - 2026-08-06
### Added
- **Search** transactions by merchant or amount (search icon in the app bar).
- **Income / Expense toggle** to filter the transaction list — the income and expense totals still always show both.
- **Edit or delete** any transaction — tap it to fix a wrong amount/merchant, flip income↔expense, or remove a stray entry.
- **Export to CSV** — export the current view to a file via the system share sheet.
- **Monthly spending trend** (last 6 months) on the Statistics screen.
- **Compare months** — pick any two months on Statistics to see the spending/income **% change** and the transaction-count delta, with a plain-language insight (e.g. "You spent 15% more than last month").

### Changed
- When a closing balance doesn't reconcile, the app now offers to **add the missing transaction inline** — prefilled with the shortfall and the inferred income/expense type — instead of navigating to the reconciliation screen.

## [2.1.3] - 2026-08-06
### Changed
- Removed the unused `RECEIVE_SMS` permission — the app only reads existing inbox messages, it never intercepts incoming SMS. This shrinks the permission footprint and reduces the "financial fraud" warning some devices show for apps that can intercept messages.

### Fixed
- Monthly balance reminders no longer depend solely on push. The app now prompts for the opening balance whenever it's opened during the first 5 days of the month (and the closing balance in the last 3 days) if not yet recorded — so a missed or OEM-blocked push no longer means a missed reminder.

## [2.1.2] - 2026-07-29
### Fixed
- Promotional / informational SMS (EMI-conversion offers, "HURRY … % off", pre-approved loans, T&C footers, etc.) were being recorded as transactions because they quote an amount. They are now filtered out before parsing, while genuine transactions — including real EMI installment debits — are still recorded.

## [2.1.1] - 2026-07-29
### Fixed
- Duplicate transactions when the same bank SMS is delivered more than once (a telecom glitch). Transactions are now de-duplicated by their bank reference number (falling back to the message text), so re-delivered messages collapse into a single entry.
- Credit-card bill payments were misclassified as income (CREDIT) because the acknowledgment SMS says "payment ... credited to your card". Payments toward a card are now correctly recorded as an expense (DEBIT), while card cashback/refunds remain CREDIT.

## [2.1.0] - 2026-06-27
### Added
- App launcher icon.
- Indigo light/dark theme that follows the system setting, plus an in-app theme switcher (System / Light / Dark).
- First-run name prompt and a time-of-day greeting on the dashboard.

### Changed
- UI redesign across the dashboard, stats, and reconciliation screens — flat themed cards, consistent spacing, semantic income/expense colors, and themed dialogs/toasts that adapt to light and dark.
- Dashboard now defaults to the current month's transactions instead of "All" (All is still available in the date filter).

### Fixed
- Layout overflows in the date-filter sheet and the dashboard summary card.

## [2.0.0] - 2026-06-27
### Changed
- **Rebranded to MoneyCap** — new name, app/bundle ID `com.moneycap.app`, and package identifiers across Android/iOS/macOS/Linux/web.
- **Reminders now delivered via FCM push instead of local notifications.** On-device scheduled alarms are silently dropped by aggressive battery managers (vivo, Xiaomi, Oppo, etc.); push reliably reaches the device. A scheduled GitHub Action sends the opening (1st, 9 AM IST) and closing (last day, 8 PM IST) reminders to FCM topics the app subscribes to.
- **First-time SMS sync is ~10x faster** (~2 min → ~12 s): single-pass inbox read (removed O(n²) offset pagination), regex parsing moved to a background isolate, regexes compiled once, and batched single-transaction DB inserts.

### Added
- Shimmer **skeleton loader** while transactions load/sync (replaces the spinner).
- **Floating toast** notifications — non-queuing, swipe-to-dismiss, with success/error styling (replaces all SnackBars).
- **Automated signed releases** via GitHub Actions: pushing a `v*` tag builds a signed APK and publishes a GitHub Release.
- Firebase Cloud Messaging integration (`firebase_core`, `firebase_messaging`) with topic subscriptions and foreground/background handling.

### Removed
- On-device AlarmManager scheduling, exact-alarm code, and `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` permissions (superseded by FCM push).
- Stale build/analysis log files.

### Fixed
- Auto-sync toggle now reflects its state instantly instead of waiting for the sync to finish.
- Corrected a broken Android NDK reference that prevented release builds.

## [1.0.0] - 2026-02-10
### Added
- Monthly opening/closing balance tracking.
- Balance reconciliation screen with discrepancy calculation and mark-as-reconciled flow.
- Missing transaction entry from reconciliation with date selection.
- Monthly balance prompts on first/last day of month.
- Local notification scheduling for balance reminders.
- Date filter bottom sheet with presets and custom range picker.

### Changed
- Manual transaction entry supports custom date.
- Notification scheduling falls back to inexact alarms when exact alarms are not allowed.
- Database migration adds `monthly_balances` table and index.

### Fixed
- Prevents duplicate balance prompt dialogs by tracking dialog state.

