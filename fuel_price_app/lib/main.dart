import 'package:flutter/material.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/notifications/notification_service.dart';
import 'package:fuel_price_app/scheduling/background_sync.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();
  await db.init();

  // Initialize notifications
  final notificationService = NotificationService();
  await notificationService.init();

  // Register background sync at 18:00 CET
  await initBackgroundSync();

  runApp(FuelPriceApp(database: db));
}
