import 'database.dart';

/// Persistent on-device logger. Writes to `app_log` table in the same SQLite DB,
/// so logs survive restart/reboot and can be pulled via adb for later analysis.
///
/// Keeps the last [_maxRows] rows; prunes in-place on write so storage stays bounded.
class AppLogger {
  final AppDatabase db;
  static const int _maxRows = 2000;

  AppLogger(this.db);

  Future<void> log(String tag, String message) async {
    final ts = DateTime.now().toIso8601String();
    try {
      await db.insert('app_log', {
        'timestamp': ts,
        'tag': tag,
        'message': message,
      });
      await _prune();
    } catch (_) {
      // Logging must never break the app
    }
  }

  Future<void> _prune() async {
    final rows = await db.rawQuery('SELECT COUNT(*) as n FROM app_log');
    final n = (rows.first['n'] as int?) ?? 0;
    if (n > _maxRows) {
      await db.rawQuery(
          'DELETE FROM app_log WHERE id IN (SELECT id FROM app_log ORDER BY id ASC LIMIT ?)',
          [n - _maxRows]);
    }
  }
}
