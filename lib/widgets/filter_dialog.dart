import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../providers/transaction_provider.dart';

class FilterDialog extends StatelessWidget {
  final TimeFilter initialFilter;
  final Function(TimeFilter, DateTimeRange?) onApply;

  const FilterDialog({super.key, required this.initialFilter, required this.onApply});

  static void show(BuildContext context, TimeFilter initialFilter, Function(TimeFilter, DateTimeRange?) onApply) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => FilterDialog(initialFilter: initialFilter, onApply: onApply),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.filter_list, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Filter by Date',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: TimeFilter.values.map((filter) {
              final isSelected = initialFilter == filter;
              final range = _getPresetRange(filter);
              String? subtitle;
              if (range != null) {
                subtitle = '${DateFormat('MMM d').format(range.start)} - ${DateFormat('MMM d, y').format(range.end)}';
              } else if (filter == TimeFilter.all) {
                subtitle = 'Show everything';
              } else if (filter == TimeFilter.custom) {
                subtitle = 'Pick start & end dates';
              }

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                leading: Icon(
                  _getFilterIcon(filter),
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                  size: 22,
                ),
                title: Text(
                  filter.label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? theme.colorScheme.primary : null,
                  ),
                ),
                subtitle: subtitle != null
                    ? Text(subtitle, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant))
                    : null,
                trailing: isSelected
                    ? Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20)
                    : null,
                onTap: () async {
                  if (filter == TimeFilter.custom) {
                    Navigator.pop(context);
                    final now = DateTime.now();
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: now,
                      initialDateRange: DateTimeRange(
                        start: now.subtract(const Duration(days: 7)),
                        end: now,
                      ),
                    );
                    if (picked != null) {
                      onApply(TimeFilter.custom, picked);
                    }
                  } else {
                    onApply(filter, null);
                    Navigator.pop(context);
                  }
                },
              );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFilterIcon(TimeFilter filter) {
    switch (filter) {
      case TimeFilter.all:
        return Icons.all_inclusive;
      case TimeFilter.today:
        return Icons.today;
      case TimeFilter.yesterday:
        return Icons.history;
      case TimeFilter.thisWeek:
      case TimeFilter.lastWeek:
        return Icons.view_week;
      case TimeFilter.thisMonth:
      case TimeFilter.lastMonth:
        return Icons.calendar_month;
      case TimeFilter.thisYear:
      case TimeFilter.lastYear:
        return Icons.calendar_today;
      case TimeFilter.custom:
        return Icons.date_range;
    }
  }

  DateTimeRange? _getPresetRange(TimeFilter filter) {
    if (filter == TimeFilter.all || filter == TimeFilter.custom) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (filter) {
      case TimeFilter.today:
        return DateTimeRange(start: today, end: today);
      case TimeFilter.yesterday:
        final start = today.subtract(const Duration(days: 1));
        return DateTimeRange(start: start, end: start);
      case TimeFilter.thisWeek:
        final start = today.subtract(Duration(days: today.weekday - 1));
        final end = start.add(const Duration(days: 6));
        return DateTimeRange(start: start, end: end);
      case TimeFilter.lastWeek:
        final start = today.subtract(Duration(days: today.weekday - 1 + 7));
        final end = start.add(const Duration(days: 6));
        return DateTimeRange(start: start, end: end);
      case TimeFilter.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0);
        return DateTimeRange(start: start, end: end);
      case TimeFilter.lastMonth:
        final start = DateTime(now.year, now.month - 1, 1);
        final end = DateTime(now.year, now.month, 0);
        return DateTimeRange(start: start, end: end);
      case TimeFilter.thisYear:
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year, 12, 31);
        return DateTimeRange(start: start, end: end);
      case TimeFilter.lastYear:
        final start = DateTime(now.year - 1, 1, 1);
        final end = DateTime(now.year - 1, 12, 31);
        return DateTimeRange(start: start, end: end);
      default:
        return null;
    }
  }
}
