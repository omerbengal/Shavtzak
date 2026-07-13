import 'package:flutter/material.dart';

import '../../core/debug/logger.dart';
import '../../core/utils/date_utils.dart' as app_date_utils;
import '../../domain/entities/event.dart';

/// The mark shown next to a person who is also assigned to a different event on
/// a day this event covers. Tap to see which events.
///
/// Deliberately a DIFFERENT icon from the orange ⚠ that flags a second role in
/// the SAME event: a person can carry both marks at once and they are different
/// problems, so an identical icon would force the user to tap each one to find
/// out what it is telling them.
class SameDayAssignmentMark extends StatelessWidget {
  const SameDayAssignmentMark({
    super.key,
    required this.otherEvents,
    required this.memberName,
    this.size = 20,
  });

  /// Sorted by start date then name — see `sameDayOtherEventsByMember`.
  final List<Event> otherEvents;
  final String memberName;
  final double size;

  static const Color _markColor = Colors.orange;

  @override
  Widget build(BuildContext context) {
    if (otherEvents.isEmpty) return const SizedBox.shrink();

    return Tooltip(
      message: 'משובץ/ת גם ב: ${otherEvents.map(_shortLabel).join(', ')}',
      child: InkWell(
        onTap: () {
          Logger.action('open:sameDayAssignmentDialog', {
            'otherEventCount': otherEvents.length,
          });
          _showOtherEventsDialog(context);
        },
        child: Icon(Icons.event_repeat, color: _markColor, size: size),
      ),
    );
  }

  static String _shortLabel(Event event) =>
      '${event.name} (${event.startDate.day}/${event.startDate.month})';

  void _showOtherEventsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          // otherEvents is unbounded, and a non-scrollable AlertDialog lets its
          // content overflow rather than shrink it (see the AlertDialog docs).
          // On a phone, six events with long Hebrew names — which wrap at that
          // width — overflow by hundreds of pixels.
          scrollable: true,
          title: Row(
            children: const [
              Icon(Icons.event_repeat, color: _markColor),
              SizedBox(width: 8),
              Expanded(child: Text('שיבוץ באירוע נוסף באותו יום')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$memberName משובץ/ת גם באירועים:',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              ...otherEvents.map(
                (event) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '• ${event.name} — '
                    '${app_date_utils.DateUtils.formatDate(event.startDate)}',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Logger.action('tap:close:sameDayAssignmentDialog');
                Navigator.of(dialogContext).pop();
              },
              child: const Text('סגור'),
            ),
          ],
        ),
      ),
    );
  }
}
