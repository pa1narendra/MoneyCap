
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'parser_service.dart';
import 'db_service.dart';

class SmsService {
  final SmsQuery _query = SmsQuery();
  final ParserService _parser = ParserService();
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<void> syncSms() async {
    var permission = await Permission.sms.status;
    if (permission.isDenied) {
      await Permission.sms.request();
    }
    
    if (await Permission.sms.isGranted) {
      final lastSync = await _db.getLatestTimestamp();
      bool isFinished = false;
      int start = 0;
      int batchSize = 200;
      int safetyLimit = 10000; // Stop after 10k messages to prevent infinite loops on weird devices
      int totalChecked = 0;

      while (!isFinished && totalChecked < safetyLimit) {
        List<SmsMessage> messages = await _query.querySms(
          kinds: [SmsQueryKind.inbox],
          sort: true, // sort by date (Newest first)
          count: batchSize,
          start: start,
        );

        if (messages.isEmpty) {
          isFinished = true;
          break;
        }

        for (var msg in messages) {
          if (msg.date == null) continue;

          // incremental sync optimization:
          // If we have a lastSync date, and we reach a message older than that,
          // we can assume we've seen everything else (since it's sorted).
          if (lastSync != null && msg.date!.isBefore(lastSync)) {
             isFinished = true;
             break;
          }
          
          // Even equal timestamps should be checked to be safe, 
          // but avoiding strict duplicates is handled by DB primary key or logic?
          // Actually DB.create doesn't check duplicates unless we query first.
          // But for now, let's just parse.
          if (lastSync != null && !msg.date!.isAfter(lastSync)) {
             continue;
          }

          var txn = _parser.parseSms(msg);
          if (txn != null) {
            await _db.create(txn);
          }
        }
        
        start += batchSize;
        totalChecked += messages.length;
        
        // Small delay to yield UI thread if needed (optional but good for Flutter)
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }
  }
}
