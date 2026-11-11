import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/event_items.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/event_item.dart';

Event _event(String id, DateTime updatedAt, List<EventItem> items) => Event(
      id: id,
      name: id,
      startDate: DateTime(2026, 12, 10),
      endDate: DateTime(2026, 12, 10),
      startTime: '',
      endTime: '',
      assemblyTime: '',
      requiresArmed: false,
      roleRequirements: const {},
      createdAt: DateTime(2026, 1, 1),
      updatedAt: updatedAt,
      items: items,
    );

void main() {
  const scan = EventItem(name: 'סריקה', emoji: '🤳🏻');
  const menorah = EventItem(name: 'חנוכייה', emoji: '🕎');
  const band = EventItem(name: 'להקה');

  group('labels', () {
    test('an item reads name then emoji, or just the name', () {
      expect(scan.label, 'סריקה 🤳🏻');
      expect(band.label, 'להקה');
      expect(scan.compact, '🤳🏻');
      expect(band.compact, 'להקה');
    });

    test('the picture sentence lists every item', () {
      expect(eventItemsSentence(const [scan, menorah, band]),
          'באירוע זה יש: סריקה 🤳🏻, חנוכייה 🕎, להקה');
      expect(eventItemsSentence(const []), isNull);
    });

    test('the calendar line uses emoji, and the name where there is none', () {
      expect(eventItemsCompactLine(const [scan, menorah, band]),
          '🤳🏻, 🕎, להקה');
      expect(eventItemsCompactLine(const []), isNull);
    });
  });

  group('suggestEventItems', () {
    final events = [
      _event('old', DateTime(2026, 1, 1), const [scan, menorah]),
      _event('new', DateTime(2026, 6, 1),
          const [EventItem(name: 'סריקה', emoji: '📱'), band]),
      _event('newest-no-emoji', DateTime(2026, 3, 1),
          const [EventItem(name: 'מסך לד')]),
    ];

    test('matches part of a name and takes the emoji of the latest event', () {
      expect(suggestEventItems('סר', events, const []),
          const [EventItem(name: 'סריקה', emoji: '📱')]);
    });

    test('items already on the event are not offered again', () {
      expect(suggestEventItems('', events, const [band, scan]),
          const [menorah, EventItem(name: 'מסך לד')]);
    });

    test('a blank query lists everything, sorted by name', () {
      expect(
        suggestEventItems('  ', events, const []).map((i) => i.name),
        ['חנוכייה', 'להקה', 'מסך לד', 'סריקה'],
      );
    });
  });
}
