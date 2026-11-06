import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/transaction_provider.dart';
import '../services/backup_service.dart';
import 'app_toast.dart';

/// Creates a backup file and opens the share sheet. Returns false if it failed.
Future<bool> shareBackup(BuildContext context, TransactionProvider provider) async {
  try {
    final json = await provider.exportBackupJson();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final file = await BackupService.writeExportFile('moneycap_backup_$stamp.json', json);
    await Share.shareXFiles([XFile(file.path, mimeType: 'application/json')],
        subject: 'MoneyCap backup');
    return true;
  } catch (e) {
    if (context.mounted) showToast(context, 'Backup failed', isError: true);
    return false;
  }
}

/// Reminder before an action that clears or replaces data. Backing up is
/// offered, never required. Returns true if the action should go ahead.
///
/// [onBackup] exists so tests can stand in for the share sheet.
Future<bool> confirmWithBackupReminder(
  BuildContext context,
  TransactionProvider? provider, {
  required String title,
  required String message,
  required String confirmLabel,
  bool allowCancel = true,
  Future<bool> Function()? onBackup,
}) async {
  var backedUp = false;
  while (true) {
    if (!context.mounted) return false;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: allowCancel,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 12),
              Row(children: [
                Icon(backedUp ? Icons.check_circle_outline : Icons.info_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(backedUp
                      ? 'Backup created. Save it somewhere safe before you continue.'
                      : 'You may want a backup first. It keeps a copy you can restore later.'),
                ),
              ]),
            ],
          ),
        ),
        // Stacked: three buttons don't fit in a row on a phone.
        actionsOverflowAlignment: OverflowBarAlignment.end,
        actions: [
          if (allowCancel)
            TextButton(onPressed: () => Navigator.pop(d, 'cancel'), child: const Text('Cancel')),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(d, 'backup'),
            icon: const Icon(Icons.backup_outlined),
            label: Text(backedUp ? 'Back up again' : 'Back up first'),
          ),
          FilledButton(onPressed: () => Navigator.pop(d, 'go'), child: Text(confirmLabel)),
        ],
      ),
    );
    if (choice == 'go') return true;
    if (choice != 'backup') return false;
    if (onBackup != null) {
      if (await onBackup()) backedUp = true;
    } else {
      if (!context.mounted) return false;
      if (await shareBackup(context, provider!)) backedUp = true;
    }
  }
}
