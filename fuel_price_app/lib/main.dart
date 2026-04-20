import 'package:flutter/material.dart';
import 'package:fuel_price_app/data/app_logger.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/settings_repository.dart';
import 'package:fuel_price_app/notifications/notification_service.dart';
import 'package:fuel_price_app/scheduling/background_sync.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();
  await db.init();

  final logger = AppLogger(db);
  await logger.log('app', 'START');

  // Initialize notifications
  final notificationService = NotificationService();
  await notificationService.init();

  // Read user's notification hour so WorkManager fires at the right time.
  final notifSettings = await SettingsRepository(db).getNotificationSettings();
  final notifHour = (notifSettings['hour'] as int?) ?? 9;
  await logger.log('app', 'notifHour=$notifHour day=${notifSettings['day']} enabled=${notifSettings['enabled']}');

  runApp(FuelPriceApp(database: db));

  // Register background sync after UI is up — non-blocking
  initBackgroundSync(targetLocalHour: notifHour);
  await logger.log('app', 'initBackgroundSync scheduled for hour=$notifHour');
}
