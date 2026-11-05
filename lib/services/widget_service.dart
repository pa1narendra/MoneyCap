import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'db_service.dart';

/// Pushes this month's totals to the Android home-screen widget
/// (android/app/src/main/kotlin/.../MoneyCapWidgetProvider.kt). Only totals
/// are shared, never merchants or SMS text.
class WidgetService {
  WidgetService._();

  static const _provider = 'com.moneycap.app.MoneyCapWidgetProvider';

  static Future<void> refresh() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final now = DateTime.now();
      final month = DateFormat('yyyy-MM').format(now);
      final rows = await DatabaseHelper.instance.monthRowsAllAccounts(month);
      double spent = 0, income = 0;
      for (final r in rows) {
        if (r['kind'] == 'TRANSFER') continue;
        final a = (r['amount'] as num).toDouble();
        if (r['type'] == 'DEBIT') {
          spent += a;
        } else {
          income += a;
        }
      }
      final fmt = NumberFormat.compactSimpleCurrency(locale: 'en_IN', name: '₹');
      await HomeWidget.saveWidgetData<String>('month', DateFormat('MMMM').format(now));
      await HomeWidget.saveWidgetData<String>('spent', fmt.format(spent));
      await HomeWidget.saveWidgetData<String>('income', fmt.format(income));
      await HomeWidget.saveWidgetData<String>(
          'updated', 'Updated ${DateFormat('d MMM, h:mm a').format(now)}');
      await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
    } catch (e) {
      debugPrint('Widget refresh failed: $e');
    }
  }
}
