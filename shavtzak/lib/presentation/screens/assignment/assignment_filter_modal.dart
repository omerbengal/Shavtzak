import 'package:flutter/material.dart';
import '../../../domain/entities/event.dart';

/// Modal for filtering assignments by events
class AssignmentFilterModal extends StatefulWidget {
  final List<Event> availableEvents;
  final Set<String> selectedEventIds;

  const AssignmentFilterModal({
    super.key,
    required this.availableEvents,
    required this.selectedEventIds,
  });

  @override
  State<AssignmentFilterModal> createState() => _AssignmentFilterModalState();
}

class _AssignmentFilterModalState extends State<AssignmentFilterModal> {
  late Set<String> _selectedEventIds;
  bool _eventsExpanded = false;

  @override
  void initState() {
    super.initState();
    _selectedEventIds = Set.from(widget.selectedEventIds);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.filter_list, color: Colors.blue),
                    const SizedBox(width: 12),
                    const Text(
                      'סינון שיבוצים',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: 'סגור',
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Events section with dropdown arrow
                      InkWell(
                        onTap: () {
                          setState(() {
                            _eventsExpanded = !_eventsExpanded;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _eventsExpanded
                                    ? Icons.arrow_drop_down
                                    : Icons.arrow_left,
                                size: 28,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'אירועים',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              if (_selectedEventIds.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_selectedEventIds.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Events list
                      if (_eventsExpanded) ...[
                        const SizedBox(height: 12),
                        if (widget.availableEvents.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(
                              child: Text(
                                'אין אירועים זמינים לסינון',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          )
                        else
                          ...widget.availableEvents.map((event) {
                            final isSelected =
                                _selectedEventIds.contains(event.id);
                            return CheckboxListTile(
                              value: isSelected,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedEventIds.add(event.id);
                                  } else {
                                    _selectedEventIds.remove(event.id);
                                  }
                                });
                              },
                              title: Text(
                                event.name,
                                style: const TextStyle(fontSize: 14),
                              ),
                              subtitle: Text(
                                _formatEventDate(event),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 0),
                              dense: true,
                            );
                          }),
                      ],
                    ],
                  ),
                ),
              ),

              // Footer with buttons
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Clear button (left side)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedEventIds.clear();
                        });
                      },
                      child: const Text(
                        'ניקוי',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.red,
                        ),
                      ),
                    ),
                    // Cancel and Apply buttons (right side)
                    Row(
                      children: [
                        // Cancel button
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'ביטול',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Apply button
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop(_selectedEventIds);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                          child: const Text(
                            'החל',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatEventDate(Event event) {
    final startDate =
        '${event.startDate.day.toString().padLeft(2, '0')}/${event.startDate.month.toString().padLeft(2, '0')}';
    if (_isSameDay(event.startDate, event.endDate)) {
      return startDate;
    } else {
      final endDate =
          '${event.endDate.day.toString().padLeft(2, '0')}/${event.endDate.month.toString().padLeft(2, '0')}';
      return '$startDate - $endDate';
    }
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}
