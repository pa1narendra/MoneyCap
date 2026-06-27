import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around the local-notification plugin. Reminders themselves are
/// delivered via FCM push (see [PushService]); this class is used to:
///  - display a reminder while the app is in the FOREGROUND (FCM notification
///    messages aren't shown automatically in that case), and
///  - funnel notification taps into a single stream the dashboard listens to,
///    so both local taps and FCM taps deep-link into reconciliation.
class NotificationService {
  static final NotificationService instance = NotificationService._init();
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  static const _channelId = 'balance_reminders';
  static const _channelName = 'Balance Reminders';
  static const _channelDescription = 'Monthly balance entry reminders';

  final StreamController<String> _notificationTapController =
      StreamController<String>.broadcast();
  Stream<String> get onNotificationTap => _notificationTapController.stream;

  NotificationService._init();

  // Initialize the plugin and request notification permission.
  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    final android = _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    // Request permission (Android 13+)
    await android?.requestNotificationsPermission();

    // Create the channel up front so background FCM notifications (displayed by
    // the system while the app is killed) land in the right channel.
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );
  }

  // Check if app was launched by tapping a (locally shown) notification.
  Future<String?> getInitialPayload() async {
    final details = await _notifications.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true &&
        details?.notificationResponse?.payload != null) {
      return details!.notificationResponse!.payload;
    }
    return null;
  }

  /// Display a reminder immediately (used for foreground FCM messages).
  Future<void> showReminder({
    required String title,
    required String body,
    required String payload,
  }) async {
    await _notifications.show(
      payload.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: payload,
    );
  }

  /// Emit a tap payload (e.g. from an FCM notification tap) into the shared
  /// stream so the dashboard handles it the same way as a local-notification tap.
  void emitTap(String payload) {
    _notificationTapController.add(payload);
  }

  void _handleNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      _notificationTapController.add(response.payload!);
    }
  }

  void dispose() {
    _notificationTapController.close();
  }
}
