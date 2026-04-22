# Changelog
All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [Unreleased]

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

