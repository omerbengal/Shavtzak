import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/data/repositories/event_repository.dart';
import 'package:shavtzak/data/repositories/assignment_repository.dart';
import 'package:shavtzak/domain/entities/slot_annotation.dart';
import 'package:shavtzak/presentation/bloc/event/event_bloc.dart';
import 'package:shavtzak/presentation/bloc/event/event_event.dart';

import 'event_bloc_slot_annotation_test.mocks.dart';

@GenerateMocks([EventRepository, AssignmentRepository])
void main() {
  late MockEventRepository eventRepo;
  late MockAssignmentRepository assignmentRepo;

  setUp(() {
    eventRepo = MockEventRepository();
    assignmentRepo = MockAssignmentRepository();
    when(eventRepo.watchEvents()).thenAnswer((_) => const Stream.empty());
    when(eventRepo.watchEventCalendarSyncStates())
        .thenAnswer((_) => const Stream.empty());
    when(eventRepo.updateSlotAnnotation(any, any, any,
            staleKey: anyNamed('staleKey')))
        .thenAnswer((_) async {});
  });

  blocTest<EventBloc, dynamic>(
    'UpsertSlotAnnotation with content upserts a SlotAnnotation at the key',
    build: () => EventBloc(eventRepo, assignmentRepo),
    act: (bloc) => bloc.add(const UpsertSlotAnnotation(
      eventId: 'e1', roleKey: 'medic', slotIndex: 2,
      note: 'C', labelId: 'L2',
    )),
    verify: (_) {
      verify(eventRepo.updateSlotAnnotation(
        'e1', 'medic#2', const SlotAnnotation(note: 'C', labelId: 'L2'),
        staleKey: null)).called(1);
    },
  );

  blocTest<EventBloc, dynamic>(
    'UpsertSlotAnnotation with blank note + null label clears (null value)',
    build: () => EventBloc(eventRepo, assignmentRepo),
    act: (bloc) => bloc.add(const UpsertSlotAnnotation(
      eventId: 'e1', roleKey: 'medic', slotIndex: 2,
      note: '   ', labelId: null, staleKey: 'medic#3',
    )),
    verify: (_) {
      verify(eventRepo.updateSlotAnnotation('e1', 'medic#2', null,
          staleKey: 'medic#3')).called(1);
    },
  );
}
