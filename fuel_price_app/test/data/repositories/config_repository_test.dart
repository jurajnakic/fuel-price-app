import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fuel_price_app/data/database.dart';
import 'package:fuel_price_app/data/repositories/config_repository.dart';
import 'package:fuel_price_app/data/services/remote_config_service.dart';
import 'package:fuel_price_app/models/fuel_params.dart';

class MockRemoteConfigService extends Mock implements RemoteConfigService {}

void main() {
  late AppDatabase db;
  late MockRemoteConfigService mockService;
  late ConfigRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = AppDatabase(inMemory: true);
    await db.init();
    mockService = MockRemoteConfigService();
    repo = ConfigRepository(db, mockService);
  });

  tearDown(() async => await db.close());

  test('syncConfig returns params on first fetch', () async {
    when(() => mockService.fetchParams())
        .thenAnswer((_) async => FuelParams.defaultParams);
    final result = await repo.syncConfig();
    expect(result, isNotNull);
    expect(result!.version, '2025-02-26');
  });

  test('syncConfig returns null when version unchanged', () async {
    when(() => mockService.fetchParams())
        .thenAnswer((_) async => FuelParams.defaultParams);
    await repo.syncConfig(); // first fetch
    final result = await repo.syncConfig(); // same version
    expect(result, isNull);
  });

  test('syncConfig returns null on fetch failure', () async {
    when(() => mockService.fetchParams()).thenAnswer((_) async => null);
    final result = await repo.syncConfig();
    expect(result, isNull);
  });

  test('getLastFetchTime returns null initially', () async {
    final time = await repo.getLastFetchTime();
    expect(time, isNull);
  });

  test('getLastFetchTime returns time after sync', () async {
    when(() => mockService.fetchParams())
        .thenAnswer((_) async => FuelParams.defaultParams);
    await repo.syncConfig();
    final time = await repo.getLastFetchTime();
    expect(time, isNotNull);
  });
}
