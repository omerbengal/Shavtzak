import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/task_topic.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';
import '../../../support/team_tasks_harness.dart';

/// Omer's round 10 (msg 3789): the update log can be edited, the new-task
/// form's order, a subtask as one line, "+" on a card, "אירוע שעוד לא נוצר"
/// and the event's assignments window from its card.
void main() {
  final dana = buildMember(id: 'm1', name: 'דנה');
  final yossi = buildMember(id: 'm2', name: 'יוסי');
  final manager = buildMember(id: 'mgr', name: 'מנהלת', isAdmin: true);
  final at = DateTime(2026, 11, 10, 9);
  const pending = TaskTopic(id: 'pe1', name: 'חנוכה 2027');
  final topicLink = const TaskLink(TaskLinkType.topic, 'p1');

  TeamTaskBoard board(List<TeamTask> tasks) => TeamTaskBoard(
        tasks: tasks,
        members: [dana, yossi, manager],
        topics: [buildTopic()],
        pendingEvents: const [pending],
      );

  final logged = buildTeamTask(
    id: 'a',
    title: 'להזמין אולם',
    assigneeIds: ['m1', 'mgr'],
    link: topicLink,
    updates: [
      TaskUpdateEntry(id: 'u-yossi', text: 'של יוסי', at: at, byId: 'm2', byName: 'יוסי'),
      TaskUpdateEntry(
          id: 'u-dana', text: 'של דנה', at: at, byId: 'm1', byName: 'דנה', editedAt: at),
      TaskUpdateEntry(id: 'u-excel', text: 'ישן', at: at, byId: '', byName: 'מהאקסל'),
      TaskUpdateEntry(id: 'u-mgr', text: 'של המנהלת', at: at, byId: 'mgr', byName: 'מנהלת'),
    ],
  ).copyWith(owners: [dana, manager], topic: () => buildTopic());

  Future<void> openTask(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key('team-task-row-$id')));
    await tester.pumpAndSettle();
  }

  Finder menuOf(String id) => find.byKey(Key('team-task-log-menu-$id'));

  group('update log', () {
    testWidgets('an owner edits and deletes only their own updates', (tester) async {
      final harness = await pumpTeamTasks(tester, user: dana, board: board([logged]));
      await openTask(tester, 'a');
      expect(menuOf('u-dana'), findsOneWidget);
      expect(menuOf('u-yossi'), findsNothing);
      expect(menuOf('u-excel'), findsNothing);
      expect(find.textContaining('(נערך)'), findsOneWidget);

      await tester.tap(menuOf('u-dana'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-task-log-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('team-task-log-edit-field')), 'דנה מתקנת');
      await tester.tap(find.byKey(const Key('team-task-log-edit-save')));
      await tester.pumpAndSettle();
      expect(harness.repository.calls, contains('editLog:a:u-dana:דנה מתקנת'));

      await tester.tap(menuOf('u-dana'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-task-log-delete')));
      await tester.pumpAndSettle();
      expect(harness.repository.calls.where((c) => c.startsWith('deleteLog')), isEmpty);
      await tester.tap(find.byKey(const Key('team-task-log-delete-confirm')));
      await tester.pumpAndSettle();
      expect(harness.repository.calls, contains('deleteLog:a:u-dana'));
    });

    testWidgets('a manager changes everyone\'s in "כל המשימות", only theirs in "המשימות שלי"',
        (tester) async {
      await pumpTeamTasks(tester, user: manager, board: board([logged]));
      await openTask(tester, 'a');
      for (final id in ['u-yossi', 'u-dana', 'u-excel', 'u-mgr']) {
        expect(menuOf(id), findsOneWidget, reason: id);
      }
      await tester.tap(find.byKey(const Key('team-task-close')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('team-tab-mine')));
      await tester.pumpAndSettle();
      await openTask(tester, 'a');
      expect(menuOf('u-mgr'), findsOneWidget);
      for (final id in ['u-yossi', 'u-dana', 'u-excel']) {
        expect(menuOf(id), findsNothing, reason: id);
      }
    });
  });

  group('new task form', () {
    testWidgets('the order: link, title, description, owners, deadline', (tester) async {
      await pumpTeamTasks(tester,
          user: manager, board: board(const []), size: const Size(1200, 1000));
      await tester.tap(find.byKey(const Key('team-task-new')));
      await tester.pumpAndSettle();
      double top(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
      expect(top('new-team-task-link'), lessThan(top('new-team-task-title')));
      expect(top('new-team-task-title'), lessThan(top('new-team-task-description')));
      expect(top('new-team-task-description'), lessThan(top('new-team-task-owners')));
      expect(top('new-team-task-owners'), lessThan(top('new-team-task-deadline')));
    });

    testWidgets('a subtask is one line of text, no description', (tester) async {
      await pumpTeamTasks(tester,
          user: manager, board: board(const []), size: const Size(1200, 1000));
      await tester.tap(find.byKey(const Key('team-task-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-team-task-add-subtask')));
      await tester.pumpAndSettle();
      expect(find.text('תת-משימה חדשה'), findsOneWidget);
      // The subtask form sits on top of the task's form: one title field
      // each, and only the task's description.
      expect(find.byKey(const Key('new-team-task-description')), findsOneWidget);
      expect(find.byKey(const Key('new-team-task-title')), findsNWidgets(2));
      expect(find.widgetWithText(TextField, 'תת-משימה'), findsOneWidget);
    });

    testWidgets('a description saved before stays readable on the subtask', (tester) async {
      final parent = buildTeamTask(id: 'p', title: 'דו יומי', subtasks: const [
        TeamSubtask(
            id: 's1', title: 'לשלוח לוז', description: 'מחזור 12.11', assigneeIds: ['m1']),
      ]).copyWith(owners: [dana]);
      await pumpTeamTasks(tester, user: dana, board: board([parent]));
      await openTask(tester, 's1');
      expect(find.byKey(const Key('team-task-legacy-description')), findsOneWidget);
      expect(find.text('מחזור 12.11'), findsOneWidget);
      expect(find.byKey(const Key('team-task-edit-description')), findsNothing);
    });
  });

  group('cards', () {
    testWidgets('"+" on a card opens a new task already linked to it', (tester) async {
      final harness = await pumpTeamTasks(tester, user: manager, board: board([logged]));
      await tester.tap(find.byKey(const Key('team-task-group-add-topic:p1')));
      await tester.pumpAndSettle();
      expect(find.text('נשות מגדים'), findsWidgets);
      await tester.enterText(find.byKey(const Key('new-team-task-title')), 'עוד משימה');
      await tester.tap(find.byKey(const Key('new-team-task-save')));
      await tester.pumpAndSettle();
      expect(harness.repository.inserted.single.link, topicLink);
    });

    testWidgets('a member gets no "+" on a card', (tester) async {
      await pumpTeamTasks(tester, user: dana, board: board([logged]));
      expect(find.byKey(const Key('team-task-group-add-topic:p1')), findsNothing);
    });

    testWidgets('👥 on an event card only for who sees "מסך מנהלים"', (tester) async {
      final event = buildEvent(id: 'e1', name: 'ערב הוקרה');
      final onEvent = buildTeamTask(
        id: 'ev',
        assigneeIds: ['m1'],
        link: const TaskLink(TaskLinkType.event, 'e1'),
      ).copyWith(owners: [dana], event: () => event);
      await pumpTeamTasks(tester, user: manager, board: board([onEvent, logged]));
      expect(find.byKey(const Key('team-task-group-assignments-event:e1')), findsOneWidget);
      expect(find.byKey(const Key('team-task-group-assignments-topic:p1')), findsNothing);
    });

    testWidgets('👥 not for a member without "מסך מנהלים"', (tester) async {
      final event = buildEvent(id: 'e1', name: 'ערב הוקרה');
      final onEvent = buildTeamTask(
        id: 'ev',
        assigneeIds: ['m1'],
        link: const TaskLink(TaskLinkType.event, 'e1'),
      ).copyWith(owners: [dana], event: () => event);
      await pumpTeamTasks(tester, user: dana, board: board([onEvent]));
      expect(find.byKey(const Key('team-task-group-assignments-event:e1')), findsNothing);
    });
  });

  group('אירוע שעוד לא נוצר', () {
    final onPending = buildTeamTask(
      id: 'pt',
      title: 'להזמין להקה',
      assigneeIds: ['m1'],
      link: const TaskLink(TaskLinkType.pendingEvent, 'pe1'),
    ).copyWith(owners: [dana], pendingEvent: () => pending);

    testWidgets('its card reads its name and offers the link to the real event',
        (tester) async {
      final event = buildEvent(id: 'e1', name: 'חנוכה', startDate: DateTime(2027, 12, 5));
      final harness = await pumpTeamTasks(
        tester,
        user: manager,
        board: TeamTaskBoard(
          tasks: [onPending],
          members: [dana, manager],
          events: [event],
          pendingEvents: const [pending],
        ),
      );
      expect(find.text('אירוע שעוד לא נוצר · חנוכה 2027'), findsOneWidget);
      await tester.tap(find.byKey(const Key('team-task-group-link-pending-pendingEvent:pe1')));
      await tester.pumpAndSettle();
      // Only real events, no segments, no placeholders.
      expect(find.byKey(const Key('task-link-option-pe1')), findsNothing);
      await tester.tap(find.byKey(const Key('task-link-option-e1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('link-pending-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('link-pending-confirm-button')));
      await tester.pumpAndSettle();
      expect(harness.repository.calls, contains('linkPending:pe1:e1'));
    });

    testWidgets('the events list starts with it: a manager names a new one', (tester) async {
      final harness = await pumpTeamTasks(tester, user: manager, board: board(const []));
      await tester.tap(find.byKey(const Key('team-task-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-team-task-link')));
      await tester.pumpAndSettle();
      // The existing placeholder is listed, and the entry for a new one.
      expect(find.byKey(const Key('task-link-option-pe1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('task-link-pending-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('task-link-pending-name')), 'פורים');
      await tester.tap(find.byKey(const Key('task-link-pending-add')));
      await tester.pumpAndSettle();
      expect(harness.repository.calls, contains('insertPending:פורים'));
    });
  });
}
