import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'sms_service.dart';
import 'widget_service.dart';

const _taskName = 'moneycap.smsSync';
const _uniqueName = 'moneycap-periodic-sms-sync';

/// Entry point WorkManager runs in a background isolate. It must be a
/// top-level function annotated as an entry point.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final r = await SmsService().syncSms();
      if (r.status == SyncStatus.ok) await WidgetService.refresh();
      // noPermission isn't a retryable failure.
      return r.status != SyncStatus.error;
    } catch (e) {
      debugPrint('Background sync failed: $e');
      return false;
    }
  });
}

/// Periodic background SMS sync (Android WorkManager). The OS decides the
/// exact time; 6 hours is a battery-friendly cadence for a finance log.
class BackgroundSync {
  BackgroundSync._();

  static Future<void> init() async {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) return;
    await Workmanager().initialize(backgroundDispatcher);
  }

  static Future<void> setEnabled(bool on) async {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) return;
    try {
      if (on) {
        await Workmanager().registerPeriodicTask(
          _uniqueName,
          _taskName,
          frequency: const Duration(hours: 6),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
          constraints: Constraints(
            networkType: NetworkType.notRequired,
            requiresBatteryNotLow: true,
          ),
        );
      } else {
        await Workmanager().cancelByUniqueName(_uniqueName);
      }
    } catch (e) {
      debugPrint('BackgroundSync.setEnabled($on) failed: $e');
    }
  }
}
