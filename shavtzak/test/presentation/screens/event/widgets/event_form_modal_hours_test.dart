// EventFormModal in edit mode: when a save moves the event in time, members
// with custom hours are resolved first (CustomHoursResolveDialog) and the
// chosen hours go to the backend with the event. The hours step comes before
// anything is written, so cancelling it leaves everything as it was.
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
import 'package:shavtzak/domain/entities/custom_hours_resolution.dart';
import 'package:shavtzak/domain/entities/event.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_bloc.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_event.dart';
import 'package:shavtzak/presentation/bloc/assignment/assignment_state.dart';
import 'package:shavtzak/presentation/bloc/category/category_bloc.dart';
import 'package:shavtzak/presentation/bloc/category/category_event.dart';
import 'package:shavtzak/presentation/bloc/category/category_state.dart';
import 'package:shavtzak/presentation/bloc/event/event_bloc.dart';
import 'package:shavtzak/presentation/bloc/role/role_bloc.dart';
import 'package:shavtzak/presentation/bloc/role/role_event.dart';
import 'package:shavtzak/presentation/bloc/role/role_state.dart';
import 'package:shavtzak/presentation/screens/event/widgets/custom_hours_resolve_dialog.dart';
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

void main() {
  final stamp = DateTime(2026, 10, 1);

  // 27-28.10, assembly 12:00, team end 23:30.
  final event = Event(
    id: 'e1',
    name: 'כנס חורף',
    startDate: DateTime(2026, 10, 27),
    endDate: DateTime(2026, 10, 28),
    startTime: '19:00',
    endTime: '23:00',
    teamEndTime: '23:30',
    assemblyTime: '12:00',
    location: 'אולמי ורסאי',
    requiresArmed: false,
    roleRequirements: const {'medic': 2},
    createdAt: stamp,
    updatedAt: stamp,
  );

  final dana = TeamMember(
    id: 'm1',
    name: 'דנה כהן',
    isActive: true,
    isPermanent: true,
    constraints: const [],
    roleCapabilities: const {},
    createdAt: stamp,
    updatedAt: stamp,
    uniqueKey: 'k1',
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
        teamMember: dana,
      );

  late MockEventRepository eventRepository;
  late MockAssignmentRepository assignmentRepository;
  var saved = 0;

  Future<void> pumpForm(
    WidgetTester tester, {
    required Stream<List<Assignment>> assignments,
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

    eventRepository = MockEventRepository();
    assignmentRepository = MockAssignmentRepository();
    saved = 0;
    when(eventRepository.updateEvent(
      any,
      knownOriginal: anyNamed('knownOriginal'),
      customHoursResolutions: anyNamed('customHoursResolutions'),
    )).thenAnswer((invocation) async => invocation.positionalArguments.first);
    when(assignmentRepository.watchAssignmentsByEvent('e1'))
        .thenAnswer((_) => assignments);
    // The quota step's one-shot read: reached only after the hours step.
    when(assignmentRepository.getAssignmentsByEvent('e1'))
        .thenAnswer((_) async => const <Assignment>[]);

    final eventBloc = EventBloc(eventRepository, assignmentRepository);
    addTearDown(eventBloc.close);
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
                event: event,
                onSuccess: () => saved++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder timeField(String label) => find.widgetWithText(TextFormField, label);

  Future<void> changeAssemblyTo(WidgetTester tester, String digits) async {
    await tester.enterText(timeField('שעת התייצבות (אופציונלי)'), digits);
    await tester.pump();
  }

  /// While a save is in flight the button shows a spinner that never stops
  /// animating, so pumpAndSettle would time out: pump a bounded while instead.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, 'שמור'));
    await settle(tester);
  }

  ({Event event, Event? original, List<CustomHoursResolution> resolutions})
      updateCall() {
    final call = verify(eventRepository.updateEvent(
      captureAny,
      knownOriginal: captureAnyNamed('knownOriginal'),
      customHoursResolutions: captureAnyNamed('customHoursResolutions'),
    )).captured;
    return (
      event: call[0] as Event,
      original: call[1] as Event?,
      resolutions: (call[2] as List).cast<CustomHoursResolution>(),
    );
  }

  testWidgets('a save that moves nothing writes straight away, asking nobody',
      (tester) async {
    await pumpForm(tester, assignments: const Stream.empty());

    await tester.enterText(
        find.widgetWithText(TextFormField, 'שם האירוע'), 'כנס חורף 2027');
    await tester.pump();
    await tapSave(tester);

    verifyNever(assignmentRepository.watchAssignmentsByEvent(any));
    expect(find.byType(CustomHoursResolveDialog), findsNothing);
    final call = updateCall();
    expect(call.event.name, 'כנס חורף 2027');
    expect(call.original, event);
    expect(call.resolutions, isEmpty);
    expect(saved, 1);
  });

  testWidgets(
      'times changed but nobody has hours: no question, nothing extra '
      'is sent', (tester) async {
    await pumpForm(
      tester,
      assignments: Stream.value([assignment('a1')]),
    );

    await changeAssemblyTo(tester, '1100');
    await tapSave(tester);

    expect(find.byType(CustomHoursResolveDialog), findsNothing);
    final call = updateCall();
    expect(call.event.assemblyTime, '11:00');
    expect(call.resolutions, isEmpty);
    expect(saved, 1);
  });

  testWidgets(
      'times changed and a member has hours: the answer travels with '
      'the event', (tester) async {
    await pumpForm(
      tester,
      assignments: Stream.value([
        assignment('a1', start: '2026-10-27T14:00', end: '2026-10-27T23:00'),
      ]),
    );

    await changeAssemblyTo(tester, '1100');
    await tapSave(tester);

    // Asked first; nothing written yet.
    expect(find.byType(CustomHoursResolveDialog), findsOneWidget);
    expect(find.text('דנה כהן'), findsOneWidget);
    verifyNever(eventRepository.updateEvent(
      any,
      knownOriginal: anyNamed('knownOriginal'),
      customHoursResolutions: anyNamed('customHoursResolutions'),
    ));

    await tester.tap(find.text('להשאיר כמו שזה'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ElevatedButton, 'שמור אירוע'));
    await settle(tester);

    final call = updateCall();
    expect(call.event.assemblyTime, '11:00');
    expect(call.original, event);
    expect(call.resolutions, [
      const CustomHoursResolution(
        assignmentId: 'a1',
        customStartAt: '2026-10-27T14:00',
        customEndAt: '2026-10-27T23:00',
      ),
    ]);
    expect(saved, 1);
  });

  testWidgets(
      'cancelling the question writes nothing and the form stays '
      'open and ready', (tester) async {
    await pumpForm(
      tester,
      assignments: Stream.value([
        assignment('a1', start: '2026-10-27T14:00', end: '2026-10-27T23:00'),
      ]),
    );

    await changeAssemblyTo(tester, '1100');
    await tapSave(tester);
    expect(find.byType(CustomHoursResolveDialog), findsOneWidget);

    await tester.tap(find.text('ביטול').last);
    await settle(tester);

    expect(find.byType(CustomHoursResolveDialog), findsNothing);
    verifyNever(eventRepository.updateEvent(
      any,
      knownOriginal: anyNamed('knownOriginal'),
      customHoursResolutions: anyNamed('customHoursResolutions'),
    ));
    expect(saved, 0);
    // The save button is back to its label: not stuck on the spinner.
    expect(find.widgetWithText(ElevatedButton, 'שמור'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'שמור'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
      'the hours question comes before the quota step: cancelling it '
      'never reaches the assignments a quota cut would have touched',
      (tester) async {
    await pumpForm(
      tester,
      assignments: Stream.value([
        assignment('a1', start: '2026-10-27T14:00', end: '2026-10-27T23:00'),
      ]),
    );

    // Fewer medics (2 to 1) and a new assembly time, in one save.
    await tester.tap(find.descendant(
      of: find.widgetWithText(ListTile, 'חובש/ת'),
      matching: find.byIcon(Icons.remove_circle_outline),
    ));
    await tester.pump();
    await changeAssemblyTo(tester, '1100');
    await tapSave(tester);
    expect(find.byType(CustomHoursResolveDialog), findsOneWidget);

    await tester.tap(find.text('ביטול').last);
    await settle(tester);

    verifyNever(assignmentRepository.getAssignmentsByEvent(any));
    verifyNever(eventRepository.updateEvent(
      any,
      knownOriginal: anyNamed('knownOriginal'),
      customHoursResolutions: anyNamed('customHoursResolutions'),
    ));
    expect(saved, 0);
  });

  testWidgets(
      'hours that cannot be checked in time stop the save with a '
      'message', (tester) async {
    await pumpForm(tester,
        assignments: StreamController<List<Assignment>>().stream);

    await changeAssemblyTo(tester, '1100');
    await tester.tap(find.widgetWithText(ElevatedButton, 'שמור'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();

    expect(
        find.text('לא ניתן לבדוק שעות מותאמות כרגע — נסו שוב'), findsOneWidget);
    verifyNever(eventRepository.updateEvent(
      any,
      knownOriginal: anyNamed('knownOriginal'),
      customHoursResolutions: anyNamed('customHoursResolutions'),
    ));
    expect(saved, 0);
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'שמור'))
          .onPressed,
      isNotNull,
    );
  });
}
