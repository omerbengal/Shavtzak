import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/presentation/screens/team_task/team_tasks_place.dart';
import 'package:shavtzak/presentation/screens/team_task/widgets/team_task_sheet.dart';
import 'package:shavtzak/presentation/widgets/member_bar_buttons.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';
import '../../../support/team_tasks_harness.dart';

/// `#/team-tasks?task=<id>`: the link a "שובצת למשימה" notification opens.
void main() {
  final manager = buildMember(id: 'mgr', name: 'מנהלת', isAdmin: true);
  final task = buildTeamTask(id: 'a', title: 'להזמין אולם', assigneeIds: ['mgr'])
      .copyWith(owners: [manager]);

  TeamTaskBoard board() => TeamTaskBoard(
        tasks: [task],
        members: [manager],
        topics: [buildTopic()],
        categories: [buildCategory()],
      );

  testWidgets('the linked task opens by itself once loaded', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board(), openTaskId: 'a');
    await tester.pumpAndSettle();
    final sheet = tester.widget<TeamTaskSheet>(find.byType(TeamTaskSheet));
    expect(sheet.taskId, 'a');
  });

  testWidgets('wide: the linked task opens in the side panel', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board(), openTaskId: 'a', size: teamWideSize);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('team-task-panel-a')), findsOneWidget);
  });

  testWidgets('a task that is gone says so', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board(), openTaskId: 'gone');
    await tester.pumpAndSettle();
    expect(find.byType(TeamTaskSheet), findsNothing);
    expect(find.text('המשימה לא נמצאה'), findsOneWidget);
  });

  testWidgets('a member who is not a manager: the task opens in the "משימות" tab',
      (tester) async {
    final dana = buildMember(id: 'm1', name: 'דנה');
    final own = buildTeamTask(id: 'b', title: 'לסגור הסעה', assigneeIds: ['m1'])
        .copyWith(owners: [dana]);
    await pumpTeamTasks(tester,
        user: dana,
        board: TeamTaskBoard(tasks: [own], members: [dana], topics: [buildTopic()], categories: [buildCategory()]),
        place: TeamTasksPlace.tab,
        openTaskId: 'b');
    await tester.pumpAndSettle();
    expect(tester.widget<TeamTaskSheet>(find.byType(TeamTaskSheet)).taskId, 'b');
  });

  testWidgets("the tab has the member bar's settings button instead of home", (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board(), place: TeamTasksPlace.tab);
    await tester.pumpAndSettle();
    expect(find.byType(MemberSettingsButton), findsOneWidget);
    expect(find.byKey(const Key('team-tasks-home')), findsNothing);
  });

  testWidgets('no link opens nothing', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board());
    await tester.pumpAndSettle();
    expect(find.byType(TeamTaskSheet), findsNothing);
  });

  // Omer, 17/11/2026: closing the task a notification opened showed "כל
  // המשימות"; the notification is about his own task, so "המשימות שלי".
  bool showingAll(WidgetTester tester) =>
      tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>)).selected.first;

  testWidgets('a linked task of mine opens over "המשימות שלי"', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board(), openTaskId: 'a');
    await tester.pumpAndSettle();
    expect(showingAll(tester), isFalse);
    Navigator.of(tester.element(find.byType(TeamTaskSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(TeamTaskSheet), findsNothing);
    expect(showingAll(tester), isFalse);
  });

  testWidgets('a linked task that is not mine keeps "כל המשימות"', (tester) async {
    final other = buildTeamTask(id: 'b', title: 'לסדר ציוד', assigneeIds: const []);
    await pumpTeamTasks(
      tester,
      user: manager,
      board: TeamTaskBoard(
        tasks: [task, other],
        members: [manager],
        topics: [buildTopic()],
        categories: [buildCategory()],
      ),
      openTaskId: 'b',
    );
    await tester.pumpAndSettle();
    expect(find.byType(TeamTaskSheet), findsOneWidget);
    expect(showingAll(tester), isTrue);
  });

  testWidgets('no link opens on "כל המשימות" as before', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board());
    await tester.pumpAndSettle();
    expect(showingAll(tester), isTrue);
  });
}
