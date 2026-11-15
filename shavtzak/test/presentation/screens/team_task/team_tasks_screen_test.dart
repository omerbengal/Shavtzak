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

    // Two subtasks, each in the same form as a task (round 2).
    Future<void> addSubtask(String title, {String? ownerId}) async {
      await tester.ensureVisible(find.byKey(const Key('new-team-task-add-subtask')));
      await tester.tap(find.byKey(const Key('new-team-task-add-subtask')));
      await tester.pumpAndSettle();
      expect(find.text('תת-משימה חדשה'), findsOneWidget);
      // The subtask form has no link: it belongs where its parent does.
      expect(find.byKey(const Key('new-team-task-link')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('new-team-task-title')).last, title);
      // No contact line appears by itself while typing (bug 6).
      expect(find.byKey(const Key('edit-contact-name-0')), findsOneWidget);
      if (ownerId != null) {
        await tester.tap(find.byKey(const Key('new-team-task-owners')).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('edit-assignee-$ownerId')).last);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const Key('new-team-task-save')).last);
      await tester.pumpAndSettle();
    }

    await addSubtask('הצעת מחיר');
    // The parent's title changes once it has a subtask.
    expect(find.text('משימת אב חדשה'), findsOneWidget);
    await addSubtask('חוזה', ownerId: 'm2');
    // With subtasks the owners are theirs: no own owners field.
    expect(find.byKey(const Key('new-team-task-owners')), findsNothing);

    await tester.tap(find.byKey(const Key('new-team-task-save')));
    await tester.pumpAndSettle();
    final saved = harness.repository.inserted.single;
    expect(saved.title, 'להזמין אולם');
    expect(saved.contacts.single.name, 'רונית');
    expect(saved.subtasks.map((s) => s.title), ['הצעת מחיר', 'חוזה']);
    expect(saved.subtasks.last.assigneeIds, ['m2']);
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

  testWidgets('a first subtask on a task with owners asks what to do', (tester) async {
    await pumpTeamTasks(tester,
        user: manager, board: board(const []), size: const Size(1200, 1000));
    await tester.tap(find.byKey(const Key('team-task-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-team-task-title')), 'להזמין אולם');
    await tester.tap(find.byKey(const Key('new-team-task-owners')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-assignee-m1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('new-team-task-add-subtask')));
    await tester.tap(find.byKey(const Key('new-team-task-add-subtask')));
    await tester.pumpAndSettle();
    // "להשאיר כמשימה אחת": nothing changes.
    await tester.tap(find.byKey(const Key('first-subtask-keep')));
    await tester.pumpAndSettle();
    expect(find.text('תת-משימה חדשה'), findsNothing);
    expect(find.byKey(const Key('new-team-task-owners')), findsOneWidget);
    // "ליצור תתי-משימות ולהסיר את האחראים": the subtask form opens.
    await tester.tap(find.byKey(const Key('new-team-task-add-subtask')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('first-subtask-split')));
    await tester.pumpAndSettle();
    expect(find.text('תת-משימה חדשה'), findsOneWidget);
  });

  testWidgets('"המשימות שלי" lists my subtask as its own row under the parent title',
      (tester) async {
    final parent = buildTeamTask(id: 'p', title: 'אולם', subtasks: [
      TeamSubtask(id: 's1', title: 'הצעת מחיר', assigneeIds: const ['m1'], assignees: [dana]),
      const TeamSubtask(id: 's2', title: 'חוזה', assigneeIds: ['m2']),
    ]);
    await pumpTeamTasks(tester, user: dana, board: board([parent]));
    expect(find.byKey(const Key('team-task-row-s1')), findsOneWidget);
    expect(find.byKey(const Key('team-task-parent-s1')), findsOneWidget);
    expect(find.text('אולם'), findsOneWidget);
    expect(find.byKey(const Key('team-task-row-p')), findsNothing);
    expect(find.byKey(const Key('team-task-row-s2')), findsNothing);
  });

  testWidgets('"כל המשימות" folds the subtasks under their parent, "2/4 ▾" opens them', (tester) async {
    final parent = buildTeamTask(id: 'p', title: 'אולם', subtasks: const [
      TeamSubtask(id: 's1', title: 'הצעת מחיר', assigneeIds: ['m1']),
      TeamSubtask(id: 's2', title: 'חוזה', assigneeIds: ['m2']),
    ]);
    await pumpTeamTasks(tester, user: manager, board: board([parent]));
    await tester.tap(find.byKey(const Key('team-tab-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-task-row-s1')), findsNothing);
    await tester.tap(find.byKey(const Key('team-task-progress-p')));
    await tester.pumpAndSettle();
    final parentTop = tester.getTopLeft(find.byKey(const Key('team-task-row-p'))).dy;
    expect(tester.getTopLeft(find.byKey(const Key('team-task-row-s1'))).dy, greaterThan(parentTop));
    expect(find.byKey(const Key('team-task-row-s2')), findsOneWidget);
  });

  group('round 3', () {
    final theirs = buildTeamTask(id: 'b', title: 'של יוסי', assigneeIds: ['m2'])
        .copyWith(owners: [yossi]);
    final managersOwn = buildTeamTask(id: 'c', title: 'של המנהלת', assigneeIds: ['mgr'])
        .copyWith(owners: [manager]);

    Future<void> openMine(WidgetTester tester) async {
      await tester.tap(find.text('המשימות שלי'));
      await tester.pumpAndSettle();
    }

    testWidgets('"המשימות שלי" has no owner filter; "כל המשימות" has it', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([mine, managersOwn]));
      expect(find.byKey(const Key('team-filter-owner')), findsOneWidget);
      await openMine(tester);
      expect(find.byKey(const Key('team-filter-owner')), findsNothing);
      expect(find.byKey(const Key('team-filter-status')), findsOneWidget);
    });

    testWidgets('an owner filter colours only the owner chip, not the status chip', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([mine, theirs]));
      await tester.tap(find.byKey(const Key('team-filter-owner')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('יוסי').last);
      await tester.pumpAndSettle();
      Color? fill(String key) {
        final box = tester.widget<Container>(find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(Container),
        ).first);
        return (box.decoration as BoxDecoration?)?.color;
      }
      expect(fill('team-filter-owner'), TaskStyle.currentLight);
      expect(fill('team-filter-status'), Colors.transparent);
    });

    testWidgets('a manager in "המשימות שלי" gets the view of a member', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([managersOwn]));
      await openMine(tester);
      expect(find.byKey(const Key('team-task-new')), findsNothing);
      expect(find.byKey(const Key('team-tasks-menu')), findsNothing);
      await tester.tap(find.byKey(const Key('team-task-row-c')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-panel')), findsOneWidget);
      expect(find.byKey(const Key('team-task-edit-title')), findsNothing);
      expect(find.byKey(const Key('team-task-delete')), findsNothing);
    });

    testWidgets('a manager in "כל המשימות" gets the editing view', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([managersOwn]));
      await tester.tap(find.byKey(const Key('team-task-row-c')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-edit-title')), findsOneWidget);
    });

    testWidgets('the search folds the chips into a funnel and filters', (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([mine, theirs]));
      expect(find.byKey(const Key('team-filter-funnel')), findsNothing);
      await tester.tap(find.byKey(const Key('team-filter-search')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-filter-funnel')), findsOneWidget);
      expect(find.byKey(const Key('team-filter-status')), findsNothing);
      await tester.enterText(find.byKey(const Key('team-filter-search')), 'יוסי');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-row-a')), findsNothing);
      expect(find.byKey(const Key('team-task-row-b')), findsOneWidget);

      // The funnel's menu holds the three filters as rows.
      await tester.tap(find.byKey(const Key('team-filter-funnel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-filter-menu-status')), findsOneWidget);
      expect(find.byKey(const Key('team-filter-menu-owner')), findsOneWidget);
      expect(find.byKey(const Key('team-filter-menu-link')), findsOneWidget);
      await tester.tap(find.byKey(const Key('team-filter-menu-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-filter-menu-status-open')).first);
      await tester.pumpAndSettle();
      // "פתוחה" unticked: both open tasks go.
      expect(find.byKey(const Key('team-task-row-b')), findsNothing);
      final funnel = tester.widget<Icon>(find.descendant(
        of: find.byKey(const Key('team-filter-funnel')),
        matching: find.byType(Icon),
      ));
      expect(funnel.icon, Icons.filter_alt);

      // Clearing the search brings the chips back.
      await tester.tapAt(const Offset(200, 900));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-filter-search-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-filter-funnel')), findsNothing);
      expect(find.byKey(const Key('team-filter-status')), findsOneWidget);
    });

    testWidgets('a search that matches a subtask opens its parent', (tester) async {
      final parent = buildTeamTask(id: 'p', title: 'אולם', subtasks: const [
        TeamSubtask(id: 's1', title: 'הצעת מחיר', assigneeIds: ['m1']),
        TeamSubtask(id: 's2', title: 'חוזה', assigneeIds: ['m2']),
      ]);
      await pumpTeamTasks(tester, user: manager, board: board([parent]));
      await tester.enterText(find.byKey(const Key('team-filter-search')), 'חוזה');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('team-task-row-s2')), findsOneWidget);
      expect(find.byKey(const Key('team-task-row-s1')), findsNothing);
    });

    testWidgets('a row shows the status circle and the initials of the owners', (tester) async {
      final omer = buildMember(id: 'o1', name: 'עומר בנגל');
      final task = buildTeamTask(id: 'x', title: 'משימה', assigneeIds: ['o1'], status: TeamTaskStatus.inProgress)
          .copyWith(owners: [omer]);
      await pumpTeamTasks(tester, user: omer, board: board([task]));
      expect(find.byKey(const Key('team-status-icon-inProgress')), findsOneWidget);
      expect(find.text('עב'), findsOneWidget);
    });
  });
}
