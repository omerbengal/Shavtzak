import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shavtzak/data/repositories/task_repository.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/bloc/task/task_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_bloc.dart';
import 'package:shavtzak/presentation/bloc/user_selection/user_selection_state.dart';
import 'package:shavtzak/presentation/screens/task/edit/event_edit_screen.dart';
import 'package:shavtzak/presentation/screens/task/tasks_place.dart';

import '../../../../support/event_tasks_harness.dart';
import '../../../../support/fake_task_import_files.dart';
import '../../../../support/fake_task_repository.dart';
import '../../../../support/sample_event.dart';
import '../../../../support/task_fixtures.dart';

void main() {
  final admin = buildMember(id: 'boss', name: 'מנהלת', isAdmin: true);
  final member = buildMember(id: 'm1', name: 'דנה');

  final detailedWs = buildStage(
    id: 'ws',
    title: 'סדנאות',
    date: sampleTue,
    startTime: '14:30',
    endTime: '17:00',
    hotelLocation: 'חדרי הסדנה',
    notes: 'להגיע מוקדם',
    requirements: 'מקרן ומסך',
    contacts: const [
      StageContact(id: 'c1', name: 'הלל', role: 'מנהל', phone: '0522010344'),
    ],
  );

  TaskBoard board() => TaskBoard(
        tasks: sampleTasks,
        events: [sampleEvent],
        stages: [
          for (final stage in sampleStages)
            stage.id == 'ws' ? detailedWs : stage,
        ],
        members: [sDana, sYoav],
      );

  Future<FakeTaskRepository> pump(
    WidgetTester tester, {
    TeamMember? user,
    Size size = const Size(1280, 3200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeTaskRepository()
      ..assigneesByEvent = {
        'e1': [sDana, sYoav],
      };
    final bloc = TaskBloc(repository: repo);
    final userBloc = MockUserSelectionBloc();
    addTearDown(() {
      unawaited(bloc.close());
      if (!repo.controller.isClosed) unawaited(repo.controller.close());
    });
    whenListen(
      userBloc,
      const Stream<UserSelectionState>.empty(),
      initialState: UserAuthenticated(user ?? admin),
    );
    const place = TasksPlace.standalone;
    await tester.pumpWidget(RepositoryProvider<TaskRepository>.value(
      value: repo,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<TaskBloc>.value(value: bloc),
          BlocProvider<UserSelectionBloc>.value(value: userBloc),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: place.editRoute('e1'),
            routes: [
              GoRoute(
                path: place.listRoute,
                builder: (context, state) => const Text('list'),
                routes: [
                  GoRoute(
                    path: ':eventId',
                    builder: (context, state) =>
                        const Scaffold(body: Text('מסך האירוע')),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (context, state) => EventEditScreen(
                          eventId: state.pathParameters['eventId']!,
                          place: place,
                          clock: () => sampleNow,
                          importFiles: FakeTaskImportFiles(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    repo.controller.add(board());
    await tester.pump();
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('manager sees every stage and task detail', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('edit-stage-ws')), findsOneWidget);
    expect(find.text('חדרי הסדנה'), findsOneWidget);
    expect(find.text('להגיע מוקדם'), findsOneWidget);
    expect(find.text('מקרן ומסך'), findsOneWidget);
    expect(find.byKey(const Key('edit-contact-chip-c1')), findsOneWidget);
    expect(find.byKey(const Key('edit-task-row-ws-later')), findsOneWidget);
    expect(find.text('חלוקת ערכות למשתתפים'), findsOneWidget);
    // Not a progress screen.
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('non-manager sees אין הרשאה', (tester) async {
    await pump(tester, user: member);
    expect(find.byKey(const Key('edit-no-access')), findsOneWidget);
    expect(find.byKey(const Key('edit-list')), findsNothing);
  });

  testWidgets('editing a title dispatches UpdateTask with the new title',
      (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.text('חלוקת ערכות למשתתפים'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-text')), 'ערכות חדשות');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.updatedTasks.single.id, 'ws-later');
    expect(repo.updatedTasks.single.title, 'ערכות חדשות');
    // Shown at once, before the stream brings it back.
    expect(find.text('ערכות חדשות'), findsOneWidget);
  });

  testWidgets('two quick edits build on each other', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.text('חלוקת ערכות למשתתפים'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-text')), 'ערכות');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-task-description-ws-later')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-text')), 'בכניסה');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(repo.updatedTasks, hasLength(2));
    expect(repo.updatedTasks.last.title, 'ערכות');
    expect(repo.updatedTasks.last.description, 'בכניסה');
  });

  testWidgets('a refused save puts the stored value back', (tester) async {
    final repo = await pump(tester);
    repo.failWith = Exception('boom');
    await tester.tap(find.text('חלוקת ערכות למשתתפים'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-text')), 'לא יישמר');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('לא יישמר'), findsNothing);
    expect(find.text('חלוקת ערכות למשתתפים'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('editing a stage location dispatches UpdateStage',
      (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.text('חדרי הסדנה'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-text')), 'אולם ב');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.updatedStages.single.hotelLocation, 'אולם ב');
    expect(repo.updatedStages.single.contacts, detailedWs.contacts);
  });

  testWidgets('moving a task from its menu sends the new stage',
      (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.byKey(const Key('edit-task-menu-ws-later')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-task-move')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-move-to-dinner')));
    await tester.pumpAndSettle();
    expect(repo.updatedTasks.single.stageId, 'dinner');
  });

  testWidgets('the time is edited in a small window, not in its cell',
      (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.byKey(const Key('edit-task-time-ws-later')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-value-sheet')), findsOneWidget);
    expect(find.byKey(const Key('edit-value-editor')), findsNothing);
    await tester.enterText(
        find.descendant(
            of: find.byKey(const Key('edit-time')),
            matching: find.byType(EditableText)),
        '18:15');
    await tester.tap(find.byKey(const Key('edit-value-save')));
    await tester.pumpAndSettle();
    expect(repo.updatedTasks.single.assemblyTime, '18:15');
  });

  testWidgets('dragging a task onto another stage moves it', (tester) async {
    final repo = await pump(tester);
    final handle = find.byKey(const Key('edit-task-drag-ws-later'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture
        .moveTo(tester.getCenter(find.byKey(const Key('edit-stage-dinner'))));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(repo.updatedTasks.single.stageId, 'dinner');
  });

  testWidgets('on a phone a long press drags a task onto another stage',
      (tester) async {
    final repo = await pump(tester, size: const Size(400, 5000));
    final card = find.byKey(const Key('edit-task-card-ws-later'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(card));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture
        .moveTo(tester.getCenter(find.byKey(const Key('edit-stage-dinner'))));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(repo.updatedTasks.single.stageId, 'dinner');
  });

  testWidgets('on a phone a short tap still edits, not drags',
      (tester) async {
    final repo = await pump(tester, size: const Size(400, 5000));
    await tester.tap(find.text('חלוקת ערכות למשתתפים'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-value-sheet')), findsOneWidget);
    expect(repo.updatedTasks, isEmpty);
  });

  testWidgets('holding a dragged task at the bottom edge scrolls down, '
      'at the top scrolls back up', (tester) async {
    await pump(tester, size: const Size(1280, 700));
    double offset() => tester
        .state<ScrollableState>(find.descendant(
            of: find.byKey(const Key('edit-list')),
            matching: find.byType(Scrollable)).first)
        .position
        .pixels;
    final handle = find.byKey(const Key('edit-task-drag-ws-later'));
    await tester.ensureVisible(handle);
    await tester.pumpAndSettle();
    final start = offset();
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveTo(const Offset(640, 695));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final down = offset();
    expect(down, greaterThan(start));
    // In the middle it stays put.
    await gesture.moveTo(const Offset(640, 350));
    await tester.pump(const Duration(milliseconds: 16));
    final held = offset();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(offset(), held);
    await gesture.moveTo(const Offset(640, 2));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(offset(), lessThan(held));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a phone card shows its whole time, on one line',
      (tester) async {
    await pump(tester, size: const Size(400, 5000));
    final time = find.descendant(
      of: find.byKey(const Key('edit-task-time-ws-later')),
      matching: find.text('15:45'),
    );
    final paragraph = tester.renderObject<RenderParagraph>(time);
    expect(paragraph.size.width,
        greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)));
    expect(paragraph.size.height,
        lessThan(paragraph.getMinIntrinsicHeight(double.infinity) * 1.5));
  });

  testWidgets('a phone shows a long event name on two lines', (tester) async {
    await pump(tester, size: const Size(400, 5000));
    final title = tester.widget<Text>(find.byKey(const Key('edit-title')));
    expect(title.data, 'דו יומי הנהלה');
    expect(title.maxLines, 2);
    expect(find.textContaining('עריכה · '), findsOneWidget);
  });

  testWidgets('narrow window shows task cards', (tester) async {
    await pump(tester, size: const Size(400, 5000));
    expect(find.byKey(const Key('edit-task-card-ws-later')), findsOneWidget);
    expect(find.byKey(const Key('edit-task-row-ws-later')), findsNothing);
    // Requirements fold away on a phone.
    expect(find.text('מקרן ומסך'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('edit-stage-more-ws')));
    await tester.tap(find.byKey(const Key('edit-stage-more-ws')));
    await tester.pumpAndSettle();
    expect(find.text('מקרן ומסך'), findsOneWidget);
  });

  testWidgets('search keeps matching tasks and hides empty stages',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('edit-search')), 'ערכות');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-task-row-ws-later')), findsOneWidget);
    expect(find.byKey(const Key('edit-stage-dinner')), findsNothing);
  });

  testWidgets('back returns to the event screen', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('edit-back')));
    await tester.pumpAndSettle();
    expect(find.text('מסך האירוע'), findsOneWidget);
  });

  testWidgets('the event screen shows עריכה to managers only', (tester) async {
    await pumpEventTasks(tester,
        user: admin,
        board: board(),
        clock: () => sampleNow,
        size: tallPhoneSize);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tasks-edit')), findsOneWidget);
  });

  testWidgets('a member gets no עריכה button', (tester) async {
    await pumpEventTasks(tester,
        user: sDana,
        board: board(),
        clock: () => sampleNow,
        size: tallPhoneSize);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tasks-edit')), findsNothing);
  });
}
