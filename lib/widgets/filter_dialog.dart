
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../providers/transaction_provider.dart';

class FilterDialog extends StatefulWidget {
  final TimeFilter initialFilter;
  final Function(TimeFilter, DateTimeRange?) onApply;

  const FilterDialog({super.key, required this.initialFilter, required this.onApply});

  @override
  State<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<FilterDialog> {
  late TimeFilter _selectedFilter;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600, // Fixed width for tablet/desktop feel, or responsive
        height: 450,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Date Range', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))
              ],
            ),
            const Divider(),
            Expanded(
              child: Row(
                children: [
                  // Presets Column
                  SizedBox(
                    width: 140,
                    child: ListView(
                      children: TimeFilter.values.map((filter) {
                        final isSelected = _selectedFilter == filter;
                        return ListTile(
                          title: Text(filter.label),
                          selected: isSelected,
                          selectedTileColor: Colors.blue.withOpacity(0.1),
                          onTap: () {
                              setState(() {
                                  _selectedFilter = filter;
                                  if (filter == TimeFilter.custom) {
                                      _pickCustomRange();
                                  }
                              });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const VerticalDivider(),
                  // Calendar View (Placeholder or actual)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                          if (_selectedFilter == TimeFilter.custom && _customRange != null)
                              Text(
                                  '${DateFormat('MMM d').format(_customRange!.start)} - ${DateFormat('MMM d, y').format(_customRange!.end)}',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              )
                          else
                              Text(_selectedFilter.label, style: const TextStyle(fontSize: 24)),
                          
                          const SizedBox(height: 20),
                          const Icon(Icons.calendar_month, size: 64, color: Colors.grey),
                          const SizedBox(height: 20),
                          if (_selectedFilter == TimeFilter.custom)
                            ElevatedButton(onPressed: _pickCustomRange, child: const Text("Select Range"))
                          else 
                            const Text("Preset selected. Click Apply.")
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context), 
                    child: const Text('Cancel')
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                    onPressed: () {
                        widget.onApply(_selectedFilter, _customRange);
                        Navigator.pop(context);
                    }, 
                    child: const Text('Apply'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
  
  Future<void> _pickCustomRange() async {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
          context: context, 
          firstDate: DateTime(2020), 
          lastDate: now,
          initialDateRange: _customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
      );
      
      if (picked != null) {
          setState(() {
              _customRange = picked;
          });
      }
  }
}
