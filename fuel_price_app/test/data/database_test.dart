import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fuel_price_app/data/database.dart';

void main() {
  late AppDatabase db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase(inMemory: true);
    await db.init();
  });

  tearDown(() async {
    await db.close();
  });

  test('creates all tables', () async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
    );
    final names = tables.map((t) => t['name'] as String).toSet();
    expect(names, containsAll([
      'oil_prices', 'exchange_rates', 'fuel_prices',
      'fuel_order', 'fuel_visibility', 'notification_settings',
      'config_version',
    ]));
  });

  test('oil_prices insert and query', () async {
    await db.insert('oil_prices', {
      'date': '2026-03-20',
      'cif_med': 650.5,
      'source': 'BZ=F',
    });
    final rows = await db.query('oil_prices');
    expect(rows.length, 1);
    expect(rows.first['cif_med'], 650.5);
  });
}
