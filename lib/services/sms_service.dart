
import 'package:flutter/foundation.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'parser_service.dart';
import 'db_service.dart';

class SmsService {
  final SmsQuery _query = SmsQuery();
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<void> syncSms() async {
    var permission = await Permission.sms.status;
    if (permission.isDenied) {
      await Permission.sms.request();
    }
    
    if (await Permission.sms.isGranted) {
      final sw = Stopwatch()..start();
      final lastSync = await _db.getLatestTimestamp();
      final bool firstRun = lastSync == null;

      const int safetyLimit = 10000; // hard cap to avoid runaways on odd devices

      // READING is the dominant cost. Offset paging (querySms with a growing
      // `start`) is ~O(n^2) because each call re-skips earlier rows. So on a
      // first run we read the whole inbox in ONE pass; incremental runs read
      // small pages and stop early at lastSync.
      final int readPage = firstRun ? safetyLimit : 200;
      // PROCESSING (parse on a background isolate + batched insert) is done in
      // small chunks so a big single read still feels smooth — each chunk yields
      // a frame, keeping the skeleton shimmer animating.
      const int processChunk = 1000;

      bool isFinished = false;
      int start = 0;
      int totalChecked = 0;
      int totalInserted = 0;
      int readMs = 0, parseMs = 0, insertMs = 0;

      while (!isFinished && totalChecked < safetyLimit) {
        final t = Stopwatch()..start();
        final messages = await _query.querySms(
          kinds: [SmsQueryKind.inbox],
          sort: true, // newest first
          count: readPage,
          start: start,
        );
        readMs += t.elapsedMilliseconds;

        if (messages.isEmpty) break;

        // Collect qualifying raw records (cheap date checks on the main isolate).
        final raws = <Map<String, dynamic>>[];
        for (var msg in messages) {
          if (msg.date == null) continue;

          // Sorted newest-first: once we pass lastSync, everything else is older.
          if (lastSync != null && msg.date!.isBefore(lastSync)) {
            isFinished = true;
            break;
          }
          // Skip messages already imported (at or before lastSync).
          if (lastSync != null && !msg.date!.isAfter(lastSync)) continue;

          raws.add({
            'body': msg.body,
            'address': msg.address,
            'date': msg.date!.millisecondsSinceEpoch,
          });
        }

        // Parse + insert in small chunks (background isolate per chunk), yielding
        // a frame between each so the UI never freezes even on a huge first read.
        for (int i = 0; i < raws.length; i += processChunk) {
          final end =
              (i + processChunk < raws.length) ? i + processChunk : raws.length;
          final sub = raws.sublist(i, end);

          t.reset();
          final txnMaps = await compute(parseSmsBatch, sub);
          parseMs += t.elapsedMilliseconds;

          t.reset();
          await _db.createAllRaw(txnMaps);
          insertMs += t.elapsedMilliseconds;
          totalInserted += txnMaps.length;

          await Future.delayed(Duration.zero); // yield a frame
        }

        start += readPage;
        totalChecked += messages.length;
      }

      sw.stop();
      debugPrint('SMS sync: scanned $totalChecked, inserted $totalInserted in '
          '${sw.elapsedMilliseconds}ms (read ${readMs}ms, parse ${parseMs}ms, '
          'insert ${insertMs}ms)');
    }
  }
}
