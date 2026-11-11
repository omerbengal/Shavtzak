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
    test('reads items, an empty emoji counts as none', () {
      final event = EventModel.fromJson({
        ..._baseJson(),
        'items': [
          {'name': 'סריקה', 'emoji': '🤳🏻'},
          {'name': 'להקה', 'emoji': null},
          {'name': 'חנוכייה', 'emoji': ''},
          {'name': '  '},
        ],
      }).toEntity();
      expect(event.items, const [
        EventItem(name: 'סריקה', emoji: '🤳🏻'),
        EventItem(name: 'להקה'),
        EventItem(name: 'חנוכייה'),
      ]);
    });

    test('defaults to empty for events saved before items existed', () {
      expect(EventModel.fromJson(_baseJson()).toEntity().items, isEmpty);
    });

    test('toJson always carries items so a save can clear them', () {
      final entity = EventModel.fromJson(_baseJson())
          .toEntity()
          .copyWith(items: const [EventItem(name: 'סריקה', emoji: '🤳🏻')]);
      expect(EventModel.fromEntity(entity).toJson()['items'], [
        {'name': 'סריקה', 'emoji': '🤳🏻'},
      ]);
      expect(
        EventModel.fromEntity(entity.copyWith(items: const []))
            .toJson()['items'],
        isEmpty,
      );
    });
  });
}
