import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase(inMemory: true);
    await db.init();
    repo = SettingsRepository(db);
  });

  tearDown(() async => await db.close());

  test('returns default fuel order', () async {
    final order = await repo.getFuelOrder();
    expect(order, ['es95', 'es100', 'eurodizel', 'unp10kg']);
  });

  test('updates fuel order', () async {
    await repo.saveFuelOrder(['eurodizel', 'es95', 'es100', 'unp10kg']);
    final order = await repo.getFuelOrder();
    expect(order.first, 'eurodizel');
  });

  test('returns default visibility (all visible)', () async {
    final vis = await repo.getFuelVisibility();
    expect(vis.values.every((v) => v), isTrue);
  });

  test('toggles fuel visibility', () async {
    await repo.setFuelVisibility('es100', false);
    final vis = await repo.getFuelVisibility();
    expect(vis['es100'], isFalse);
    expect(vis['es95'], isTrue);
  });

  test('returns default notification settings', () async {
    final settings = await repo.getNotificationSettings();
    expect(settings['day'], 'monday');
    expect(settings['hour'], 9);
    expect(settings['enabled'], 1);
  });

  test('updates notification settings', () async {
    await repo.saveNotificationSettings(day: 'saturday', hour: 10);
    final settings = await repo.getNotificationSettings();
    expect(settings['day'], 'saturday');
    expect(settings['hour'], 10);
  });

  test('returns default notification fuels (all enabled)', () async {
    final fuels = await repo.getNotificationFuels();
    expect(fuels.values.every((v) => v), isTrue);
  });

  test('toggles notification fuel', () async {
    await repo.setNotificationFuel('unp10kg', false);
    final fuels = await repo.getNotificationFuels();
    expect(fuels['unp10kg'], isFalse);
    expect(fuels['es95'], isTrue);
  });
}
