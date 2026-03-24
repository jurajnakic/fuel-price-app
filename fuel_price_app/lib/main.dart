import 'package:flutter/material.dart';
import 'package:fuel_price_app/data/database.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();
  await db.init();

  runApp(FuelPriceApp(database: db));
}
