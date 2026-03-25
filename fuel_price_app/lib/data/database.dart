import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AppDatabase {
  Database? _db;
  final bool inMemory;

  AppDatabase({this.inMemory = false});

  Future<Database> get database async {
    _db ??= await init();
    return _db!;
  }

  Future<Database> init() async {
    final path = inMemory ? inMemoryDatabasePath : join(await getDatabasesPath(), 'fuel_prices.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE oil_prices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        cif_med REAL NOT NULL,
        source TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE exchange_rates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        usd_eur REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE fuel_prices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fuel_type TEXT NOT NULL,
        date TEXT NOT NULL,
        price REAL NOT NULL,
        is_prediction INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE fuel_order (
        fuel_type TEXT PRIMARY KEY,
        position INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE fuel_visibility (
        fuel_type TEXT PRIMARY KEY,
        visible INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE notification_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        enabled INTEGER NOT NULL DEFAULT 1,
        day TEXT NOT NULL DEFAULT 'monday',
        hour INTEGER NOT NULL DEFAULT 9
      )
    ''');
    await db.execute('''
      CREATE TABLE notification_fuels (
        fuel_type TEXT PRIMARY KEY,
        enabled INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE config_version (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        version TEXT NOT NULL,
        fetched_at TEXT NOT NULL
      )
    ''');

    // Seed default fuel order and visibility
    for (final (i, ft) in FuelTypeHelper.allNames.indexed) {
      await db.insert('fuel_order', {'fuel_type': ft, 'position': i});
      await db.insert('fuel_visibility', {'fuel_type': ft, 'visible': 1});
      await db.insert('notification_fuels', {'fuel_type': ft, 'enabled': 1});
    }
    await db.insert('notification_settings', {'id': 1, 'enabled': 1, 'day': 'monday', 'hour': 9});
    await _createStationTables(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createStationTables(db);
    }
  }

  Future<void> _createStationTables(Database db) async {
    await db.execute('''
      CREATE TABLE stations (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        updated TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE station_fuels (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        station_id TEXT NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        price REAL NOT NULL,
        FOREIGN KEY (station_id) REFERENCES stations (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE station_fetch_time (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        fetched_at TEXT NOT NULL
      )
    ''');
  }

  Future<List<Map<String, dynamic>>> query(String table, {String? where, List<dynamic>? whereArgs, String? orderBy}) =>
      _db!.query(table, where: where, whereArgs: whereArgs, orderBy: orderBy);

  Future<int> insert(String table, Map<String, dynamic> values) =>
      _db!.insert(table, values);

  Future<int> update(String table, Map<String, dynamic> values, {String? where, List<dynamic>? whereArgs}) =>
      _db!.update(table, values, where: where, whereArgs: whereArgs);

  Future<int> delete(String table, {String? where, List<dynamic>? whereArgs}) =>
      _db!.delete(table, where: where, whereArgs: whereArgs);

  Future<List<Map<String, dynamic>>> rawQuery(String sql, [List<dynamic>? args]) =>
      _db!.rawQuery(sql, args);

  Future<void> close() async => await _db?.close();
}

class FuelTypeHelper {
  static const allNames = ['es95', 'es100', 'eurodizel', 'unp10kg'];
}
