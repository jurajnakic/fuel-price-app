import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fuel_price_app/domain/price_cycle_service.dart';
import 'package:fuel_price_app/models/fuel_type.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;

  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Zagreb'));
    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'fuel_price_channel',
      'Cijene goriva',
      channelDescription: 'Obavijesti o promjenama cijena goriva',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@drawable/ic_notification',
    ),
  );

  static const int _notificationId = 0;

  String? _buildBody(Map<FuelType, ({double predicted, double? current})> fuelPredictions) {
    final lines = <String>[];
    for (final entry in fuelPredictions.entries) {
      final trend = trendIndicator(entry.value.predicted, entry.value.current);
      if (trend == null || trend == '→') continue;
      final priceStr = entry.value.predicted.toStringAsFixed(2).replaceAll('.', ',');
      lines.add('${entry.key.shortName}: $priceStr € $trend');
    }
    if (lines.isEmpty) return null;
    return lines.join(' | ');
  }

  String _buildTitle(String notificationDay) => notificationDay == 'monday'
      ? 'Promjena cijene goriva sutra'
      : 'Promjena cijene goriva u utorak';

  /// Compute the next occurrence of [targetWeekday] at [hour]:00 in Zagreb time.
  /// If today matches [targetWeekday] but it's past [hour], advances to next week.
  static tz.TZDateTime nextScheduledTime(String day, int hour) {
    final targetWeekday = switch (day) {
      'monday' => DateTime.monday,
      'saturday' => DateTime.saturday,
      'sunday' => DateTime.sunday,
      _ => DateTime.monday,
    };
    final now = tz.TZDateTime.now(tz.local);
    var candidate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
    // Advance day-by-day until weekday matches AND time is in the future.
    while (candidate.weekday != targetWeekday || !candidate.isAfter(now)) {
      candidate = tz.TZDateTime(tz.local, candidate.year, candidate.month,
          candidate.day + 1, hour);
    }
    return candidate;
  }

  /// Schedule the next price-change notification at [notifHour] on the next
  /// matching [notificationDay], using an exact alarm so it fires under Doze
  /// regardless of WorkManager state. Replaces any pending notification.
  ///
  /// Returns the scheduled time, or null if there's nothing to notify (no
  /// fuels with a non-flat trend).
  Future<tz.TZDateTime?> scheduleNextPriceNotification({
    required String notificationDay,
    required int notifHour,
    required Map<FuelType, ({double predicted, double? current})> fuelPredictions,
  }) async {
    final body = _buildBody(fuelPredictions);
    // Always cancel pending so stale predictions don't get delivered if the
    // current run has nothing to show.
    await _plugin.cancel(_notificationId);
    if (body == null) return null;

    final scheduled = nextScheduledTime(notificationDay, notifHour);
    await _plugin.zonedSchedule(
      _notificationId,
      _buildTitle(notificationDay),
      body,
      scheduled,
      _details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
    return scheduled;
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Diagnostic: post a notification immediately (no scheduling, no Doze).
  /// If this works but scheduled notifications don't, the FLN scheduled-payload
  /// pathway (or OEM background block) is broken.
  Future<void> showTestNow() async {
    await _plugin.show(
      _notificationId,
      'Test obavijest',
      'Vrijeme: ${DateTime.now().toIso8601String()}',
      _details,
    );
  }
}
