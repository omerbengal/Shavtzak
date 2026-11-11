import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/event_items.dart';
import 'package:shavtzak/domain/entities/event_item.dart';

EventItem item(String id, String name, String? emoji, int sortOrder,
        {bool archived = false}) =>
    EventItem(
      id: id,
      name: name,
      emoji: emoji,
      sortOrder: sortOrder,
      isArchived: archived,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  final scan = item('scan', 'סריקה', '🤳🏻', 0);
  final menorah = item('menorah', 'חנוכייה', '🕎', 1);
  final band = item('band', 'להקה', null, 2, archived: true);
  final catalogue = [scan, menorah, band];

  group('labels', () {
    test('an item reads name then emoji, or just the name', () {
      expect(scan.label, 'סריקה 🤳🏻');
      expect(band.label, 'להקה');
      expect(scan.compact, '🤳🏻');
      expect(band.compact, 'להקה');
    });

    test('the picture sentence lists every item', () {
      expect(eventItemsSentence([scan, menorah, band]),
          'באירוע זה יש: סריקה 🤳🏻, חנוכייה 🕎, להקה');
      expect(eventItemsSentence(const []), isNull);
    });

    test('the calendar line uses emoji, and the name where there is none', () {
      expect(eventItemsCompactLine([scan, menorah, band]), '🤳🏻, 🕎, להקה');
      expect(eventItemsCompactLine(const []), isNull);
    });
  });

  group('eventItemsOf', () {
    const choices = [
      EventItemChoice(itemId: 'band', showInEventExport: false),
      EventItemChoice(itemId: 'gone'),
      EventItemChoice(itemId: 'scan', showInCalendarExport: false),
    ];

    test('looks the choices up in catalogue order; archived kept, deleted skipped', () {
      expect(eventItemsOf(choices, catalogue), [scan, band]);
    });

    test('keeps only the choices the filter accepts', () {
      expect(
        eventItemsOf(choices, catalogue, where: (c) => c.showInEventExport),
        [scan],
      );
      expect(
        eventItemsOf(choices, catalogue, where: (c) => c.showInCalendarExport),
        [band],
      );
    });

    test('nothing before the catalogue has loaded', () {
      expect(eventItemsOf(choices, const []), isEmpty);
    });
  });

  group('EventItem json', () {
    test('round-trips and drops entries without id or name', () {
      expect(EventItem.listFromJson([
        band.toJson(),
        scan.toJson(),
        {'id': '', 'name': 'x'},
        {'id': 'y', 'name': '  '},
      ]), [scan, band]);
    });
  });
}
