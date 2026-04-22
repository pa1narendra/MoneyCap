import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService instance = NotificationService._init();
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _exactAlarmAllowed = true;

  final StreamController<String> _notificationTapController =
      StreamController<String>.broadcast();
  Stream<String> get onNotificationTap => _notificationTapController.stream;

  NotificationService._init();

  // Initialize notifications and request permission
  Future<void> initialize() async {
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    // Request permission (Android 13+)
    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    await _loadAndroidExactAlarmPermission();
  }

  // Check if app was launched from a notification
  Future<String?> getInitialPayload() async {
    final details = await _notifications.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true &&
        details?.notificationResponse?.payload != null) {
      return details!.notificationResponse!.payload;
    }
    return null;
  }

  // Schedule notifications for next 12 months
  Future<void> scheduleMonthlyBalanceNotifications() async {
    // Cancel all existing notifications first
    await _notifications.cancelAll();

    final now = DateTime.now();

    for (int i = 0; i < 12; i++) {
      final targetMonth = DateTime(now.year, now.month + i, 1);
      final monthName = DateFormat('MMMM yyyy').format(targetMonth);

      // Schedule opening balance notification (1st at 9 AM)
      final openingDate = DateTime(targetMonth.year, targetMonth.month, 1, 9, 0);
      if (openingDate.isAfter(now)) {
        await _scheduleNotification(
          id: i * 2,
          title: 'Opening Balance Required',
          body: 'Enter your opening balance for $monthName',
          scheduledDate: openingDate,
          payload: 'opening:${DateFormat('yyyy-MM').format(targetMonth)}',
        );
      }

      // Schedule closing balance notification (last day at 8 PM)
      final lastDay = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
      final closingDate = DateTime(targetMonth.year, targetMonth.month, lastDay, 20, 0);
      if (closingDate.isAfter(now)) {
        await _scheduleNotification(
          id: i * 2 + 1,
          title: 'Closing Balance Required',
          body: 'Enter your closing balance for $monthName',
          scheduledDate: closingDate,
          payload: 'closing:${DateFormat('yyyy-MM').format(targetMonth)}',
        );
      }
    }
  }

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String payload,
  }) async {
    final tzScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);
    final scheduleMode = _exactAlarmAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    await _notifications.zonedSchedule(
      id,
      title,
      body,
      tzScheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'balance_reminders',
          'Balance Reminders',
          channelDescription: 'Monthly balance entry reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: scheduleMode,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  void _handleNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      _notificationTapController.add(response.payload!);
    }
  }

  // Cancel all notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  void dispose() {
    _notificationTapController.close();
  }

  Future<void> _loadAndroidExactAlarmPermission() async {
    final status = await Permission.scheduleExactAlarm.status;
    if (status.isGranted) {
      _exactAlarmAllowed = true;
      return;
    }

    final requested = await Permission.scheduleExactAlarm.request();
    _exactAlarmAllowed = requested.isGranted;
  }
}
