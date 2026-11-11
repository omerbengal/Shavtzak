import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/models/event_model.dart';
import 'package:shavtzak/domain/entities/event_item.dart';

Map<String, dynamic> _baseJson() => {
      'id': 'event-1',
      'name': 'טקס פתיחה',
      'startDate': '2026-07-20',
      'endDate': '2026-07-20',
      'startTime': '18:00',
      'endTime': '22:00',
      'assemblyTime': '17:00',
      'requiresArmed': false,
      'roleRequirements': <String, dynamic>{},
      'createdAt': DateTime.utc(2026, 7, 14).toIso8601String(),
      'updatedAt': DateTime.utc(2026, 7, 14).toIso8601String(),
    };

void main() {
  group('EventModel items', () {
    test('reads item choices; a missing switch is on, id-less entries dropped', () {
      final event = EventModel.fromJson({
        ..._baseJson(),
        'items': [
          {'itemId': 'scan', 'showInEventExport': true, 'showInCalendarExport': false},
          {'itemId': 'band'},
          {'name': 'סריקה', 'emoji': '🤳🏻'},
        ],
      }).toEntity();
      expect(event.items, const [
        EventItemChoice(itemId: 'scan', showInCalendarExport: false),
        EventItemChoice(itemId: 'band'),
      ]);
    });

    test('defaults to empty for events saved before items existed', () {
      expect(EventModel.fromJson(_baseJson()).toEntity().items, isEmpty);
    });

    test('toJson always carries items so a save can clear them', () {
      final entity = EventModel.fromJson(_baseJson())
          .toEntity()
          .copyWith(items: const [
        EventItemChoice(itemId: 'scan', showInEventExport: false),
      ]);
      expect(EventModel.fromEntity(entity).toJson()['items'], [
        {'itemId': 'scan', 'showInEventExport': false, 'showInCalendarExport': true},
      ]);
      expect(
        EventModel.fromEntity(entity.copyWith(items: const []))
            .toJson()['items'],
        isEmpty,
      );
    });
  });
}
