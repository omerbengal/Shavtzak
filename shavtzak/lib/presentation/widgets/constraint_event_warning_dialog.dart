import 'package:flutter/material.dart';
import '../../core/utils/time_range_utils.dart';
import '../../core/utils/constraint_event_overlap.dart';

class ConstraintEventWarningDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;
  final List<EventOverlapInfo> overlaps;
  final bool showMissingTimeNote;

  const ConstraintEventWarningDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmText,
    required this.overlaps,
    this.showMissingTimeNote = false,
  });

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
    required List<EventOverlapInfo> overlaps,
    bool showMissingTimeNote = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ConstraintEventWarningDialog(
        title: title,
        message: message,
        confirmText: confirmText,
        overlaps: overlaps,
        showMissingTimeNote: showMissingTimeNote,
      ),
    );

    return result ?? false;
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatDateRange(DateTime start, DateTime end) {
    final sameDay = start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;

    if (sameDay) {
      return _formatDate(start);
    }

    return '${_formatDate(start)} - ${_formatDate(end)}';
  }

  String _formatEventTime(EventOverlapInfo overlap) {
    final event = overlap.event;
    final hasValidTime =
        TimeRangeUtils.parseTimeToMinutes(event.startTime) != null &&
            TimeRangeUtils.parseTimeToMinutes(event.endTime) != null;

    if (!hasValidTime) {
      return 'שעת האירוע לא מוגדרת';
    }

    return '${event.startTime} - ${event.endTime}';
  }

  String _formatLocation(String rawLocation) {
    final trimmed = rawLocation.trim();
    if (trimmed.isEmpty) {
      return 'מיקום לא הוגדר';
    }

    final parts = trimmed.split('||');
    final display = parts.first.trim();
    return display.isEmpty ? 'מיקום לא הוגדר' : display;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Column(
                        children: overlaps.map((overlap) {
                          final event = overlap.event;
                          final locationText = _formatLocation(event.location);

                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                    'תאריך: ${_formatDateRange(event.startDate, event.endDate)}'),
                                Text('שעה: ${_formatEventTime(overlap)}'),
                                Text('מיקום: $locationText'),
                                if (showMissingTimeNote &&
                                    overlap.eventHasMissingTime)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Text(
                                      'שעת האירוע לא הוגדרה, זו אזהרה כללית.',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }
}
