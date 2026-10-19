import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/task_repository.dart';
import 'package:shavtzak/domain/entities/team_member.dart';
import 'package:shavtzak/presentation/screens/task/task_style.dart';
import 'package:shavtzak/presentation/screens/task/widgets/member_timeline.dart';
import 'package:shavtzak/presentation/screens/task/widgets/stage_block.dart';

import '../../../support/event_tasks_harness.dart';
import '../../../support/fake_task_repository.dart';
import '../../../support/sample_event.dart';
import '../../../support/task_fixtures.dart';

void main() {
  final admin = buildMember(id: 'boss', name: 'מנהלת', isAdmin: true);
  late FakeTaskRepository repository;

  TaskBoard sampleTaskBoard() => TaskBoard(
        tasks: sampleTasks,
        events: [sampleEvent],
        stages: sampleStages,
        members: [sDana, sYoav],
      );

  Future<void> pumpWide(
    WidgetTester tester, {
    TeamMember? user,
    TaskBoard? board,
    Map<String, List<TeamMember>>? assignees,
  }) async {
    final harness = await pumpEventTasks(
      tester,
      user: user ?? admin,
      size: wideSize,
      clock: () => sampleNow,
      board: board ?? sampleTaskBoard(),
      assignees: assignees,
    );
    repository = harness.repository;
    await tester.pumpAndSettle();
  }

  Finder inPanel(Finder finder) =>
      find.descendant(of: find.byKey(const Key('stage-panel')), matching: finder);

  StageBlock block(WidgetTester tester, String id) =>
      tester.widget<StageBlock>(find.byKey(Key('stage-block-$id')));

  testWidgets('the days sit side by side and the panel waits on the left',
      (tester) async {
    await pumpWide(tester);

    expect(find.byKey(const Key('day-header-2026-10-20')), findsOneWidget);
    expect(find.byKey(const Key('day-header-2026-10-21')), findsOneWidget);
    expect(inPanel(find.byKey(const Key('stage-panel-hint'))), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('stage-panel'))).dx,
      lessThan(tester.getTopLeft(find.byKey(const Key('day-column-2026-10-20'))).dx),
    );
    expect(find.byKey(const Key('task-sheet')), findsNothing);
  });

  testWidgets('clicking a stage opens it in the panel as a table; it stays outlined and nothing fades',
      (tester) async {
    await pumpWide(tester);

    await tester.tap(find.byKey(const Key('stage-block-ws')));
    await tester.pumpAndSettle();

    expect(inPanel(find.byKey(const Key('stage-table'))), findsOneWidget);
    expect(inPanel(find.byKey(const Key('table-row-ws-later'))), findsOneWidget);
    expect(block(tester, 'ws').isOutlined, isTrue);
    expect(block(tester, 'lunch').isFaded, isFalse);
    expect(find.byKey(const Key('task-sheet')), findsNothing);
  });

  testWidgets('the toolbar holds the summary, the filters and the check',
      (tester) async {
    await pumpWide(tester, assignees: {
      'e1': [sDana],
    });

    Finder inToolbar(Finder finder) => find.descendant(
          of: find.byKey(const Key('wide-toolbar')),
          matching: finder,
        );
    expect(inToolbar(find.byKey(const Key('event-summary'))), findsOneWidget);
    expect(inToolbar(find.byKey(const Key('task-filter-bar'))), findsOneWidget);
    expect(inToolbar(find.text('לבדיקה: ')), findsOneWidget);
    expect(
      inToolbar(find.text('3 משימות של מי שכבר לא משובץ לאירוע')),
      findsOneWidget,
    );
  });

  testWidgets('filter, search and check results, and tasks, use the panel',
      (tester) async {
    await pumpWide(tester);

    await tester.tap(find.byKey(const Key('filter-late')));
    await tester.pumpAndSettle();
    expect(inPanel(find.text('באיחור · 2 משימות')), findsOneWidget);

    await tester.tap(inPanel(find.byKey(const Key('task-row-lunch-late'))));
    await tester.pumpAndSettle();
    expect(inPanel(find.byKey(const Key('task-detail-lunch-late'))), findsOneWidget);

    await tester.tap(find.byKey(const Key('stage-panel-back')));
    await tester.pumpAndSettle();
    expect(inPanel(find.text('באיחור · 2 משימות')), findsOneWidget);

    await tester.tap(find.byKey(const Key('stage-panel-close')));
    await tester.pumpAndSettle();
    expect(inPanel(find.byKey(const Key('stage-panel-hint'))), findsOneWidget);
    expect(find.byKey(const Key('task-sheet')), findsNothing);
  });

  testWidgets('a manager edits a task from its table row', (tester) async {
    await pumpWide(tester);
    await tester.tap(find.byKey(const Key('stage-block-ws')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('table-edit-ws-later')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-form-title')), findsOneWidget);
  });

  testWidgets('more than three days fall back to day chips', (tester) async {
    final longEvent = buildEvent(
      id: 'e1',
      name: 'דו יומי הנהלה',
      startDate: sampleTue,
      endDate: DateTime(2026, 10, 23),
      location: 'מלון רויאל',
    );
    await pumpWide(
      tester,
      board: TaskBoard(
        tasks: sampleTasks,
        events: [longEvent],
        stages: sampleStages,
        members: [sDana, sYoav],
      ),
    );

    expect(find.byKey(const Key('calendar-day-2026-10-23')), findsOneWidget);
    expect(find.byKey(const Key('day-column-2026-10-20')), findsOneWidget);
    expect(find.byKey(const Key('day-column-2026-10-21')), findsNothing);
  });

  testWidgets('a member at this width gets the same layout and ticks their own tasks',
      (tester) async {
    await pumpWide(tester, user: sDana);
    await tester.tap(find.text('כל השלבים'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('stage-block-ws')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('table-tick-ws-later')));
    await tester.pump();

    expect(repository.calls, ['complete:ws-later:true']);
    expect(
      tester.widget<Checkbox>(find.byKey(const Key('table-tick-ws-theirs'))).onChanged,
      isNull,
    );
    expect(find.byKey(const Key('table-edit-ws-later')), findsNothing);
  });

  testWidgets('המשימות שלי stays a centred column of readable width',
      (tester) async {
    await pumpWide(tester, user: sDana);

    final timeline = find.byType(MemberTimeline);
    expect(tester.getSize(timeline).width, lessThanOrEqualTo(TaskStyle.readableWidth));
    expect(tester.getCenter(timeline).dx, closeTo(wideSize.width / 2, 1));
  });
}
