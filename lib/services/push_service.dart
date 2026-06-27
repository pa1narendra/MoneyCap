import 'package:firebase_messaging/firebase_messaging.dart';
import 'notification_service.dart';

/// Handles FCM push reminders (the reliable delivery path on OEMs that block
/// local AlarmManager notifications, e.g. vivo/Xiaomi/Oppo). A scheduled cloud
/// job (GitHub Actions cron) broadcasts to the `balance_opening` /
/// `balance_closing` topics on the 1st and last day of each month; Google Play
/// Services delivers them even when the app is killed.
///
/// Messages carry `data: {type: opening|closing, month: yyyy-MM}` so a tap can
/// deep-link into reconciliation, reusing the existing payload flow handled in
/// the dashboard via [NotificationService.onNotificationTap].
class PushService {
  static final PushService instance = PushService._init();
  final FirebaseMessaging _fm = FirebaseMessaging.instance;

  PushService._init();

  Future<void> init() async {
    // Request push permission (Android 13+ / iOS). Harmless if already granted.
    await _fm.requestPermission();

    // Subscribe to the topics the scheduled cloud job broadcasts to.
    await _fm.subscribeToTopic('balance_opening');
    await _fm.subscribeToTopic('balance_closing');

    // Foreground: FCM notification messages are NOT shown automatically, so we
    // display them through the local-notification channel (this also makes the
    // tap go through the existing reconciliation deep-link flow).
    FirebaseMessaging.onMessage.listen((message) {
      NotificationService.instance.showReminder(
        title: message.notification?.title ?? 'Balance Reminder',
        body: message.notification?.body ?? 'Tap to update your balance',
        payload: _payloadFor(message),
      );
    });

    // App backgrounded, user tapped the system-shown notification.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      NotificationService.instance.emitTap(_payloadFor(message));
    });

    // App was terminated and launched by tapping the notification.
    final initial = await _fm.getInitialMessage();
    if (initial != null) {
      NotificationService.instance.emitTap(_payloadFor(initial));
    }
  }

  /// Converts an FCM message into the `type:yyyy-MM` payload the dashboard's
  /// notification-tap handler expects. Always returns a valid value.
  String _payloadFor(RemoteMessage message) {
    final type = message.data['type'] == 'closing' ? 'closing' : 'opening';
    final now = DateTime.now();
    final month = message.data['month'] ??
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    return '$type:$month';
  }
}
