import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'notification_service.dart';

/// Background/terminated FCM handler. Reminder pushes are notification
/// messages the system displays itself, so there's nothing to do here.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {}

/// FCM push reminders (reliable on OEMs that kill local alarms). A scheduled
/// GitHub Action broadcasts a GENERIC reminder to the `balance_opening` /
/// `balance_closing` topics. The app never sends anything to Firebase; the
/// only data Google receives is the device's push token.
///
/// Optional: if google-services.json wasn't present at build time, Firebase
/// fails to initialize and reminders fall back to the in-app prompt. Users
/// can also switch push reminders off (unsubscribes and deletes the token).
class PushService {
  static final PushService instance = PushService._init();
  PushService._init();

  static const _topics = ['balance_opening', 'balance_closing'];
  static bool _available = false;
  bool _listening = false;

  static bool get available => _available;

  /// Call once from main(). Never throws.
  static Future<bool> initFirebase() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      _available = true;
    } catch (e) {
      debugPrint('Firebase unavailable, push reminders disabled: $e');
      _available = false;
    }
    return _available;
  }

  Future<void> init({required bool enabled}) async {
    if (!_available) return;
    final fm = FirebaseMessaging.instance;
    if (!enabled) {
      await setEnabled(false);
      return;
    }
    await fm.requestPermission();
    for (final t in _topics) {
      await fm.subscribeToTopic(t);
    }
    if (_listening) return;
    _listening = true;

    // Foreground: show it through the local channel so the tap deep-links.
    FirebaseMessaging.onMessage.listen((message) {
      final payload = _payloadFor(message);
      if (payload == null) return;
      NotificationService.instance.showReminder(
        title: message.notification?.title ?? 'Balance Reminder',
        body: message.notification?.body ?? 'Tap to update your balance',
        payload: payload,
      );
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final p = _payloadFor(message);
      if (p != null) NotificationService.instance.emitTap(p);
    });
    final initial = await fm.getInitialMessage();
    final p = initial == null ? null : _payloadFor(initial);
    if (p != null) NotificationService.instance.emitTap(p);
  }

  Future<void> setEnabled(bool on) async {
    if (!_available) return;
    try {
      final fm = FirebaseMessaging.instance;
      if (on) {
        await init(enabled: true);
      } else {
        for (final t in _topics) {
          await fm.unsubscribeFromTopic(t);
        }
        await fm.deleteToken();
      }
    } catch (e) {
      debugPrint('PushService.setEnabled($on) failed: $e');
    }
  }

  /// `type:yyyy-MM`, or null if the push data is malformed (push data is
  /// untrusted input and must never crash the app).
  String? _payloadFor(RemoteMessage message) {
    final type = message.data['type'] == 'closing' ? 'closing' : 'opening';
    final now = DateTime.now();
    final month = message.data['month'] ?? '${now.year}-${now.month.toString().padLeft(2, '0')}';
    if (month is! String || !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month)) return null;
    return '$type:$month';
  }
}
