import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/transaction_provider.dart';
import '../services/sms_service.dart';
import '../theme/app_theme.dart';

/// First run: name -> SMS disclosure (shown BEFORE the system permission
/// prompt, as Play's prominent-disclosure rule requires) -> first import with
/// a progress bar.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { welcome, disclosure, importing, done }

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController();
  _Step _step = _Step.welcome;
  bool _permanentlyDenied = false;
  int _imported = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _allowSms() async {
    final status = await Permission.sms.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() => _permanentlyDenied = status.isPermanentlyDenied);
      return;
    }
    setState(() => _step = _Step.importing);
    final provider = context.read<TransactionProvider>();
    final result = await provider.syncSms();
    if (!mounted) return;
    setState(() {
      _imported = result.inserted;
      _step = _Step.done;
    });
  }

  Future<void> _finish() async {
    final settings = context.read<SettingsProvider>();
    await settings.setUserName(_name.text);
    await settings.completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: switch (_step) {
                  _Step.welcome => _welcome(context),
                  _Step.disclosure => _disclosure(context),
                  _Step.importing => _importing(context),
                  _Step.done => _done(context),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('welcome'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.account_balance_wallet_outlined, size: 56, color: cs.primary),
        const SizedBox(height: AppSpacing.md),
        Text('Welcome to MoneyCap',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.sm),
        Text('Your money, captured automatically from your bank SMS.',
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => setState(() => _step = _Step.disclosure),
          decoration: const InputDecoration(
            labelText: 'What should we call you? (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => setState(() => _step = _Step.disclosure),
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  Widget _disclosure(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget point(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(body, style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        );
    return Column(
      key: const ValueKey('disclosure'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SMS access',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'MoneyCap reads the SMS already in your inbox to find bank and card '
          'transactions, so you never have to type them in.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        point(Icons.mark_email_read_outlined, 'Only bank messages',
            'Messages from personal phone numbers and promotional senders are skipped. OTPs, failed payments and bill reminders are ignored.'),
        point(Icons.phone_android, 'Stays on this phone',
            'Transactions are stored only on this device. They are not uploaded and are excluded from Google Drive backup.'),
        point(Icons.sync, 'Read-only',
            'MoneyCap never sends, deletes or intercepts messages. New SMS are picked up when you open the app or in a periodic background sync.'),
        point(Icons.notifications_none, 'Reminders',
            'A generic monthly balance reminder arrives by push (Firebase). It carries no personal data, and you can turn it off in Settings.'),
        if (_permanentlyDenied) ...[
          Card(
            color: cs.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                'SMS permission is blocked. Enable it in App settings > Permissions, or continue and add transactions manually.',
                style: TextStyle(color: cs.onErrorContainer),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const OutlinedButton(onPressed: openAppSettings, child: Text('Open app settings')),
        ],
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _allowSms,
            icon: const Icon(Icons.check),
            label: const Text('Allow SMS access'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _finish,
            child: const Text('Not now, I\'ll add transactions manually'),
          ),
        ),
      ],
    );
  }

  Widget _importing(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = context.watch<TransactionProvider>().syncProgress;
    return Column(
      key: const ValueKey('importing'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Importing your transactions',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.sm),
        Text(
          p == null ? 'Reading your inbox…' : 'Processing messages… ${(p * 100).round()}%',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        LinearProgressIndicator(value: p, minHeight: 8, borderRadius: BorderRadius.circular(4)),
      ],
    );
  }

  Widget _done(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final failed = context.read<TransactionProvider>().lastSyncStatus == SyncStatus.error;
    return Column(
      key: const ValueKey('done'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(failed ? Icons.error_outline : Icons.check_circle_outline,
            size: 56, color: failed ? cs.error : cs.primary),
        const SizedBox(height: AppSpacing.md),
        Text(
          failed
              ? 'Import hit a problem'
              : 'Found $_imported transaction${_imported == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          failed
              ? 'You can retry any time with pull-to-refresh on the dashboard.'
              : 'Tap any transaction to fix its category, mark it as a transfer, or edit it.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: _finish, child: const Text('Go to dashboard')),
        ),
      ],
    );
  }
}
