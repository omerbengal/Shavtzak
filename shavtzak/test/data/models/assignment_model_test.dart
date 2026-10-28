// AssignmentModel carries an assignment's custom hours through all of its
// conversions: entity, Firestore document and JSON.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/data/models/assignment_model.dart';
import 'package:shavtzak/domain/entities/assignment.dart';

void main() {
  final created = DateTime.utc(2026, 10, 1, 8);
  final updated = DateTime.utc(2026, 10, 2, 9);

  AssignmentModel model({String? start, String? end}) => AssignmentModel(
        id: 'a1',
        eventId: 'e1',
        teamMemberId: 'm1',
        roleType: 'medic',
        slotIndex: 0,
        status: 'confirmed',
        notes: '',
        createdAt: created,
        updatedAt: updated,
        customStartAt: start,
        customEndAt: end,
      );

  Map<String, dynamic> storedMap({Map<String, dynamic> extra = const {}}) => {
        'eventId': 'e1',
        'teamMemberId': 'm1',
        'roleType': 'medic',
        'slotIndex': 0,
        'status': 'confirmed',
        'notes': '',
        'createdAt': Timestamp.fromDate(created),
        'updatedAt': Timestamp.fromDate(updated),
        ...extra,
      };

  group('toJson', () {
    test('without hours still carries both keys, as null', () {
      final json = model().toJson();
      expect(json.containsKey('customStartAt'), isTrue);
      expect(json.containsKey('customEndAt'), isTrue);
      expect(json['customStartAt'], isNull);
      expect(json['customEndAt'], isNull);
    });

    test('with hours carries them', () {
      final json = model(start: '2026-10-27T14:00', end: '2026-10-27T23:00').toJson();
      expect(json['customStartAt'], '2026-10-27T14:00');
      expect(json['customEndAt'], '2026-10-27T23:00');
    });
  });

  group('fromJson', () {
    Map<String, dynamic> json({Map<String, dynamic> extra = const {}}) => {
          'id': 'a1',
          'eventId': 'e1',
          'teamMemberId': 'm1',
          'roleType': 'medic',
          'createdAt': created.toIso8601String(),
          'updatedAt': updated.toIso8601String(),
          ...extra,
        };

    test('a map without the keys gives nulls', () {
      final parsed = AssignmentModel.fromJson(json());
      expect(parsed.customStartAt, isNull);
      expect(parsed.customEndAt, isNull);
    });

    test('valid strings round-trip', () {
      final original = model(start: '2026-10-27T14:00', end: '2026-10-28T02:00');
      final parsed = AssignmentModel.fromJson(original.toJson());
      expect(parsed.customStartAt, '2026-10-27T14:00');
      expect(parsed.customEndAt, '2026-10-28T02:00');
    });

    test('a value that is not a string reads as no hours, never throws', () {
      final parsed = AssignmentModel.fromJson(
        json(extra: {'customStartAt': 5, 'customEndAt': true}),
      );
      expect(parsed.customStartAt, isNull);
      expect(parsed.customEndAt, isNull);
    });
  });

  group('Firestore', () {
    late FakeFirebaseFirestore firestore;

    setUp(() => firestore = FakeFirebaseFirestore());

    Future<AssignmentModel> read(String id) async =>
        AssignmentModel.fromFirestore(
          await firestore.collection('assignments').doc(id).get(),
        );

    test('a document without the keys gives nulls', () async {
      await firestore.collection('assignments').doc('a1').set(storedMap());
      final parsed = await read('a1');
      expect(parsed.customStartAt, isNull);
      expect(parsed.customEndAt, isNull);
    });

    test('a document with null values gives nulls', () async {
      await firestore
          .collection('assignments')
          .doc('a1')
          .set(storedMap(extra: {'customStartAt': null, 'customEndAt': null}));
      final parsed = await read('a1');
      expect(parsed.customStartAt, isNull);
      expect(parsed.customEndAt, isNull);
    });

    test('valid strings round-trip through toFirestore', () async {
      await firestore.collection('assignments').doc('a1').set(
            model(start: '2026-10-27T14:00', end: '2026-10-28T02:00').toFirestore(),
          );
      final parsed = await read('a1');
      expect(parsed.customStartAt, '2026-10-27T14:00');
      expect(parsed.customEndAt, '2026-10-28T02:00');
    });

    test('a value that is not a string reads as no hours, never throws',
        () async {
      await firestore
          .collection('assignments')
          .doc('a1')
          .set(storedMap(extra: {'customStartAt': 5, 'customEndAt': 7}));
      final parsed = await read('a1');
      expect(parsed.customStartAt, isNull);
      expect(parsed.customEndAt, isNull);
    });

    test('toFirestore writes a delete marker for missing hours', () {
      final doc = model().toFirestore();
      expect(doc.containsKey('customStartAt'), isTrue);
      expect(doc.containsKey('customEndAt'), isTrue);
      expect(doc['customStartAt'], FieldValue.delete());
      expect(doc['customEndAt'], FieldValue.delete());
    });

    test('toFirestore writes the strings when there are hours', () {
      final doc =
          model(start: '2026-10-27T14:00', end: '2026-10-27T23:00').toFirestore();
      expect(doc['customStartAt'], '2026-10-27T14:00');
      expect(doc['customEndAt'], '2026-10-27T23:00');
    });
  });

  group('entity conversions', () {
    test('fromEntity and toEntity carry the hours', () {
      final entity = Assignment(
        id: 'a1',
        eventId: 'e1',
        teamMemberId: 'm1',
        roleType: 'medic',
        slotIndex: 0,
        status: AssignmentStatus.confirmed,
        notes: '',
        createdAt: created,
        updatedAt: updated,
        customStartAt: '2026-10-27T14:00',
        customEndAt: '2026-10-27T23:00',
      );
      final roundTripped = AssignmentModel.fromEntity(entity).toEntity();
      expect(roundTripped, entity);
      expect(roundTripped.customStartAt, '2026-10-27T14:00');
      expect(roundTripped.customEndAt, '2026-10-27T23:00');
    });

    test('an entity without hours stays without', () {
      final entity = Assignment(
        id: 'a1',
        eventId: 'e1',
        teamMemberId: 'm1',
        roleType: 'medic',
        slotIndex: 0,
        status: AssignmentStatus.pending,
        notes: '',
        createdAt: created,
        updatedAt: updated,
      );
      final roundTripped = AssignmentModel.fromEntity(entity).toEntity();
      expect(roundTripped.customStartAt, isNull);
      expect(roundTripped.customEndAt, isNull);
    });
  });
}
