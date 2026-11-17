import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';
import '../../../support/team_tasks_harness.dart';

/// Omer, msg 4476: on a wide window the task open in the side panel keeps
/// its place in the list while it stays open. A change that would move it
/// (its link, urgency, status, owners) shows on its row, and it moves only
/// once the panel closes (X) or another task is chosen. Other tasks move as
/// usual; a phone is unchanged.
void main() {
  final manager = buildMember(id: 'mgr', name: 'מנהלת', isAdmin: true);
  final dana = buildMember(id: 'm1', name: 'דנה');
  const topic1 = TaskLink(TaskLinkType.topic, 'p1');
  const topic2 = TaskLink(TaskLinkType.topic, 'p2');

  TeamTask task(String id, String title, TaskLink link,
          {List<String> owners = const ['mgr'],
          TeamTaskUrgency urgency = TeamTaskUrgency.normal}) =>
      buildTeamTask(id: id, title: title, link: link, assigneeIds: owners, urgency: urgency)
          .copyWith(owners: [for (final o in owners) o == 'mgr' ? manager : dana]);

  final a = task('a', 'להזמין אולם', topic1);
  final b = task('b', 'לסדר ציוד', topic2);
  final c = task('c', 'לקנות כיבוד', topic2);

  TeamTaskBoard board(List<TeamTask> tasks) => TeamTaskBoard(
        tasks: tasks,
        members: [manager, dana],
        topics: [buildTopic(), buildTopic(id: 'p2', name: 'חנוכה')],
        categories: [buildCategory()],
      );

  Finder rowIn(String id, String groupKey) => find.descendant(
      of: find.byKey(Key('team-task-card-$groupKey')),
      matching: find.byKey(Key('team-task-row-$id')));

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<TeamTasksHarness> openA(WidgetTester tester, {Size size = teamWideSize}) async {
    final harness = await pumpTeamTasks(tester, user: manager, board: board([a, b, c]), size: size);
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('team-task-row-a')));
    return harness;
  }

  // "a" moves to the other topic and gets a high urgency (as a save through
  // the stream brings it).
  final moved = task('a', 'להזמין אולם', topic2, urgency: TeamTaskUrgency.high);

  testWidgets('the open task stays in place, shows its new values, and moves on X', (tester) async {
    final harness = await openA(tester);
    expect(find.byKey(const ValueKey('team-task-panel-a')), findsOneWidget);
    await harness.deliver(tester, board([moved, b, c]));
    await tester.pumpAndSettle();
    expect(rowIn('a', 'topic:p1'), findsOneWidget);
    expect(rowIn('a', 'topic:p2'), findsNothing);
    // Its row already shows the new urgency.
    expect(
        find.descendant(
            of: rowIn('a', 'topic:p1'), matching: find.byKey(const Key('team-task-urgency-a'))),
        findsOneWidget);
    await tap(tester, find.byKey(const Key('team-task-close')));
    expect(rowIn('a', 'topic:p1'), findsNothing);
    expect(rowIn('a', 'topic:p2'), findsOneWidget);
  });

  testWidgets('choosing another task lets it move', (tester) async {
    final harness = await openA(tester);
    await harness.deliver(tester, board([moved, b, c]));
    await tester.pumpAndSettle();
    expect(rowIn('a', 'topic:p1'), findsOneWidget);
    await tap(tester, find.byKey(const Key('team-task-row-b')));
    expect(find.byKey(const ValueKey('team-task-panel-b')), findsOneWidget);
    expect(rowIn('a', 'topic:p2'), findsOneWidget);
    expect(rowIn('a', 'topic:p1'), findsNothing);
  });

  testWidgets('other tasks keep moving while one is held', (tester) async {
    final harness = await openA(tester);
    final cMoved = task('c', 'לקנות כיבוד', topic1);
    await harness.deliver(tester, board([moved, b, cMoved]));
    await tester.pumpAndSettle();
    expect(rowIn('c', 'topic:p1'), findsOneWidget);
    expect(rowIn('a', 'topic:p1'), findsOneWidget);
  });

  testWidgets('in "המשימות שלי" a task no longer mine stays until it is left', (tester) async {
    final harness =
        await pumpTeamTasks(tester, user: manager, board: board([a, b, c]), size: teamWideSize);
    await tester.pumpAndSettle();
    await tap(tester, find.text('המשימות שלי'));
    await tap(tester, find.byKey(const Key('team-task-row-a')));
    // Given to Dana: it is not the manager's any more.
    await harness.deliver(
        tester,
        board([
          task('a', 'להזמין אולם', topic1, owners: ['m1']),
          b,
          c
        ]));
    await tester.pumpAndSettle();
    expect(rowIn('a', 'topic:p1'), findsOneWidget);
    await tap(tester, find.byKey(const Key('team-task-close')));
    expect(find.byKey(const Key('team-task-row-a')), findsNothing);
  });

  testWidgets('a held task that is deleted is gone at once', (tester) async {
    final harness = await openA(tester);
    await harness.deliver(tester, board([b, c]));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-task-row-a')), findsNothing);
  });

  testWidgets('switching tabs lets it go', (tester) async {
    final harness = await openA(tester);
    await harness.deliver(tester, board([moved, b, c]));
    await tester.pumpAndSettle();
    await tap(tester, find.text('המשימות שלי'));
    await tap(tester, find.text('כל המשימות'));
    expect(rowIn('a', 'topic:p2'), findsOneWidget);
    expect(rowIn('a', 'topic:p1'), findsNothing);
  });

  testWidgets('a phone is unchanged: the task moves under the open sheet', (tester) async {
    final harness = await openA(tester, size: teamPhoneSize);
    await harness.deliver(tester, board([moved, b, c]));
    await tester.pumpAndSettle();
    expect(rowIn('a', 'topic:p2'), findsOneWidget);
    expect(rowIn('a', 'topic:p1'), findsNothing);
  });

  testWidgets('with "כל המשימות" folded, an open card keeps the held task', (tester) async {
    final harness = await pumpTeamTasks(tester,
        user: manager, board: board([a, b, c]), size: teamWideSize, foldAllTab: true);
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('team-task-group-topic:p1')));
    await tap(tester, find.byKey(const Key('team-task-row-a')));
    await harness.deliver(tester, board([moved, b, c]));
    await tester.pumpAndSettle();
    expect(rowIn('a', 'topic:p1'), findsOneWidget);
    await tap(tester, find.byKey(const Key('team-task-close')));
    // Its new card is still folded, as it was.
    expect(find.byKey(const Key('team-task-row-a')), findsNothing);
    expect(find.byKey(const Key('team-task-group-topic:p2')), findsOneWidget);
  });
}
