import '../database.dart';

class SettingsRepository {
  final AppDatabase db;

  SettingsRepository(this.db);

  // --- Fuel Order ---

  Future<List<String>> getFuelOrder() async {
    final rows = await db.query('fuel_order', orderBy: 'position ASC');
    return rows.map((r) => r['fuel_type'] as String).toList();
  }

  Future<void> saveFuelOrder(List<String> order) async {
    for (var i = 0; i < order.length; i++) {
      await db.update('fuel_order', {'position': i},
          where: 'fuel_type = ?', whereArgs: [order[i]]);
    }
  }

  // --- Fuel Visibility ---

  Future<Map<String, bool>> getFuelVisibility() async {
    final rows = await db.query('fuel_visibility');
    return {for (final r in rows) r['fuel_type'] as String: (r['visible'] as int) == 1};
  }

  Future<void> setFuelVisibility(String fuelType, bool visible) async {
    await db.update('fuel_visibility', {'visible': visible ? 1 : 0},
        where: 'fuel_type = ?', whereArgs: [fuelType]);
  }

  // --- Notification Settings ---

  Future<Map<String, dynamic>> getNotificationSettings() async {
    final rows = await db.query('notification_settings');
    if (rows.isEmpty) return {'id': 1, 'enabled': 1, 'day': 'monday', 'hour': 9};
    return rows.first;
  }

  Future<void> saveNotificationSettings({String? day, int? hour, bool? enabled}) async {
    final values = <String, dynamic>{};
    if (day != null) values['day'] = day;
    if (hour != null) values['hour'] = hour;
    if (enabled != null) values['enabled'] = enabled ? 1 : 0;
    if (values.isNotEmpty) {
      await db.update('notification_settings', values, where: 'id = 1');
    }
  }

  // --- Notification Fuels ---

  Future<Map<String, bool>> getNotificationFuels() async {
    final rows = await db.query('notification_fuels');
    return {for (final r in rows) r['fuel_type'] as String: (r['enabled'] as int) == 1};
  }

  Future<void> setNotificationFuel(String fuelType, bool enabled) async {
    await db.update('notification_fuels', {'enabled': enabled ? 1 : 0},
        where: 'fuel_type = ?', whereArgs: [fuelType]);
  }
}
