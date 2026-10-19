import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_progress.dart';
import 'package:shavtzak/core/utils/task_schedule.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/presentation/screens/task/widgets/stage_sheet_view.dart';

import '../../../../support/sample_event.dart';
import '../../../../support/task_fixtures.dart';

void main() {
  final stage = buildStage(
    id: 'ws',
    title: 'סדנאות',
    date: sampleTue,
    startTime: '14:30',
    endTime: '17:00',
    hotelLocation: 'חדרי הסדנה',
    notes: 'להגיע חצי שעה לפני',
    requirements: '60 מקומות',
    contacts: const [
      StageContact(
        id: 'c1',
        name: 'רונית',
        phone: '0500000000',
        role: 'מנהלת אירועים',
      ),
      StageContact(id: 'c2', name: 'משה'),
    ],
  );
  const progress = TaskProgress(total: 5, done: 1, late: 1, dueSoon: 1);

  late int edits;
  late int deletes;
  late int adds;
  late List<bool> switches;
  late List<String> calls;

  Future<void> pumpHeader(WidgetTester tester, {bool canManage = false}) {
    edits = 0;
    deletes = 0;
    return tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: StageSheetHeader(
            stage: stage,
            canManage: canManage,
            onEdit: () => edits++,
            onDelete: () => deletes++,
          ),
        ),
      ),
    ));
  }

  Future<void> pumpBody(
    WidgetTester tester, {
    Stage? of,
    List<TaskItem> rows = const [],
    TaskProgress withProgress = progress,
    bool missingOnly = false,
    bool canManage = false,
  }) {
    adds = 0;
    switches = [];
    calls = [];
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: StageSheetBody(
              stage: of ?? stage,
              rows: rows,
              progress: withProgress,
              missingOnly: missingOnly,
              onSwitch: switches.add,
              rowBuilder: (task) => Text('row:${task.id}'),
              canManage: canManage,
              onAddTask: () => adds++,
              onCallPhone: calls.add,
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('the header shows the title, the day, the time and the place',
      (tester) async {
    await pumpHeader(tester);

    expect(find.text('סדנאות'), findsOneWidget);
    expect(find.text(stageSummaryLine(stage)), findsOneWidget);
  });

  testWidgets('only managers get edit and delete', (tester) async {
    await pumpHeader(tester);
    expect(find.byKey(const Key('stage-edit-ws')), findsNothing);
    expect(find.byKey(const Key('stage-delete-ws')), findsNothing);

    await pumpHeader(tester, canManage: true);
    await tester.tap(find.byKey(const Key('stage-edit-ws')));
    await tester.tap(find.byKey(const Key('stage-delete-ws')));
    expect((edits, deletes), (1, 1));
  });

  testWidgets('notes, hotel requirements and contacts show, with a call button per phone',
      (tester) async {
    await pumpBody(tester);

    expect(find.text('להגיע חצי שעה לפני'), findsOneWidget);
    expect(find.text('דרישות מהמלון ולוגיסטיקה'), findsOneWidget);
    expect(find.text('60 מקומות'), findsOneWidget);
    expect(find.text('אנשי קשר'), findsOneWidget);
    expect(find.text('רונית · מנהלת אירועים'), findsOneWidget);
    expect(find.text('משה'), findsOneWidget);

    await tester.tap(find.byKey(const Key('stage-contact-call-c1')));
    expect(calls, ['0500000000']);
    expect(find.byKey(const Key('stage-contact-call-c2')), findsNothing);
  });

  testWidgets('the switch reads חסרות (n) | הכל (m) and reports the other side',
      (tester) async {
    await pumpBody(tester, missingOnly: true);

    expect(find.text('חסרות (4)'), findsOneWidget);
    expect(find.text('הכל (5)'), findsOneWidget);
    final segmented = tester.widget<SegmentedButton<bool>>(
      find.byKey(const Key('stage-switch')),
    );
    expect(segmented.selected, {true});

    await tester.tap(find.text('הכל (5)'));
    expect(switches, [false]);
  });

  testWidgets('shows how many are done', (tester) async {
    await pumpBody(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('stage-done-count-ws'))).data,
      '${ltr('1/5')} הושלמו',
    );
  });

  testWidgets('lists the rows it is given, in that order', (tester) async {
    await pumpBody(tester, rows: [
      buildTask(id: 'b', stage: stage, assemblyTime: '15:00'),
      buildTask(id: 'a', stage: stage, assemblyTime: '15:30'),
    ]);

    expect(
      tester.getTopLeft(find.text('row:b')).dy,
      lessThan(tester.getTopLeft(find.text('row:a')).dy),
    );
  });

  testWidgets('managers get משימה חדשה', (tester) async {
    await pumpBody(tester);
    expect(find.byKey(const Key('stage-add-task-ws')), findsNothing);

    await pumpBody(tester, canManage: true);
    await tester.tap(find.byKey(const Key('stage-add-task-ws')));
    expect(adds, 1);
  });

  testWidgets('a stage without tasks says so, with no switch', (tester) async {
    await pumpBody(
      tester,
      of: stRooms,
      withProgress: const TaskProgress(),
      canManage: true,
    );

    expect(find.text('אין עדיין משימות בשלב זה'), findsOneWidget);
    expect(find.byKey(const Key('stage-switch')), findsNothing);
    expect(find.byKey(const Key('stage-add-task-rooms')), findsOneWidget);
  });

  testWidgets('a missing list with nothing in it says the stage is done',
      (tester) async {
    await pumpBody(
      tester,
      withProgress: const TaskProgress(total: 2, done: 2),
      missingOnly: true,
    );

    expect(find.text('כל המשימות בשלב הושלמו'), findsOneWidget);
  });
}
