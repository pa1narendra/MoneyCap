import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/transaction_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/background_sync.dart';
import 'services/backup_service.dart';
import 'services/push_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Both are optional and never throw: a build without Firebase config or a
  // device without WorkManager still runs.
  await PushService.initFirebase();
  try {
    await BackgroundSync.init();
  } catch (e) {
    debugPrint('Background sync unavailable: $e');
  }
  BackupService.cleanupExports(); // remove exports left from a previous run

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return MaterialApp(
      title: 'MoneyCap',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.themeMode,
      home: !settings.loaded
          ? const Scaffold(body: SizedBox.shrink())
          : settings.onboarded
              ? const DashboardScreen()
              : const OnboardingScreen(),
    );
  }
}
