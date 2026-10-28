// EventFormModal in duplication mode: the "שכפל שעות מותאמות" sub-switch under
// "שכפל גם את השיבוצים". It is offered only while assignments are being
// copied and the event being duplicated has an assignment with custom hours,
// which the form reads from the first value of that event's assignments
// stream. Whatever goes wrong with that read leaves the switch hidden, so the
// duplication behaves as it does without custom hours.
//
// The conflict dialog's answer travels back to the bloc as a
// ConfirmDuplicationWithExclusions: whether hours were asked for, and which
// assignments the admin unticked. (The other half, the form's own request,
// needs the date picker and is not exercised here.)
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/constants/role_types.dart';
import 'package:shavtzak/data/repositories/assignment_label_repository.dart';
import 'package:shavtzak/data/repositories/assignment_repository.dart';
import 'package:shavtzak/data/repositories/event_repository.dart';
import 'package:shavtzak/domain/entities/assignment.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';
import 'package:shavtzak/presentation/bloc/category/category_bloc.dart';
import 'package:shavtzak/presentation/bloc/category/category_event.dart';
import 'package:shavtzak/presentation/bloc/category/category_state.dart';
import 'package:shavtzak/presentation/bloc/event/duplication_availability.dart';
import 'package:shavtzak/presentation/bloc/event/event_bloc.dart';
import 'package:shavtzak/presentation/bloc/event/event_event.dart';
import 'package:shavtzak/presentation/bloc/event/event_state.dart';
import 'package:shavtzak/presentation/bloc/role/role_bloc.dart';
import 'package:shavtzak/presentation/bloc/role/role_event.dart';
import 'package:shavtzak/presentation/bloc/role/role_state.dart';
import 'package:shavtzak/presentation/screens/event/widgets/duplication_conflict_resolution_dialog.dart';
import 'package:shavtzak/presentation/screens/event/widgets/event_form_modal.dart';

// The generated mocks of the subscription test already hold MockEventRepository
// and MockAssignmentRepository; reuse them rather than generating a second copy.
import '../../../bloc/event_bloc_subscription_test.mocks.dart';

class _MockAssignmentBloc extends MockBloc<AssignmentEvent, AssignmentState>
    implements AssignmentBloc {}

class _MockLabelRepository extends Mock implements AssignmentLabelRepository {}

class _MockCategoryBloc extends MockBloc<CategoryEvent, CategoryState>
    implements CategoryBloc {}

class _MockRoleBloc extends MockBloc<RoleEvent, RoleState>
    implements RoleBloc {}

/// An EventBloc that only records what the form sends it.
class _RecordingEventBloc extends MockBloc<EventEvent, EventState>
    implements EventBloc {
  final added = <EventEvent>[];

  @override
  void add(EventEvent event) => added.add(event);
}

void main() {
  final stamp = DateTime(2026, 10, 1);

  final source = Event(
    id: 'e1',
    name: 'כנס חורף',
    startDate: DateTime(2026, 12, 1),
    endDate: DateTime(2026, 12, 1),
    startTime: '19:00',
    endTime: '23:00',
    assemblyTime: '18:00',
    location: 'אולמי ורסאי',
    requiresArmed: false,
    roleRequirements: const {'medic': 2},
    createdAt: stamp,
    updatedAt: stamp,
  );

  Assignment assignment(String id, {String? start, String? end}) => Assignment(
        id: id,
        eventId: 'e1',
        teamMemberId: 'm1',
        roleType: 'medic',
        slotIndex: 0,
        status: AssignmentStatus.confirmed,
        notes: '',
        customStartAt: start,
        customEndAt: end,
        createdAt: stamp,
        updatedAt: stamp,
      );

  Future<void> pumpForm(
    WidgetTester tester, {
    required Stream<List<Assignment>> assignments,
    EventBloc? bloc,
    VoidCallback? onSuccess,
  }) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The form's white panel is a DecoratedBox above a ListTile, which trips
    // ListTile's debug-only "ink may be invisible" assertion. It is the form's
    // own and has nothing to do with these tests; every other error still fails.
    final reportError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('ListTile background color')) {
        return;
      }
      reportError?.call(details);
    };
    addTearDown(() => FlutterError.onError = reportError);

    final eventRepository = MockEventRepository();
    final assignmentRepository = MockAssignmentRepository();
    when(assignmentRepository.watchAssignmentsByEvent('e1'))
        .thenAnswer((_) => assignments);

    final eventBloc = bloc ?? EventBloc(eventRepository, assignmentRepository);
    if (bloc == null) addTearDown(eventBloc.close);
    final categoryBloc = _MockCategoryBloc();
    whenListen(categoryBloc, const Stream<CategoryState>.empty(),
        initialState: const CategoryInitial());
    final roleBloc = _MockRoleBloc();
    whenListen(roleBloc, const Stream<RoleState>.empty(),
        initialState: const RoleInitial());
    final assignmentBloc = _MockAssignmentBloc();
    whenListen(assignmentBloc, const Stream<AssignmentState>.empty(),
        initialState: const AssignmentInitial());

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AssignmentRepository>.value(
              value: assignmentRepository),
          RepositoryProvider<EventRepository>.value(value: eventRepository),
          RepositoryProvider<AssignmentLabelRepository>.value(
              value: _MockLabelRepository()),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<EventBloc>.value(value: eventBloc),
            BlocProvider<CategoryBloc>.value(value: categoryBloc),
            BlocProvider<RoleBloc>.value(value: roleBloc),
            BlocProvider<AssignmentBloc>.value(value: assignmentBloc),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EventFormModal(
                event: source,
                isDuplication: true,
                onSuccess: onSuccess ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final copyAssignments =
      find.widgetWithText(SwitchListTile, 'שכפל גם את השיבוצים');
  final copyHours = find.widgetWithText(SwitchListTile, 'שכפל שעות מותאמות');

  Future<void> turnOnCopyAssignments(WidgetTester tester) async {
    await tester.tap(copyAssignments);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'a source with hours offers the sub-switch once assignments '
      'are being copied, on by default', (tester) async {
    await pumpForm(
      tester,
      assignments: Stream.value([
        assignment('a1', start: '2026-12-01T14:00', end: '2026-12-01T20:00'),
      ]),
    );

    // Not while assignments are not being copied.
    expect(copyHours, findsNothing);

    await turnOnCopyAssignments(tester);

    expect(copyHours, findsOneWidget);
    expect(tester.widget<SwitchListTile>(copyHours).value, isTrue);
    // Indented under the switch it belongs to.
    expect(tester.getTopRight(copyHours).dx,
        lessThan(tester.getTopRight(copyAssignments).dx));
  });

  testWidgets('the sub-switch can be turned off and on', (tester) async {
    await pumpForm(
      tester,
      assignments: Stream.value([
        assignment('a1', start: '2026-12-01T14:00', end: '2026-12-01T20:00'),
      ]),
    );
    await turnOnCopyAssignments(tester);

    await tester.tap(copyHours);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(copyHours).value, isFalse);

    await tester.tap(copyHours);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(copyHours).value, isTrue);
  });

  testWidgets('turning copying of assignments off takes the sub-switch away',
      (tester) async {
    await pumpForm(
      tester,
      assignments: Stream.value([
        assignment('a1', start: '2026-12-01T14:00', end: '2026-12-01T20:00'),
      ]),
    );
    await turnOnCopyAssignments(tester);
    expect(copyHours, findsOneWidget);

    await tester.tap(copyAssignments);
    await tester.pumpAndSettle();

    expect(copyHours, findsNothing);
  });

  testWidgets('a source with no hours never offers it', (tester) async {
    await pumpForm(tester, assignments: Stream.value([assignment('a1')]));

    await turnOnCopyAssignments(tester);

    expect(copyHours, findsNothing);
  });

  testWidgets('hours that cannot be read do not count', (tester) async {
    await pumpForm(
      tester,
      assignments: Stream.value([
        assignment('a1', start: 'soon', end: '2026-12-01T20:00'),
      ]),
    );

    await turnOnCopyAssignments(tester);

    expect(copyHours, findsNothing);
  });

  testWidgets('a stream that fails leaves it hidden and the form working',
      (tester) async {
    await pumpForm(
      tester,
      assignments: Stream<List<Assignment>>.error(StateError('offline')),
    );

    await turnOnCopyAssignments(tester);

    expect(copyHours, findsNothing);
    expect(copyAssignments, findsOneWidget);
  });

  testWidgets('a stream that never answers leaves it hidden after 10 seconds',
      (tester) async {
    await pumpForm(
      tester,
      assignments: StreamController<List<Assignment>>().stream,
    );
    await tester.pump(const Duration(seconds: 11));

    await turnOnCopyAssignments(tester);

    expect(copyHours, findsNothing);
    expect(copyAssignments, findsOneWidget);
  });

  group('the conflict dialog answers the bloc', () {
    final copy = Event(
      id: 'copy',
      name: 'כנס חורף',
      startDate: DateTime(2026, 12, 8),
      endDate: DateTime(2026, 12, 8),
      startTime: '19:00',
      endTime: '23:00',
      assemblyTime: '18:00',
      requiresArmed: false,
      roleRequirements: const {'medic': 2},
      createdAt: stamp,
      updatedAt: stamp,
    );

    AssignmentDuplicationInfo info(String id, {bool withHours = true}) {
      return AssignmentDuplicationInfo(
        assignment: Assignment(
          id: id,
          eventId: 'e1',
          teamMemberId: 'm-$id',
          roleType: 'medic',
          slotIndex: 0,
          status: AssignmentStatus.confirmed,
          notes: '',
          customStartAt: withHours ? '2026-12-01T14:00' : null,
          customEndAt: withHours ? '2026-12-01T20:00' : null,
          createdAt: stamp,
          updatedAt: stamp,
          teamMember: TeamMember(
            id: 'm-$id',
            name: 'חבר $id',
            isActive: true,
            isPermanent: true,
            constraints: const [],
            roleCapabilities: const {'medic': true},
            createdAt: stamp,
            updatedAt: stamp,
            uniqueKey: 'key-$id',
          ),
        ),
        hasAvailabilityConflict: false,
        isInOverQuotaRole: false,
        movedCustomStartAt: withHours ? '2026-12-08T14:00' : null,
        movedCustomEndAt: withHours ? '2026-12-08T20:00' : null,
        availabilityWithEventHours:
            withHours ? DuplicationAvailability.clear : null,
      );
    }

    /// The form open on [state], which the bloc has just emitted; the dialog
    /// it asks for is on screen.
    Future<_RecordingEventBloc> openDialog(
      WidgetTester tester,
      DuplicationRequiresConflictResolution state, {
      VoidCallback? onSuccess,
    }) async {
      final bloc = _RecordingEventBloc();
      whenListen(
        bloc,
        Stream<EventState>.value(state),
        initialState: const EventInitial(),
      );
      await pumpForm(
        tester,
        assignments: const Stream<List<Assignment>>.empty(),
        bloc: bloc,
        onSuccess: onSuccess,
      );
      expect(find.byType(DuplicationConflictResolutionDialog), findsOneWidget);
      return bloc;
    }

    final dialog = find.byType(DuplicationConflictResolutionDialog);

    /// Confirm in the dialog. The form then shows a spinner that never stops,
    /// so pump a bounded while instead of settling.
    Future<void> confirm(WidgetTester tester) async {
      await tester.tap(
          find.descendant(of: dialog, matching: find.text('צור אירוע משוכפל')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    DuplicationRequiresConflictResolution stateWith(
            List<AssignmentDuplicationInfo> infos) =>
        DuplicationRequiresConflictResolution(
          originalEvent: source,
          proposedEvent: copy,
          assignmentInfos: infos,
          roleQuotas: const {'medic': 2},
        );

    testWidgets(
        'hours asked for and an unticked member travel with the '
        'confirmation', (tester) async {
      final bloc = await openDialog(
          tester, stateWith([info('a1'), info('a2', withHours: false)]));

      await tester
          .tap(find.descendant(of: dialog, matching: find.byType(Checkbox)));
      await tester.pump();
      await confirm(tester);

      final sent =
          bloc.added.whereType<ConfirmDuplicationWithExclusions>().single;
      expect(sent.duplicateCustomHours, isTrue);
      expect(sent.customHoursDropped, {'a1'});
      expect(sent.assignmentIdsToExclude, isEmpty);
      expect(sent.originalAssignmentIds, ['a1', 'a2']);
      expect(sent.originalEvent, source);
      expect(sent.proposedEvent, copy);
    });

    testWidgets('hours left ticked drop nothing', (tester) async {
      final bloc = await openDialog(tester, stateWith([info('a1')]));

      await confirm(tester);

      final sent =
          bloc.added.whereType<ConfirmDuplicationWithExclusions>().single;
      expect(sent.duplicateCustomHours, isTrue);
      expect(sent.customHoursDropped, isEmpty);
    });

    testWidgets('a dialog without hours confirms without them', (tester) async {
      final bloc =
          await openDialog(tester, stateWith([info('a1', withHours: false)]));

      await confirm(tester);

      final sent =
          bloc.added.whereType<ConfirmDuplicationWithExclusions>().single;
      expect(sent.duplicateCustomHours, isFalse);
      expect(sent.customHoursDropped, isEmpty);
    });

    testWidgets('cancelling confirms nothing and closes the form',
        (tester) async {
      var closed = 0;
      final bloc = await openDialog(tester, stateWith([info('a1')]),
          onSuccess: () => closed++);

      await tester
          .tap(find.descendant(of: dialog, matching: find.text('ביטול')));
      await tester.pumpAndSettle();

      expect(bloc.added.whereType<ConfirmDuplicationWithExclusions>(), isEmpty);
      expect(closed, 1);
    });
  });
}
