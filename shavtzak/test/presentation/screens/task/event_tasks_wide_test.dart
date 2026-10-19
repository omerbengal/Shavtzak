import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/task_repository.dart';
import 'package:shavtzak/domain/entities/stage.dart';
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

  Finder inSheet(Finder finder) =>
      find.descendant(of: find.byKey(const Key('task-sheet')), matching: finder);

  StageBlock block(WidgetTester tester, String id) =>
      tester.widget<StageBlock>(find.byKey(Key('stage-block-$id')));

  testWidgets('one timeline spans the window, a day under the other',
      (tester) async {
    await pumpWide(tester);

    final tue = find.byKey(const Key('calendar-day-divider-2026-10-20'));
    final wed = find.byKey(const Key('calendar-day-divider-2026-10-21'));
    expect(tue, findsOneWidget);
    expect(wed, findsOneWidget);
    expect(tester.getTopLeft(tue).dy, lessThan(tester.getTopLeft(wed).dy));
    expect(find.byKey(const Key('day-header-2026-10-20')), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('day-column-2026-10-20'))).width,
      greaterThan(wideSize.width * 0.8),
    );
    expect(find.byKey(const Key('task-sheet')), findsNothing);
  });

  testWidgets('clicking a stage opens the sheet from below, centred, its tasks as a table',
      (tester) async {
    await pumpWide(tester);

    await tester.tap(find.byKey(const Key('stage-block-ws')));
    await tester.pumpAndSettle();

    final sheet = find.byKey(const Key('task-sheet'));
    expect(inSheet(find.byKey(const Key('stage-table'))), findsOneWidget);
    expect(inSheet(find.byKey(const Key('table-row-ws-later'))), findsOneWidget);
    expect(tester.getSize(sheet).width, TaskStyle.wideSheetWidth);
    expect(tester.getCenter(sheet).dx, closeTo(wideSize.width / 2, 1));
    expect(block(tester, 'ws').isOutlined, isTrue);
    expect(block(tester, 'lunch').isFaded, isTrue);
    expect(find.byKey(const Key('stage-add')), findsNothing);
  });

  testWidgets("a stage's details use the sheet's width; a contact's phone stays near the name",
      (tester) async {
    const requirements = 'העמדת שולחנות קליטה, זכויות, מפות לבנות ושקעי חשמל';
    final detailed = buildStage(
      id: 'ws',
      title: 'סדנאות',
      date: sampleTue,
      startTime: '14:30',
      endTime: '17:00',
      requirements: requirements,
      contacts: const [
        StageContact(
          id: 'c1',
          name: 'הלל',
          role: 'צייר קריקטורות (מהשעה 10:30)',
          phone: '0522010344',
        ),
      ],
    );
    await pumpWide(
      tester,
      board: TaskBoard(
        tasks: sampleTasks,
        events: [sampleEvent],
        stages: [
          for (final stage in sampleStages) stage.id == 'ws' ? detailed : stage,
        ],
        members: [sDana, sYoav],
      ),
    );
    await tester.tap(find.byKey(const Key('stage-block-ws')));
    await tester.pumpAndSettle();

    final text = inSheet(find.text(requirements));
    expect(tester.getSize(text).height, lessThan(30), reason: 'one line');
    final contact = find.byKey(const Key('stage-contact-c1'));
    expect(tester.getSize(contact).width, TaskStyle.readableWidth);
    expect(tester.getSize(contact).height, lessThan(50), reason: 'one line');
  });

  testWidgets('filter results and tasks use the sheet, with back and close',
      (tester) async {
    await pumpWide(tester);

    await tester.tap(find.byKey(const Key('filter-late')));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('באיחור · 2 משימות')), findsOneWidget);

    await tester.tap(inSheet(find.byKey(const Key('task-row-lunch-late'))));
    await tester.pumpAndSettle();
    expect(inSheet(find.byKey(const Key('task-detail-lunch-late'))), findsOneWidget);

    await tester.tap(find.byKey(const Key('task-sheet-back')));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('באיחור · 2 משימות')), findsOneWidget);

    await tester.tap(find.byKey(const Key('task-sheet-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-sheet')), findsNothing);
    expect(find.byKey(const Key('stage-add')), findsOneWidget);
  });

  testWidgets('a manager edits a task from its table row', (tester) async {
    await pumpWide(tester);
    await tester.tap(find.byKey(const Key('stage-block-ws')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('table-edit-ws-later')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('task-form-title')), findsOneWidget);
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
