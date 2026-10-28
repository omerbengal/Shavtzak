// What FirestoreDatabase.updateEvent sends to the backend's event.update, and
// what an admin gets back when the backend refuses it. The hours the admin
// chose for members with custom hours ride in the same call, and only when
// there are some: an event save that moves nothing looks exactly as it did
// before hours existed.
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/backend_api_service.dart';
import 'package:shavtzak/data/data_sources/firestore_database.dart';
import 'package:shavtzak/domain/entities/custom_hours_resolution.dart';
import 'package:shavtzak/domain/entities/event.dart';

class _FakeBackend extends Fake implements BackendApiService {
  final List<({String operation, Map<String, dynamic>? payload})> calls = [];
  Object? failWith;

  @override
  Future<Map<String, dynamic>> mutate(
    String operation, {
    Map<String, dynamic>? payload,
  }) async {
    calls.add((operation: operation, payload: payload));
    final error = failWith;
    if (error != null) throw error;
    return {'ok': true};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeBackend backend;
  late FirestoreDatabase db;

  final stamp = DateTime(2026, 10, 1);
  final event = Event(
    id: 'e1',
    name: 'כנס חורף',
    startDate: DateTime(2026, 11, 3),
    endDate: DateTime(2026, 11, 4),
    startTime: '19:00',
    endTime: '23:00',
    assemblyTime: '12:00',
    requiresArmed: false,
    roleRequirements: const {'medic': 1},
    createdAt: stamp,
    updatedAt: stamp,
  );

  setUp(() {
    backend = _FakeBackend();
    db = FirestoreDatabase(
      firestore: FakeFirebaseFirestore(),
      backendApiService: backend,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('without resolutions the payload is just the event', () async {
    await db.updateEvent(event);

    expect(backend.calls, hasLength(1));
    expect(backend.calls.single.operation, 'event.update');
    expect(backend.calls.single.payload!.keys, ['event']);
    expect(backend.calls.single.payload!['event']['id'], 'e1');
  });

  test('resolutions ride along, each with both hours keys', () async {
    await db.updateEvent(event, customHoursResolutions: const [
      CustomHoursResolution(
        assignmentId: 'a1',
        customStartAt: '2026-11-03T14:00',
        customEndAt: '2026-11-03T23:00',
      ),
      CustomHoursResolution(
        assignmentId: 'a2',
        customStartAt: null,
        customEndAt: null,
      ),
    ]);

    final payload = backend.calls.single.payload!;
    expect(payload.keys, unorderedEquals(['event', 'customHoursResolutions']));
    expect(payload['customHoursResolutions'], [
      {
        'assignmentId': 'a1',
        'customStartAt': '2026-11-03T14:00',
        'customEndAt': '2026-11-03T23:00',
      },
      {
        'assignmentId': 'a2',
        'customStartAt': null,
        'customEndAt': null,
      },
    ]);
    // An explicit null is what clears the hours: the keys are there.
    expect(
      (payload['customHoursResolutions'] as List).last,
      containsPair('customStartAt', null),
    );
  });

  test('the backend\'s Hebrew refusal survives the wrapping', () async {
    const uncovered =
        'לחלק מהצוות נוספו שעות מותאמות בינתיים — יש לפתוח את האירוע מחדש';
    backend.failWith = const BackendApiException(uncovered, statusCode: 409);

    await expectLater(
      db.updateEvent(event),
      throwsA(
        isA<DatabaseException>()
            .having((e) => e.toString(), 'message', contains(uncovered)),
      ),
    );
  });
}
