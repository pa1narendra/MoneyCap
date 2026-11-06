import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/backup_service.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_toast.dart';
import '../widgets/backup_reminder.dart';
import '../widgets/input_dialogs.dart';
import 'category_rules_screen.dart';
import 'hidden_duplicates_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final settings = context.watch<SettingsProvider>();
    final cs = Theme.of(context).colorScheme;

    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.xs),
          child: Text(t, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        header('Sync'),
        SwitchListTile(
          secondary: const Icon(Icons.sync),
          title: const Text('Automatic sync'),
          subtitle: const Text('When you open the app, and every few hours in the background'),
          value: provider.isAutoSync,
          onChanged: (v) {
            provider.toggleAutoSync(v);
            showToast(context, 'Automatic sync ${v ? "on" : "off"}');
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_outlined),
          title: const Text('Monthly balance reminders (push)'),
          subtitle: Text(PushService.available
              ? 'A generic reminder via Firebase. Turning it off deletes the push token.'
              : 'Not available in this build. You\'ll still be reminded inside the app.'),
          value: PushService.available && settings.pushReminders,
          onChanged: PushService.available
              ? (v) async {
                  await settings.setPushReminders(v);
                  await PushService.instance.setEnabled(v);
                }
              : null,
        ),
        header('Personalise'),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('Your name'),
          subtitle: Text((settings.userName ?? '').isEmpty ? 'Not set' : settings.userName!),
          onTap: () => _editName(context, settings),
        ),
        ListTile(
          leading: const Icon(Icons.brightness_6),
          title: const Text('Theme'),
          trailing: DropdownButton<ThemeMode>(
            value: settings.themeMode,
            underline: const SizedBox.shrink(),
            onChanged: (m) => settings.setThemeMode(m!),
            items: const [
              DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.rule),
          title: const Text('Category rules'),
          subtitle: Text('${provider.categoryRules.length} custom rule(s)'),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const CategoryRulesScreen())),
        ),
        header('Your data'),
        ListTile(
          leading: const Icon(Icons.filter_alt_outlined),
          title: const Text('Hidden duplicates'),
          subtitle: const Text('Messages that repeat a payment already recorded'),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const HiddenDuplicatesScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Back up everything'),
          subtitle: const Text('Saves a file you keep (Drive, email to yourself, a PC…)'),
          onTap: () => _backup(context, provider),
        ),
        ListTile(
          leading: const Icon(Icons.restore),
          title: const Text('Restore from backup'),
          subtitle: const Text('Replaces all data on this phone'),
          onTap: () => _restore(context, provider),
        ),
        ListTile(
          leading: Icon(Icons.refresh, color: cs.error),
          title: Text('Re-import SMS transactions', style: TextStyle(color: cs.error)),
          subtitle: const Text('Clears SMS-imported rows and scans the inbox again. '
              'Manual entries, balances, categories and budgets are kept.'),
          onTap: () => _reset(context, provider),
        ),
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            'Privacy: transactions live only on this phone and are excluded from Google Drive '
            'auto-backup. MoneyCap never uploads your SMS or transactions. The only network use '
            'is receiving the optional reminder push.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ),
      ]),
    );
  }

  Future<void> _editName(BuildContext context, SettingsProvider settings) async {
    // Optional, so an empty answer is allowed: it just removes the name.
    final name = await showTextDialog(
      context,
      title: 'Your name',
      initial: settings.userName ?? '',
      capitalization: TextCapitalization.words,
    );
    if (name != null) await settings.setUserName(name);
  }

  Future<void> _backup(BuildContext context, TransactionProvider provider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Back up everything?'),
        content: const Text(
            'The backup file contains all your transactions and the original bank SMS text. '
            'Keep it somewhere private.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Create backup')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await shareBackup(context, provider);
  }

  Future<void> _restore(BuildContext context, TransactionProvider provider) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final f = picked?.files.single;
    if (f == null || !context.mounted) return;
    if (f.size > 100 * 1024 * 1024) {
      showToast(context, 'That file is too large to be a MoneyCap backup', isError: true);
      return;
    }
    final String json;
    try {
      json = f.bytes != null ? utf8.decode(f.bytes!) : await File(f.path!).readAsString();
      BackupService.decode(json); // validate before asking to overwrite
    } on BackupException catch (e) {
      if (context.mounted) showToast(context, e.message, isError: true);
      return;
    } catch (_) {
      if (context.mounted) showToast(context, 'Could not read that file', isError: true);
      return;
    }
    if (!context.mounted) return;
    final ok = await confirmWithBackupReminder(
      context,
      provider,
      title: 'Replace all data?',
      message: 'Everything on this phone, including manual transactions, balances, budgets and '
          'names, will be replaced by the file you picked.',
      confirmLabel: 'Restore',
    );
    if (!ok) return;
    try {
      await provider.restoreBackup(json);
      if (context.mounted) showToast(context, 'Backup restored');
    } catch (e) {
      if (context.mounted) showToast(context, 'Restore failed: nothing was changed', isError: true);
    }
  }

  Future<void> _reset(BuildContext context, TransactionProvider provider) async {
    final ok = await confirmWithBackupReminder(
      context,
      provider,
      title: 'Re-import SMS transactions?',
      message: 'SMS transactions, and any edits you made to them, are cleared and the inbox is '
          'scanned again. Manual entries, balances, categories, budgets and names are kept. '
          'Transactions you deleted stay deleted.',
      confirmLabel: 'Re-import',
    );
    if (!ok) return;
    await provider.resetSmsData();
    if (context.mounted) showToast(context, 'SMS transactions re-imported');
  }
}
