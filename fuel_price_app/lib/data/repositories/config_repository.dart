import '../database.dart';
import '../services/remote_config_service.dart';
import '../../models/fuel_params.dart';

class ConfigRepository {
  final AppDatabase db;
  final RemoteConfigService remoteService;

  ConfigRepository(this.db, this.remoteService);

  /// Fetch remote config. Returns new params if version changed, null otherwise.
  Future<FuelParams?> syncConfig() async {
    final remote = await remoteService.fetchParams();
    if (remote == null) return null;

    final current = await _getStoredVersion();
    if (current == remote.version) return null;

    await _storeVersion(remote.version);
    return remote;
  }

  Future<String?> _getStoredVersion() async {
    final rows = await db.query('config_version');
    if (rows.isEmpty) return null;
    return rows.first['version'] as String;
  }

  Future<void> _storeVersion(String version) async {
    final existing = await db.query('config_version');
    final now = DateTime.now().toIso8601String();
    if (existing.isEmpty) {
      await db.insert('config_version', {'id': 1, 'version': version, 'fetched_at': now});
    } else {
      await db.update('config_version', {'version': version, 'fetched_at': now}, where: 'id = 1');
    }
  }

  Future<DateTime?> getLastFetchTime() async {
    final rows = await db.query('config_version');
    if (rows.isEmpty) return null;
    return DateTime.parse(rows.first['fetched_at'] as String);
  }
}
