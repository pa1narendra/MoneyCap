# Changelog
All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [Unreleased]
### Added
- App launcher icon.
- Indigo light/dark theme that follows the system setting, plus an in-app theme switcher (System / Light / Dark).
- First-run name prompt and a time-of-day greeting on the dashboard.

### Changed
- UI redesign across the dashboard, stats, and reconciliation screens — flat themed cards, consistent spacing, semantic income/expense colors, and themed dialogs/toasts that adapt to light and dark.

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

