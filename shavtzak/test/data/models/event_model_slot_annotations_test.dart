import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/models/event_model.dart';
import 'package:shavtzak/domain/entities/slot_annotation.dart';

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
  group('EventModel slotAnnotations', () {
    test('reads slotAnnotations from JSON', () {
      final model = EventModel.fromJson({
        ..._baseJson(),
        'slotAnnotations': {
          'entryScreening#0': {'note': 'כניסה B', 'labelId': 'L1'},
          'medic#2': {'note': '', 'labelId': 'L2'},
        },
      });
      expect(model.toEntity().slotAnnotations, {
        'entryScreening#0': const SlotAnnotation(note: 'כניסה B', labelId: 'L1'),
        'medic#2': const SlotAnnotation(labelId: 'L2'),
      });
    });

    test('defaults to empty when absent (legacy docs)', () {
      final model = EventModel.fromJson(_baseJson());
      expect(model.toEntity().slotAnnotations, isEmpty);
    });

    test('toJson round-trips slotAnnotations', () {
      final entity = EventModel.fromJson({
        ..._baseJson(),
        'slotAnnotations': {
          'medic#1': {'note': 'ערב', 'labelId': null},
        },
      }).toEntity();
      final json = EventModel.fromEntity(entity).toJson();
      expect(json['slotAnnotations'], {
        'medic#1': {'note': 'ערב', 'labelId': null},
      });
    });
  });
}
