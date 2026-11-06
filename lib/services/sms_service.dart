import 'package:flutter/foundation.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'parser_service.dart';
import 'db_service.dart';
import 'demo_data.dart';

enum SyncStatus { ok, noPermission, error }

class SyncResult {
  final SyncStatus status;
  final int inserted;
  final int scanned;
  const SyncResult(this.status, {this.inserted = 0, this.scanned = 0});
}

/// Imports bank SMS from the inbox.
///
/// Progress is tracked by a WATERMARK: the date of the newest SMS ever
/// scanned (stored in prefs), not the newest saved row. Deleting a row can
/// therefore never rewind the scan and re-import it, and non-transaction
/// SMS aren't re-scanned on every sync.
///
/// Never prompts for permission (the onboarding screen does that, with a
/// disclosure first), so it's safe to call from a background task.
class SmsService {
  static const _kWatermark = 'sms_watermark_ms';
  static const _kPendingRescan = 'pending_rescan_v5';
  static const _kRescanConfirmed = 'rescan_confirmed_v5';
  static const _safetyLimit = 20000;
  static const _processChunk = 1000;

  final SmsQuery _query = SmsQuery();
  final DatabaseHelper _db = DatabaseHelper.instance;

  static Future<SyncResult>? _running;

  /// Concurrent callers (startup auto-sync + pull-to-refresh) share one run.
  Future<SyncResult> syncSms({void Function(double progress)? onProgress}) {
    return _running ??= _sync(onProgress).whenComplete(() => _running = null);
  }

  /// False (never throws) when the permission can't be checked, e.g. in a
  /// background isolate without the plugin or on a non-Android platform.
  static Future<bool> hasPermission() async {
    if (kDemoMode) return true;
    try {
      return await Permission.sms.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Forget the watermark so the next sync re-reads the whole inbox (after a
  /// reset). Deleted rows stay deleted (their keys are remembered).
  static Future<void> clearWatermark() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kWatermark);
  }

  /// True when an upgrade needs SMS rows rebuilt and the user hasn't been told.
  static Future<bool> isRescanPending() async {
    await DatabaseHelper.instance.database; // migrations set needsRescan
    final prefs = await SharedPreferences.getInstance();
    if (DatabaseHelper.needsRescan) {
      DatabaseHelper.needsRescan = false;
      await prefs.setBool(_kPendingRescan, true);
    }
    return (prefs.getBool(_kPendingRescan) ?? false) &&
        !(prefs.getBool(_kRescanConfirmed) ?? false);
  }

  static Future<void> confirmRescan() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRescanConfirmed, true);
  }

  /// Screenshot build: fake SMS through the real parser and duplicate check.
  /// The real inbox is never touched.
  Future<SyncResult> _demoSync(void Function(double)? onProgress) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('demo_seeded') ?? false) return const SyncResult(SyncStatus.ok);
    final now = DateTime.now();
    final raws = DemoData.sms(now);
    for (var p = 0.2; p < 1; p += 0.2) {
      onProgress?.call(p);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    final ids = await _db.createAllRaw(parseSmsBatch(raws));
    final hidden = await _db.resolveDuplicates(ids);
    await _db.applySelfRules(ids);
    await _db.pairTransfers(ids);
    await DemoData.seedExtras(now);
    await prefs.setBool('demo_seeded', true);
    onProgress?.call(1);
    return SyncResult(SyncStatus.ok, inserted: ids.length - hidden, scanned: raws.length);
  }

  Future<SyncResult> _sync(void Function(double)? onProgress) async {
    if (kDemoMode) return _demoSync(onProgress);
    try {
      final prefs = await SharedPreferences.getInstance();
      // The background isolate may have advanced the watermark; don't trust
      // this isolate's cached copy.
      await prefs.reload();
      await _db.database; // runs migrations; may request a rescan
      if (DatabaseHelper.needsRescan) {
        // Persist first, so the request survives even if SMS access is off now.
        DatabaseHelper.needsRescan = false;
        await prefs.setBool(_kPendingRescan, true);
      }
      if (!await hasPermission()) return const SyncResult(SyncStatus.noPermission);
      if (prefs.getBool(_kPendingRescan) ?? false) {
        // Clearing rows waits until the user has seen the backup reminder (a
        // background sync can arrive first).
        if (!(prefs.getBool(_kRescanConfirmed) ?? false)) {
          return const SyncResult(SyncStatus.ok);
        }
        // Rows from the old parser are unreliable: re-import from the inbox.
        await _db.deleteSmsTransactions();
        await prefs.remove(_kWatermark);
      }

      final wmMs = prefs.getInt(_kWatermark);
      final watermark = wmMs == null ? null : DateTime.fromMillisecondsSinceEpoch(wmMs);
      final sw = Stopwatch()..start();

      // A first run reads the whole inbox in ONE query (offset paging is
      // O(n^2)); incremental runs read small pages and stop at the watermark.
      final readPage = watermark == null ? _safetyLimit : 200;
      var start = 0, scanned = 0, inserted = 0;
      DateTime? newest;
      var done = false;
      final newIds = <int>[];

      while (!done && scanned < _safetyLimit) {
        final messages = await _query.querySms(
            kinds: [SmsQueryKind.inbox], sort: true, count: readPage, start: start);
        if (messages.isEmpty) break;

        final raws = <Map<String, dynamic>>[];
        for (final msg in messages) {
          final d = msg.date;
          if (d == null) continue;
          if (watermark != null && !d.isAfter(watermark)) {
            done = true; // sorted newest first: the rest is older
            break;
          }
          if (newest == null || d.isAfter(newest)) newest = d;
          raws.add({'body': msg.body, 'address': msg.address, 'date': d.millisecondsSinceEpoch});
        }

        for (var i = 0; i < raws.length; i += _processChunk) {
          final sub = raws.sublist(i, (i + _processChunk).clamp(0, raws.length));
          final maps = await compute(parseSmsBatch, sub);
          final ids = await _db.createAllRaw(maps);
          newIds.addAll(ids);
          inserted += ids.length;
          onProgress?.call(((i + sub.length) / raws.length).clamp(0.0, 1.0));
          await Future<void>.delayed(Duration.zero); // let a frame through
        }
        start += readPage;
        scanned += messages.length;
      }

      // "inserted" is what the user sees: repeats of a payment don't count.
      inserted -= await _db.resolveDuplicates(newIds);
      await _db.applySelfRules(newIds);
      await _db.pairTransfers(newIds);
      if (prefs.getBool(_kPendingRescan) ?? false) await _db.relinkOldAccountLabels();
      if (newest != null) await prefs.setInt(_kWatermark, newest.millisecondsSinceEpoch);
      await prefs.remove(_kPendingRescan);
      await prefs.remove(_kRescanConfirmed);
      onProgress?.call(1);
      debugPrint('SMS sync: scanned $scanned, inserted $inserted in ${sw.elapsedMilliseconds}ms');
      return SyncResult(SyncStatus.ok, inserted: inserted, scanned: scanned);
    } catch (e, st) {
      debugPrint('SMS sync failed: $e\n$st');
      return const SyncResult(SyncStatus.error);
    }
  }
}
