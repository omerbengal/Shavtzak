import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/models/stage_model.dart';
import 'package:shavtzak/domain/entities/stage.dart';

import '../../support/task_fixtures.dart';

void main() {
  final createdAt = DateTime(2026, 10, 1, 9);
  final updatedAt = DateTime(2026, 10, 5, 12, 30);

  Map<String, dynamic> fullMap() => {
        'eventId': 'e1',
        'title': 'קליטה ורישום',
        'date': '2026-10-21',
        'startTime': '08:00',
        'endTime': '10:45',
        'requirements': 'שני שולחנות',
        'hotelLocation': 'לובי',
        'notes': 'להגיע מוקדם',
        'contacts': [
          {'id': 'c1', 'name': 'אבי', 'phone': '050-1234567', 'role': 'מנהל'},
        ],
        'createdAt': Timestamp.fromDate(createdAt),
        'createdById': 'm-admin',
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  group('StageModel.fromMap', () {
    test('reads every stored field, the date as a local day', () {
      final stage = StageModel.fromMap('s1', fullMap());

      expect(stage.id, 's1');
      expect(stage.eventId, 'e1');
      expect(stage.title, 'קליטה ורישום');
      expect(stage.date, DateTime(2026, 10, 21));
      expect(stage.startTime, '08:00');
      expect(stage.endTime, '10:45');
      expect(stage.requirements, 'שני שולחנות');
      expect(stage.hotelLocation, 'לובי');
      expect(stage.notes, 'להגיע מוקדם');
      expect(stage.contacts, const [
        StageContact(id: 'c1', name: 'אבי', phone: '050-1234567', role: 'מנהל'),
      ]);
      expect(stage.createdAt, createdAt);
      expect(stage.createdById, 'm-admin');
      expect(stage.updatedAt, updatedAt);
    });

    test('tolerates missing and malformed fields', () {
      final stage = StageModel.fromMap('s1', {
        'title': 7,
        'date': 'not a date',
        'contacts': [
          'junk',
          {'name': 'no id'},
          {'id': 'c1', 'name': 'דנה'},
        ],
      });

      expect(stage.eventId, '');
      expect(stage.title, '');
      expect(stage.date, DateTime(1970));
      expect(stage.startTime, isNull);
      expect(stage.requirements, '');
      expect(stage.contacts, const [StageContact(id: 'c1', name: 'דנה')]);
    });
  });

  group('StageModel.toMutationPayload', () {
    test('sends the editable fields, the date as yyyy-MM-dd', () {
      final payload = StageModel.toMutationPayload(buildStage(
        id: 's1',
        eventId: 'e1',
        title: 'קליטה',
        date: DateTime(2026, 10, 2),
        startTime: '08:00',
        endTime: '09:00',
        requirements: 'שולחן',
        hotelLocation: 'לובי',
        notes: 'הערה',
        contacts: const [StageContact(id: 'c1', name: 'אבי', phone: '050')],
      ));

      expect(payload, {
        'id': 's1',
        'eventId': 'e1',
        'title': 'קליטה',
        'date': '2026-10-02',
        'startTime': '08:00',
        'endTime': '09:00',
        'requirements': 'שולחן',
        'hotelLocation': 'לובי',
        'notes': 'הערה',
        'contacts': [
          {'id': 'c1', 'name': 'אבי', 'phone': '050', 'role': ''},
        ],
      });
    });

    test('no time is sent as null', () {
      final payload = StageModel.toMutationPayload(buildStage());
      expect(payload['startTime'], isNull);
      expect(payload['endTime'], isNull);
    });
  });
}
