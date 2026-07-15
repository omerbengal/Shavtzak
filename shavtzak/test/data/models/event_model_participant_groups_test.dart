import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/models/event_model.dart';
import 'package:shavtzak/domain/entities/participant_group.dart';

void main() {
  group('EventModel participant groups', () {
    test('reads the participantGroups array when present', () async {
      final model = await _modelFromDoc({
        ..._baseDoc(),
        'participantGroups': [
          {'label': 'בוקר', 'count': 500},
          {'label': null, 'count': 700},
        ],
      });

      expect(model.toEntity().participantGroups, const [
        ParticipantGroup(label: 'בוקר', count: 500),
        ParticipantGroup(count: 700),
      ]);
    });

    test('falls back to the legacy participantCount scalar', () async {
      final model = await _modelFromDoc({
        ..._baseDoc(),
        'participantCount': 500,
      });

      expect(model.toEntity().participantGroups, const [ParticipantGroup(count: 500)]);
    });

    test('the array wins over a stale legacy scalar', () async {
      final model = await _modelFromDoc({
        ..._baseDoc(),
        'participantCount': 500,
        'participantGroups': [
          {'label': null, 'count': 600},
        ],
      });

      expect(model.toEntity().participantGroups, const [ParticipantGroup(count: 600)]);
    });

    test('an empty array does NOT fall back to the scalar', () async {
      final model = await _modelFromDoc({
        ..._baseDoc(),
        'participantCount': 500,
        'participantGroups': <Map<String, dynamic>>[],
      });

      expect(model.toEntity().participantGroups, isEmpty);
    });

    test('is empty when neither field is set', () async {
      final model = await _modelFromDoc(_baseDoc());
      expect(model.toEntity().participantGroups, isEmpty);
    });

    test('malformed entries are dropped, not thrown on', () async {
      final model = await _modelFromDoc({
        ..._baseDoc(),
        'participantGroups': [
          {'label': 'תקין', 'count': 100},
          {'label': 'ללא כמות'},
          {'label': 'שלילי', 'count': -5},
          'not a map',
        ],
      });

      expect(model.toEntity().participantGroups,
          const [ParticipantGroup(label: 'תקין', count: 100)]);
    });

    test('a string count inside the array is dropped, without killing siblings',
        () async {
      final model = await _modelFromDoc({
        ..._baseDoc(),
        'participantGroups': [
          {'label': 'תקין', 'count': 100},
          {'label': 'מחרוזת', 'count': '500'},
          {'label': 'גם תקין', 'count': 200},
        ],
      });

      expect(model.toEntity().participantGroups, const [
        ParticipantGroup(label: 'תקין', count: 100),
        ParticipantGroup(label: 'גם תקין', count: 200),
      ]);
    });

    test('tryFromJson drops NaN and Infinity counts instead of throwing', () {
      expect(
        ParticipantGroupModel.tryFromJson({'count': double.nan, 'label': 'x'}),
        isNull,
      );
      expect(
        ParticipantGroupModel.tryFromJson(
            {'count': double.infinity, 'label': 'x'}),
        isNull,
      );
    });

    test('a non-numeric legacy participantCount coerces to empty, not a throw',
        () async {
      final model = await _modelFromDoc({
        ..._baseDoc(),
        'participantCount': 'oops',
      });

      expect(model.toEntity().participantGroups, isEmpty);
    });

    test(
        'a NaN legacy participantCount coerces to empty via fromJson, not a throw',
        () {
      final model = EventModel.fromJson({
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
        'participantCount': double.nan,
      });

      expect(model.toEntity().participantGroups, isEmpty);
    });

    test('toJson serializes groups and trims labels', () {
      final json = _model(const [
        ParticipantGroup(label: '  בוקר  ', count: 500),
        ParticipantGroup(count: 700),
      ]).toJson();

      expect(json['participantGroups'], [
        {'label': 'בוקר', 'count': 500},
        {'label': null, 'count': 700},
      ]);
    });

    test('toEntity carries the groups through', () {
      expect(
        _model(const [ParticipantGroup(label: 'ערב', count: 700)])
            .toEntity()
            .participantGroups,
        const [ParticipantGroup(label: 'ערב', count: 700)],
      );
    });
  });
}

EventModel _model(List<ParticipantGroup> groups) {
  final now = DateTime(2026, 7, 14);
  return EventModel(
    id: 'event-1',
    name: 'טקס פתיחה',
    startDate: DateTime(2026, 7, 20),
    endDate: DateTime(2026, 7, 20),
    startTime: '18:00',
    endTime: '22:00',
    assemblyTime: '17:00',
    participantGroups:
        groups.map(ParticipantGroupModel.fromEntity).toList(),
    location: '',
    requiresArmed: false,
    roleRequirements: const {},
    createdAt: now,
    updatedAt: now,
  );
}

Map<String, dynamic> _baseDoc() {
  final stamp = Timestamp.fromDate(DateTime.utc(2026, 7, 14));
  return {
    'name': 'טקס פתיחה',
    'startDate': Timestamp.fromDate(DateTime.utc(2026, 7, 20)),
    'endDate': Timestamp.fromDate(DateTime.utc(2026, 7, 20)),
    'startTime': '18:00',
    'endTime': '22:00',
    'assemblyTime': '17:00',
    'requiresArmed': false,
    'roleRequirements': <String, dynamic>{},
    'createdAt': stamp,
    'updatedAt': stamp,
  };
}

Future<EventModel> _modelFromDoc(Map<String, dynamic> data) async {
  final fake = FakeFirebaseFirestore();
  await fake.collection('events').doc('event-1').set(data);
  final doc = await fake.collection('events').doc('event-1').get();
  return EventModel.fromFirestore(doc);
}
