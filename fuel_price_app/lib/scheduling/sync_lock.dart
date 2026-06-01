import 'package:shared_preferences/shared_preferences.dart';

/// Cross-isolate single-flight lock for sync operations.
///
/// Stored in SharedPreferences as `sync_lock_until_ms` (unix ms epoch). A lock
/// is considered held when `now < until`. TTL exists so a crashed holder
/// eventually releases automatically.
///
/// NB: SharedPreferences read/write is not atomic across isolates, so a small
/// TOCTOU window remains. Acceptable for our case — the goal is to prevent
/// the gross flooding pattern (3× simultaneous bg_sync starts), not to
/// guarantee strict serialization.
class SyncLock {
  static const _key = 'sync_lock_until_ms';
  static const _defaultTtl = Duration(minutes: 5);

  /// Try to acquire the lock with [ttl] expiry. Returns true on success.
  static Future<bool> tryAcquire({Duration ttl = _defaultTtl}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final now = DateTime.now().millisecondsSinceEpoch;
    final until = prefs.getInt(_key) ?? 0;
    if (until > now) return false;
    return prefs.setInt(_key, now + ttl.inMilliseconds);
  }

  /// Release the lock. Safe to call even if not held.
  static Future<void> release() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, 0);
  }

  /// For tests / diagnostics: how long until the current lock expires.
  static Future<Duration> remainingTtl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final until = prefs.getInt(_key) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: (until - now).clamp(0, 1 << 30));
  }
}
