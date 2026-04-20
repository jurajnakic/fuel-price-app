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

  /// Show a price change notification immediately.
  Future<void> showPriceNotification({
    required String notificationDay,
    required Map<FuelType, ({double predicted, double? current})> fuelPredictions,
  }) async {
    final body = _buildBody(fuelPredictions);
    if (body == null) return;
    await _plugin.show(0, _buildTitle(notificationDay), body, _details);
  }

  /// Schedule a price notification for [targetHour] local time today.
  /// Used when WorkManager fires before the user's chosen notification hour —
  /// OS delivers it at [targetHour] even if device is asleep/doze.
  Future<void> schedulePriceNotification({
    required String notificationDay,
    required int targetHour,
    required Map<FuelType, ({double predicted, double? current})> fuelPredictions,
  }) async {
    final body = _buildBody(fuelPredictions);
    if (body == null) return;
    final now = tz.TZDateTime.now(tz.local);
    final scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, targetHour);
    if (!scheduled.isAfter(now)) return; // don't schedule in the past
    await _plugin.zonedSchedule(
      0,
      _buildTitle(notificationDay),
      body,
      scheduled,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
