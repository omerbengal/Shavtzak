import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_schedule.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';
import 'package:shavtzak/presentation/screens/task/task_style.dart';
import 'package:shavtzak/presentation/screens/task/widgets/task_row.dart';

import '../../../../support/sample_event.dart';
import '../../../../support/task_fixtures.dart';

void main() {
  // sampleNow is Tuesday 14:40.
  final dana = buildMember(id: 'm1', name: 'דנה', phoneNumber: '0501234567');
  final yoav = buildMember(id: 'm2', name: 'יואב');

  late List<bool> completions;
  late List<String> calls;
  late int opens;

  Future<void> pumpRow(
    WidgetTester tester,
    TaskItem task, {
    bool canTick = true,
    String viewerId = 'm1',
    List<String> removedAssigneeIds = const [],
    Size? size,
  }) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    completions = [];
    calls = [];
    opens = 0;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: ListView(
            children: [
              TaskRow(
                task: task,
                now: sampleNow,
                viewerId: viewerId,
                canTick: canTick,
                onSetComplete: completions.add,
                onOpen: () => opens++,
                onCallPhone: calls.add,
                removedAssigneeIds: removedAssigneeIds,
              ),
            ],
          ),
        ),
      ),
    ));
  }

  TaskItem task({
    String id = 't1',
    String title = 'חלוקת ערכות למשתתפים',
    String? at = '15:45',
    bool isComplete = false,
    List<Subtask> subtasks = const [],
    List<String> assigneeIds = const ['m1'],
    String? update,
    String? updateBy,
    DateTime? updateAt,
  }) {
    final people = {'m1': dana, 'm2': yoav};
    return buildTask(
      id: id,
      title: title,
      stage: stWorkshops,
      assemblyTime: at,
      isComplete: isComplete,
      subtasks: subtasks,
      assigneeIds: assigneeIds,
      assignees: [
        for (final memberId in assigneeIds)
          if (people[memberId] != null) people[memberId]!,
      ],
      assigneeUpdate: update,
      assigneeUpdateByName: updateBy,
      assigneeUpdateAt: updateAt,
    );
  }

  TextStyle styleOf(WidgetTester tester, Finder finder) =>
      tester.widget<Text>(finder).style!;

  testWidgets('shows the title, the report time and the subtask count',
      (tester) async {
    await pumpRow(
      tester,
      task(title: 'הכנת חדר סדנה 2', at: '15:00', subtasks: const [
        Subtask(id: 'a', title: 'חיבור מקרן', isDone: true),
        Subtask(id: 'b', title: 'סידור כיסאות'),
        Subtask(id: 'c', title: 'בדיקת מיקרופון'),
      ]),
    );

    expect(find.text('הכנת חדר סדנה 2'), findsOneWidget);
    expect(find.text('התייצבות ${ltr('15:00')}'), findsOneWidget);
    expect(find.text(ltr('1/3')), findsOneWidget);
  });

  testWidgets('an untimed task says ללא שעה', (tester) async {
    await pumpRow(tester, task(at: null));

    expect(find.text('ללא שעה'), findsOneWidget);
  });

  testWidgets('a late task carries the red באיחור mark', (tester) async {
    await pumpRow(tester, task(at: '13:00'));

    expect(
      find.descendant(
        of: find.byKey(const Key('task-row-late-t1')),
        matching: find.text('באיחור'),
      ),
      findsOneWidget,
    );
    expect(
      styleOf(tester, find.text('התייצבות ${ltr('13:00')}')).color,
      TaskStyle.lateDark,
    );
  });

  testWidgets('a task due in the half hour shows its time in orange, no countdown',
      (tester) async {
    await pumpRow(tester, task(at: '15:00'));

    expect(
      styleOf(tester, find.text('התייצבות ${ltr('15:00')}')).color,
      TaskStyle.soonDark,
    );
    expect(find.byKey(const Key('task-row-late-t1')), findsNothing);
    expect(find.textContaining('בעוד'), findsNothing);
  });

  testWidgets('a task without subtasks ticks through its box', (tester) async {
    await pumpRow(tester, task());

    await tester.tap(find.byKey(const Key('task-row-tick-t1')));
    expect(completions, [true]);
    expect(opens, 0);
  });

  testWidgets('someone who may not tick gets a disabled box', (tester) async {
    await pumpRow(tester, task(), canTick: false);

    expect(
      tester.widget<Checkbox>(find.byKey(const Key('task-row-tick-t1'))).onChanged,
      isNull,
    );
  });

  testWidgets('a task with subtasks has no tick box', (tester) async {
    await pumpRow(
      tester,
      task(subtasks: const [Subtask(id: 'a', title: 'טופס')]),
    );

    expect(find.byKey(const Key('task-row-tick-t1')), findsNothing);
  });

  testWidgets('a done task is struck through', (tester) async {
    await pumpRow(tester, task(isComplete: true));

    expect(
      styleOf(tester, find.text('חלוקת ערכות למשתתפים')).decoration,
      TextDecoration.lineThrough,
    );
  });

  testWidgets('an assignee with a phone gets a call button, one without does not',
      (tester) async {
    await pumpRow(tester, task(assigneeIds: const ['m1', 'm2']));

    await tester.tap(find.byKey(const Key('task-row-call-t1-m1')));
    expect(calls, ['0501234567']);
    expect(find.byKey(const Key('task-row-call-t1-m2')), findsNothing);
    expect(opens, 0);
  });

  testWidgets('the viewer\'s own chip is filled in the mine colour',
      (tester) async {
    await pumpRow(tester, task(assigneeIds: const ['m1', 'm2']));

    BoxDecoration chip(String memberId) => tester
        .widget<Container>(find.byKey(Key('task-row-assignee-t1-$memberId')))
        .decoration! as BoxDecoration;
    expect(chip('m1').color, TaskStyle.mine);
    expect(chip('m2').color, isNot(TaskStyle.mine));
  });

  testWidgets('a removed assignee is struck through in red, with the note',
      (tester) async {
    await pumpRow(
      tester,
      task(assigneeIds: const ['m1', 'm2', 'gone']),
      removedAssigneeIds: const ['m2', 'gone'],
    );

    final yoavStyle = styleOf(tester, find.text('יואב'));
    expect(yoavStyle.decoration, TextDecoration.lineThrough);
    expect(yoavStyle.color, TaskStyle.lateDark);
    expect(find.text('חבר צוות שנמחק'), findsOneWidget);
    expect(find.text('כבר לא משובץ לאירוע'), findsNWidgets(2));
    expect(
      styleOf(tester, find.text('דנה')).decoration,
      isNot(TextDecoration.lineThrough),
    );
  });

  testWidgets('the update line shows the note, its author and its time',
      (tester) async {
    await pumpRow(
      tester,
      task(
        update: 'מחכים למקרן',
        updateBy: 'נועה לוי',
        updateAt: DateTime(2026, 10, 20, 14, 22),
      ),
    );

    expect(find.text('מחכים למקרן · נועה לוי, ${ltr('14:22')}'), findsOneWidget);
  });

  testWidgets('an update from another day carries its date', (tester) async {
    await pumpRow(
      tester,
      task(
        update: 'הוזמן',
        updateBy: 'דנה',
        updateAt: DateTime(2026, 10, 18, 9, 5),
      ),
    );

    expect(find.text('הוזמן · דנה, ${ltr('18/10 09:05')}'), findsOneWidget);
  });

  testWidgets('pressing the row opens the task', (tester) async {
    await pumpRow(tester, task());

    await tester.tap(find.text('חלוקת ערכות למשתתפים'));
    expect(opens, 1);
    expect(completions, isEmpty);
  });

  testWidgets('an 80-character title on a 320 px phone ends in an ellipsis',
      (tester) async {
    final title = 'משימה ארוכה מאוד ' * 5;
    await pumpRow(
      tester,
      task(title: title, assigneeIds: const ['m1', 'm2']),
      size: const Size(320, 640),
    );

    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.text(title));
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
  });
}
