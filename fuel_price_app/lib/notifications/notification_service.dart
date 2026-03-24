import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fuel_price_app/domain/price_cycle_service.dart';
import 'package:fuel_price_app/models/fuel_type.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;

  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);
  }

  /// Show a price change notification immediately.
  /// Called by WorkManager at the scheduled time.
  Future<void> showPriceNotification({
    required String notificationDay,
    required Map<FuelType, ({double predicted, double? current})> fuelPredictions,
  }) async {
    // Build title
    final title = notificationDay == 'monday'
        ? 'Promjena cijene goriva sutra'
        : 'Promjena cijene goriva u utorak';

    // Build body — only fuels with actual price changes (omit unchanged per spec)
    final lines = <String>[];
    for (final entry in fuelPredictions.entries) {
      final trend = trendIndicator(entry.value.predicted, entry.value.current);
      if (trend == null || trend == '→') continue;
      final priceStr = entry.value.predicted.toStringAsFixed(2).replaceAll('.', ',');
      lines.add('${entry.key.shortName}: $priceStr € $trend');
    }

    if (lines.isEmpty) return; // Don't send empty notification

    final body = lines.join(' | ');

    await _plugin.show(
      0,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'fuel_price_channel',
          'Cijene goriva',
          channelDescription: 'Obavijesti o promjenama cijena goriva',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
