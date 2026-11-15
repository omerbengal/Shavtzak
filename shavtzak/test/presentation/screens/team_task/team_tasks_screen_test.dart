import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/theme/app_theme.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_task.dart';
import 'package:shavtzak/presentation/screens/task/task_style.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';
import '../../../support/team_tasks_harness.dart';

void main() {
  final dana = buildMember(id: 'm1', name: 'דנה');
  final yossi = buildMember(id: 'm2', name: 'יוסי');
  final manager = buildMember(id: 'mgr', name: 'מנהלת', isAdmin: true);

  TeamTaskBoard board(List<TeamTask> tasks) => TeamTaskBoard(
        tasks: tasks,
        members: [dana, yossi, manager],
        topics: [buildTopic()],
        categories: [buildCategory()],
      );

  final mine = buildTeamTask(id: 'a', title: 'להזמין אולם', assigneeIds: ['m1'])
      .copyWith(owners: [dana]);

  testWidgets('owner sees no FAB and no all-tasks tab', (tester) async {
    await pumpTeamTasks(tester, user: dana, board: board([mine]));
    expect(find.byKey(const Key('team-task-new')), findsNothing);
    expect(find.text('כל המשימות'), findsNothing);
    expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
  });

  testWidgets('manager sees both', (tester) async {
    final theirs = buildTeamTask(id: 'b', title: 'של יוסי', assigneeIds: ['m2'])
        .copyWith(owners: [yossi]);
    await pumpTeamTasks(tester, user: manager, board: board([mine, theirs]));
    expect(find.byKey(const Key('team-task-new')), findsOneWidget);
    expect(find.text('כל המשימות'), findsOneWidget);
    // A manager opens on every task.
    expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
    expect(find.byKey(const Key('team-task-row-b')), findsOneWidget);
    await tester.tap(find.text('המשימות שלי'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-task-row-a')), findsNothing);
  });

  testWidgets('tabs as in דו יומי: "המשימות שלי" on the right, the chosen one readable', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board([mine]));
    final mineTab = tester.getCenter(find.byKey(const Key('team-tab-mine')));
    final allTab = tester.getCenter(find.byKey(const Key('team-tab-all')));
    expect(mineTab.dx, greaterThan(allTab.dx));
    // The same segmented switch as the דו יומי event screen, white on dark blue.
    final tabs = tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>));
    final selected = {WidgetState.selected};
    expect(tabs.style?.foregroundColor?.resolve(selected), Colors.white);
    expect(tabs.style?.backgroundColor?.resolve(selected), AppTheme.primaryDark);
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('late deadline is red', (tester) async {
    final late = buildTeamTask(id: 'l', title: 'באיחור', deadline: '2026-11-10').copyWith(owners: [dana]);
    final fine = buildTeamTask(id: 'f', title: 'בזמן', deadline: '2026-11-20').copyWith(owners: [dana]);
    await pumpTeamTasks(tester, user: dana, board: board([late, fine]));
    Text deadline(String id) => tester.widget<Text>(find.byKey(Key('team-task-deadline-$id')));
    expect(deadline('l').style?.color, TaskStyle.late);
    expect(deadline('f').style?.color, isNot(TaskStyle.late));
    expect(deadline('l').data, contains('10.11'));
  });

  testWidgets('new task saves with a topic link', (tester) async {
    final harness = await pumpTeamTasks(tester, user: manager, board: board(const []));
    await tester.tap(find.byKey(const Key('team-task-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-team-task-title')), 'לסגור להקה');
    await tester.tap(find.byKey(const Key('new-team-task-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('נושא'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-link-option-p1')));
    await tester.pumpAndSettle();
    expect(find.text('נשות מגדים'), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-team-task-save')));
    await tester.pumpAndSettle();
    final saved = harness.repository.inserted.single;
    expect(saved.title, 'לסגור להקה');
    expect(saved.link, const TaskLink(TaskLinkType.topic, 'p1'));
    expect(saved.status, TeamTaskStatus.open);
  });

  testWidgets('the link picker reads well: dark segments, roomy lines, the current one not blue',
      (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board(const []));
    await tester.tap(find.byKey(const Key('team-task-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-team-task-link')));
    await tester.pumpAndSettle();
    final segments =
        tester.widget<SegmentedButton<TaskLinkType>>(find.byType(SegmentedButton<TaskLinkType>));
    expect(segments.style?.foregroundColor?.resolve({WidgetState.selected}), Colors.white);
    expect(segments.style?.backgroundColor?.resolve({WidgetState.selected}), AppTheme.primaryDark);
    await tester.tap(find.text('נושא'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('task-link-option-p1')));
    await tester.pumpAndSettle();
    // Open again: the chosen topic is marked in words, in the normal colour.
    await tester.tap(find.byKey(const Key('new-team-task-link')));
    await tester.pumpAndSettle();
    final option = find.byKey(const Key('task-link-option-p1'));
    expect(find.descendant(of: option, matching: find.text('השיוך הנוכחי')), findsOneWidget);
    final name = tester.widget<Text>(find.descendant(of: option, matching: find.text('נשות מגדים')));
    expect(name.style?.fontSize, 16);
    expect(name.style?.color, isNull);
    expect(find.descendant(of: option, matching: find.byType(ListTile)), findsNothing);
  });

  testWidgets('a new task needs a title', (tester) async {
    final harness = await pumpTeamTasks(tester, user: manager, board: board(const []));
    await tester.tap(find.byKey(const Key('team-task-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-team-task-save')));
    await tester.pumpAndSettle();
    expect(find.text('חובה להזין כותרת'), findsOneWidget);
    expect(harness.repository.inserted, isEmpty);
  });

  testWidgets('a new task is filled in full before it exists: owners, contacts, subtasks',
      (tester) async {
    final harness = await pumpTeamTasks(tester,
        user: manager, board: board(const []), size: const Size(1200, 1000));
    await tester.tap(find.byKey(const Key('team-task-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-team-task-title')), 'להזמין אולם');

    // Contacts.
    await tester.tap(find.byKey(const Key('new-team-task-add-contact')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('edit-contact-name-0')), 'רונית');
    await tester.enterText(find.byKey(const Key('edit-contact-phone-0')), '0501234567');

    // Two subtasks, typed as in דו יומי: Enter opens the next line.
    await tester.ensureVisible(find.byKey(const Key('team-subtask-add')));
    await tester.tap(find.byKey(const Key('team-subtask-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('team-subtask-title-0')), 'הצעת מחיר');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('team-subtask-title-1')), 'חוזה');
    await tester.tap(find.byKey(const Key('team-subtask-owner-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-subtask-owner-option-m2')).last);
    await tester.pumpAndSettle();
    // With subtasks the owners are theirs: no own owners field.
    expect(find.byKey(const Key('new-team-task-owners')), findsNothing);

    await tester.tap(find.byKey(const Key('new-team-task-save')));
    await tester.pumpAndSettle();
    final saved = harness.repository.inserted.single;
    expect(saved.title, 'להזמין אולם');
    expect(saved.contacts.single.name, 'רונית');
    expect(saved.subtasks.map((s) => s.title), ['הצעת מחיר', 'חוזה']);
    expect(saved.subtasks.last.assigneeId, 'm2');
    expect(saved.ownerIds, ['m2']);
  });

  testWidgets('a new task without subtasks picks its owners in the form', (tester) async {
    final harness = await pumpTeamTasks(tester,
        user: manager, board: board(const []), size: const Size(1200, 1000));
    await tester.tap(find.byKey(const Key('team-task-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-team-task-title')), 'לסגור להקה');
    await tester.tap(find.byKey(const Key('new-team-task-owners')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-assignee-m1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-team-task-save')));
    await tester.pumpAndSettle();
    expect(harness.repository.inserted.single.ownerIds, ['m1']);
  });

  testWidgets('an empty list says so', (tester) async {
    await pumpTeamTasks(tester, user: dana, board: board(const []));
    expect(find.text('אין משימות להצגה'), findsOneWidget);
  });
}
