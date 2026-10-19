import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_schedule.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/presentation/screens/task/task_style.dart';
import 'package:shavtzak/presentation/screens/task/widgets/stage_task_table.dart';

import '../../../../support/sample_event.dart';
import '../../../../support/task_fixtures.dart';

void main() {
  // sampleNow is Tuesday 14:40: ws-theirs (14:15) is late, ws-soon (15:00)
  // is due in the half hour, ws-later (15:45) is neither.
  late List<String> ticks;
  late List<String> opens;
  late List<String> edits;
  late List<String> deletes;
  late List<String> calls;

  Future<void> pumpTable(
    WidgetTester tester,
    List<TaskItem> tasks, {
    bool canManage = true,
    bool Function(TaskItem task)? canTick,
    List<String> Function(TaskItem task)? removedAssigneeIds,
    Size size = const Size(1280, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ticks = [];
    opens = [];
    edits = [];
    deletes = [];
    calls = [];
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SingleChildScrollView(
            child: StageTaskTable(
              tasks: tasks,
              now: sampleNow,
              viewerId: sDana.id,
              canTick: canTick ?? (_) => true,
              canManage: canManage,
              removedAssigneeIds: removedAssigneeIds ?? (_) => const [],
              onSetComplete: (task, isComplete) =>
                  ticks.add('${task.id}:$isComplete'),
              onOpen: (task) => opens.add(task.id),
              onEdit: (task) => edits.add(task.id),
              onDelete: (task) => deletes.add(task.id),
              onCallPhone: calls.add,
            ),
          ),
        ),
      ),
    ));
  }

  Future<void> hover(WidgetTester tester, String id) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byKey(Key('table-row-$id'))));
    await tester.pump();
  }

  double actionsOpacity(WidgetTester tester, String id) => tester
      .widget<Opacity>(find
          .ancestor(
            of: find.byKey(Key('table-edit-$id')),
            matching: find.byType(Opacity),
          )
          .first)
      .opacity;

  TextStyle styleOf(WidgetTester tester, Finder finder) =>
      tester.widget<Text>(finder).style!;

  testWidgets('has the four columns and keeps the given order, untimed last',
      (tester) async {
    await pumpTable(tester, [tWsTheirs, tWsSoon, tWsLater, tWsUntimed]);

    expect(find.byKey(const Key('stage-table')), findsOneWidget);
    for (final header in ['התייצבות', 'משימה', 'אחראים', 'תת-משימות']) {
      expect(find.text(header), findsOneWidget);
    }
    final ys = [
      for (final task in [tWsTheirs, tWsSoon, tWsLater, tWsUntimed])
        tester.getTopLeft(find.byKey(Key('table-row-${task.id}'))).dy,
    ];
    expect(ys, [...ys]..sort());
    expect(find.text('ללא שעה'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a row carries the tick box, the late mark, the orange time and the update line',
      (tester) async {
    final updated = tWsTheirs.copyWith(
      description: 'ליד הכניסה לאולם',
      assigneeUpdate: 'מחכים למקרן',
      assigneeUpdateByName: 'נועה לוי',
      assigneeUpdateAt: DateTime(2026, 10, 20, 14, 22),
    );
    await pumpTable(tester, [updated, tWsSoon, tWsLater]);

    expect(find.byKey(const Key('table-tick-ws-theirs')), findsOneWidget);
    expect(find.text('באיחור'), findsOneWidget);
    expect(styleOf(tester, find.text(ltr('14:15'))).color, TaskStyle.lateDark);
    expect(styleOf(tester, find.text(ltr('15:00'))).color, TaskStyle.soonDark);
    expect(
      styleOf(tester, find.text(ltr('15:45'))).color,
      isNot(anyOf(TaskStyle.soonDark, TaskStyle.lateDark)),
    );
    expect(find.text('ליד הכניסה לאולם'), findsOneWidget);
    expect(find.text('מחכים למקרן · נועה לוי, ${ltr('14:22')}'), findsOneWidget);
    expect(find.textContaining('בעוד'), findsNothing);

    await tester.tap(find.byKey(const Key('table-tick-ws-theirs')));
    expect(ticks, ['ws-theirs:true']);
    expect(opens, isEmpty);
  });

  testWidgets('the pencil and the bin show on hover, for managers only',
      (tester) async {
    await pumpTable(tester, [tWsLater, tWsUntimed]);

    expect(actionsOpacity(tester, 'ws-later'), 0);
    await hover(tester, 'ws-later');
    expect(actionsOpacity(tester, 'ws-later'), 1);
    expect(actionsOpacity(tester, 'ws-untimed'), 0);

    await tester.tap(find.byKey(const Key('table-edit-ws-later')));
    await tester.tap(find.byKey(const Key('table-delete-ws-later')));
    expect(edits, ['ws-later']);
    expect(deletes, ['ws-later']);
    expect(opens, isEmpty);

    final pencil = tester.widget<Icon>(find.descendant(
        of: find.byKey(const Key('table-edit-ws-later')),
        matching: find.byType(Icon)));
    expect(pencil.icon, Icons.edit);
    expect(pencil.color, TaskStyle.edit);

    await pumpTable(tester, [tWsLater], canManage: false);
    expect(find.byKey(const Key('table-edit-ws-later')), findsNothing);
    expect(find.byKey(const Key('table-delete-ws-later')), findsNothing);
  });

  testWidgets('a hidden pencil is still reachable by touch', (tester) async {
    await pumpTable(tester, [tWsLater]);

    expect(actionsOpacity(tester, 'ws-later'), 0);
    await tester.tap(find.byKey(const Key('table-edit-ws-later')));
    expect(edits, ['ws-later']);
  });

  testWidgets('a removed assignee is struck through in red, with the note',
      (tester) async {
    final task = buildTask(
      id: 't1',
      title: 'קבלת אורחים',
      stage: stWorkshops,
      assemblyTime: '16:00',
      assigneeIds: const ['m1', 'm2', 'gone'],
      assignees: [sDana, sYoav],
    );
    await pumpTable(
      tester,
      [task],
      removedAssigneeIds: (_) => const ['m2', 'gone'],
    );

    final yoav = styleOf(tester, find.text('יואב'));
    expect(yoav.decoration, TextDecoration.lineThrough);
    expect(yoav.color, TaskStyle.lateDark);
    expect(find.text('חבר צוות שנמחק'), findsOneWidget);
    expect(find.text('כבר לא משובץ לאירוע'), findsNWidgets(2));
    expect(find.byKey(const Key('table-assignee-t1-m1')), findsOneWidget);
    final mine = tester
        .widget<Material>(find.byKey(const Key('table-assignee-t1-m1')));
    expect(mine.color, TaskStyle.mine);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long title wraps instead of ending in …', (tester) async {
    final title = 'משימה ארוכה מאוד ' * 5;
    await pumpTable(tester, [tWsLater.copyWith(title: title)]);

    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.text(title));
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.getSize(find.text(title)).height,
        greaterThanOrEqualTo(2 * TaskStyle.rowTitleSize));
  });

  testWidgets('someone who may not tick gets a disabled box', (tester) async {
    await pumpTable(tester, [tWsTheirs, tWsLater],
        canTick: (task) => task.id == 'ws-later');

    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('table-tick-ws-theirs')))
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('table-tick-ws-later')))
          .onChanged,
      isNotNull,
    );
  });

  testWidgets('a task with subtasks shows its count and no tick box',
      (tester) async {
    await pumpTable(tester, [tWsSoon, tWsLater]);

    expect(find.text(ltr('1/3')), findsOneWidget);
    expect(find.byKey(const Key('table-tick-ws-soon')), findsNothing);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('a click on a row opens the task', (tester) async {
    await pumpTable(tester, [tWsLater]);

    await tester.tap(find.text('חלוקת ערכות למשתתפים'));
    expect(opens, ['ws-later']);
    expect(ticks, isEmpty);
  });

  testWidgets('a call button calls the assignee\'s phone', (tester) async {
    await pumpTable(tester, [tWsSoon]);

    expect(find.byKey(const Key('table-call-ws-soon-m2')), findsNothing);
    await tester.tap(find.byKey(const Key('table-call-ws-soon-m1')));
    expect(calls, ['0501234567']);
    expect(opens, isEmpty);
  });
}
