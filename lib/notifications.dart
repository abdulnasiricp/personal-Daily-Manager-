import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'db.dart';

/// Schedules local notifications. Everything is rebuilt from the database
/// whenever data changes or the app is opened, so nothing can get out of sync.
/// Each notification is a one-shot alarm at an absolute instant (repeating
/// reminders are expanded into their next occurrences), which avoids any
/// time-zone lookup and survives reboots via the plugin's boot receiver.
class Notifier {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static Future<void> _last = Future<void>.value();

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Task, bill and loan repayment reminders',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    _ready = true;
  }

  static Future<bool> notificationsEnabled() async =>
      await _android?.areNotificationsEnabled() ?? false;

  static Future<bool> canScheduleExact() async =>
      await _android?.canScheduleExactNotifications() ?? false;

  /// Asks for the Android 13+ notification permission if it is not granted yet.
  static Future<bool> ensurePermission() async {
    if (await notificationsEnabled()) return true;
    return await _android?.requestNotificationsPermission() ?? false;
  }

  /// Opens the system screen where exact alarms can be allowed (Android 12+).
  static Future<void> requestExactAlarms() async {
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  static Future<void> showTest() async {
    await _plugin.show(
        0, 'Personal Daily Manager', 'Notifications are working.', _details);
  }

  /// Rebuilds all scheduled notifications. Calls are queued one after another.
  static Future<void> rescheduleAll(AppDb db) {
    _last = _last.then((_) => _run(db)).catchError((_) {});
    return _last;
  }

  static Future<void> _run(AppDb db) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    final now = DateTime.now();
    final items = await db.agenda(now, forNotifications: true);
    final exact = await canScheduleExact();
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    var id = 1;
    // Android allows roughly 500 pending alarms per app; stay well below.
    for (final it in items.take(400)) {
      try {
        await _plugin.zonedSchedule(
          id++,
          it.title,
          it.body,
          tz.TZDateTime.from(it.when, tz.UTC),
          _details,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (_) {
        // A single bad item must never stop the others from being scheduled.
      }
    }
  }
}
