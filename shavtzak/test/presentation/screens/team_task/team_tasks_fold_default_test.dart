import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_task.dart';
import 'package:shavtzak/presentation/screens/team_task/widgets/team_task_sheet.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';
import '../../../support/team_tasks_harness.dart';

/// Omer, msg 4466: in "כל המשימות" the cards open folded to their header;
/// "המשימות שלי" (and "בליץ") keep every card open. A card opened or folded
/// by hand stays so while the screen is open.
void main() {
  final manager = buildMember(id: 'mgr', name: 'מנהלת', isAdmin: true);
  final dana = buildMember(id: 'm1', name: 'דנה');
  const topic1 = TaskLink(TaskLinkType.topic, 'p1');
  const topic2 = TaskLink(TaskLinkType.topic, 'p2');

  final own = buildTeamTask(id: 'a', title: 'להזמין אולם', link: topic1, assigneeIds: ['mgr'])
      .copyWith(owners: [manager]);
  final other = buildTeamTask(id: 'b', title: 'לסדר ציוד', link: topic2, assigneeIds: ['m1'])
      .copyWith(owners: [dana]);

  TeamTaskBoard board() => TeamTaskBoard(
        tasks: [own, other],
        members: [manager, dana],
        topics: [buildTopic(), buildTopic(id: 'p2', name: 'חנוכה')],
        categories: [buildCategory()],
      );

  Finder row(String id) => find.byKey(Key('team-task-row-$id'));
  Finder group(String key) => find.byKey(Key('team-task-group-$key'));

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('"כל המשימות" opens folded, "המשימות שלי" open', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board(), foldAllTab: true);
    await tester.pumpAndSettle();
    expect(group('topic:p1'), findsOneWidget);
    expect(group('topic:p2'), findsOneWidget);
    expect(row('a'), findsNothing);
    expect(row('b'), findsNothing);
    expect(find.byTooltip('פתיחת כל השיוכים'), findsOneWidget);
    await tap(tester, find.text('המשימות שלי'));
    expect(row('a'), findsOneWidget);
  });

  testWidgets('a card opened or folded by hand stays so across the tabs', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board(), foldAllTab: true);
    await tester.pumpAndSettle();
    await tap(tester, group('topic:p2'));
    expect(row('b'), findsOneWidget);
    expect(row('a'), findsNothing);
    // "המשימות שלי": its own default (open), folded here by hand.
    await tap(tester, find.text('המשימות שלי'));
    expect(row('a'), findsOneWidget);
    await tap(tester, group('topic:p1'));
    expect(row('a'), findsNothing);
    await tap(tester, find.text('כל המשימות'));
    expect(row('b'), findsOneWidget);
    expect(row('a'), findsNothing);
    await tap(tester, find.text('המשימות שלי'));
    expect(row('a'), findsNothing);
  });

  testWidgets('the app bar button opens and folds every card of "כל המשימות"', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board(), foldAllTab: true);
    await tester.pumpAndSettle();
    await tap(tester, find.byKey(const Key('team-tasks-fold-all')));
    expect(row('a'), findsOneWidget);
    expect(row('b'), findsOneWidget);
    await tap(tester, find.byKey(const Key('team-tasks-fold-all')));
    expect(row('a'), findsNothing);
    expect(row('b'), findsNothing);
  });

  testWidgets('a member with no "כל המשימות" sees every card open', (tester) async {
    await pumpTeamTasks(tester, user: dana, board: board(), foldAllTab: true);
    await tester.pumpAndSettle();
    expect(row('b'), findsOneWidget);
  });

  testWidgets('a link to a task in a folded card opens it, and its card opens too',
      (tester) async {
    await pumpTeamTasks(tester,
        user: manager, board: board(), openTaskId: 'b', foldAllTab: true, size: teamWideSize);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('team-task-panel-b')), findsOneWidget);
    expect(row('b'), findsOneWidget);
    expect(row('a'), findsNothing);
  });

  testWidgets('on a phone the linked task opens over the list', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board(), openTaskId: 'b', foldAllTab: true);
    await tester.pumpAndSettle();
    expect(tester.widget<TeamTaskSheet>(find.byType(TeamTaskSheet)).taskId, 'b');
  });
}
