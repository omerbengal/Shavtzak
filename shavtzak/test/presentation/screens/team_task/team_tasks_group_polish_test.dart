import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/task_topic.dart';
import 'package:shavtzak/domain/entities/team_task.dart';
import 'package:shavtzak/presentation/screens/task/task_style.dart';
import 'package:shavtzak/presentation/screens/team_task/widgets/team_task_style.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';
import '../../../support/team_tasks_harness.dart';

/// Omer, 16/11/2026 (msg 4175): the filter's link picker names no new
/// "אירוע שעוד לא נוצר", a category's header takes the category's colour,
/// and its own tasks and its tasks of several events are two lists.
void main() {
  final manager = buildMember(id: 'mgr', name: 'מנהלת', isAdmin: true);
  const pending = TaskTopic(id: 'pe1', name: 'חנוכה 2027');
  const green = 0xFF4CAF50;
  final hanukkah = buildCategory(colorValue: green);
  final plainCategory = buildCategory(id: 'c2', name: 'בלי צבע');
  final candles = buildEvent(
      id: 'e1', name: 'הדלקת נרות', categoryId: 'c1', startDate: DateTime(2026, 11, 20));
  final party = buildEvent(
      id: 'e2', name: 'מסיבה', categoryId: 'c1', startDate: DateTime(2026, 12, 20));
  final other = buildEvent(
      id: 'e3', name: 'אחר', categoryId: 'c2', startDate: DateTime(2026, 11, 25));

  final own = buildTeamTask(
    id: 'own',
    title: 'של הקטגוריה',
    assigneeIds: ['mgr'],
    link: const TaskLink(TaskLinkType.category, 'c1'),
    category: hanukkah,
  );
  final several = buildTeamTask(
    id: 'several',
    title: 'של שני אירועים',
    assigneeIds: ['mgr'],
    link: const TaskLink(TaskLinkType.event, 'e1'),
    eventIds: const ['e1', 'e2'],
    event: candles,
    events: [candles, party],
  );
  final onOther = buildTeamTask(
    id: 'other',
    title: 'באירוע אחר',
    assigneeIds: ['mgr'],
    link: const TaskLink(TaskLinkType.event, 'e3'),
    event: other,
    events: [other],
  );

  TeamTaskBoard board(List<TeamTask> tasks) => TeamTaskBoard(
        tasks: tasks,
        members: [manager],
        events: [candles, party, other],
        categories: [hanukkah, plainCategory],
        pendingEvents: const [pending],
      );

  testWidgets('the filter\'s link picker offers no new "אירוע שעוד לא נוצר"', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board([own]), size: teamWideSize);
    for (final tab in ['team-tab-mine', 'team-tab-all']) {
      await tester.tap(find.byKey(Key(tab)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-filter-link')));
      await tester.pumpAndSettle();
      // The existing placeholder can still be filtered on.
      expect(find.byKey(const Key('task-link-option-pe1')), findsOneWidget);
      expect(find.byKey(const Key('task-link-pending-new')), findsNothing);
      await tester.tap(find.byKey(const Key('task-link-option-pe1')));
      await tester.pumpAndSettle();
      // Clear the filter for the next tab.
      await tester.tap(find.byKey(const Key('team-filter-link')));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a new task\'s link picker still offers it', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board(const []));
    await tester.tap(find.byKey(const Key('team-task-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-team-task-link')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-link-pending-new')), findsOneWidget);
  });

  testWidgets('a category\'s header takes its colour; none = the usual grey', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board([own, onOther]));
    Color header(String key) =>
        tester.widget<Material>(find.byKey(Key('team-task-group-header-$key'))).color!;
    final tinted = header('category:c1');
    expect(tinted, TeamTaskStyle.categoryHeader(green));
    expect(tinted, isNot(TaskStyle.stageHeader));
    // A light tint: the header's dark text stays readable.
    expect(tinted.computeLuminance(), greaterThan(0.5));
    expect(header('category:c2'), TaskStyle.stageHeader);
  });

  test('every palette colour gives a light header tint', () {
    for (final value in const [0xFF3F51B5, 0xFF795548, 0xFF673AB7, 0xFFF44336, 0xFFFFEB3B]) {
      expect(TeamTaskStyle.categoryHeader(value).computeLuminance(), greaterThan(0.5));
    }
  });

  testWidgets('a line above the own tasks, then a line above the tasks of several events',
      (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board([several, own]));
    final ownLine = find.byKey(const Key('team-task-own-separator-category:c1'));
    final severalLine = find.byKey(const Key('team-task-several-separator-category:c1'));
    expect(ownLine, findsOneWidget);
    expect(severalLine, findsOneWidget);
    expect(find.descendant(of: ownLine, matching: find.text('משויכות לקטגוריה')), findsOneWidget);
    expect(find.descendant(of: severalLine, matching: find.text('משויכות לכמה אירועים')),
        findsOneWidget);
    double top(Finder f) => tester.getRect(f).top;
    final ownTop = top(find.byKey(const Key('team-task-row-own')));
    final severalTop = top(find.byKey(const Key('team-task-row-several')));
    expect(top(ownLine), lessThan(ownTop));
    expect(ownTop, lessThan(top(severalLine)));
    expect(top(severalLine), lessThan(severalTop));
  });

  testWidgets('each list keeps its line when it is the only one', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board([several]));
    expect(find.byKey(const Key('team-task-row-several')), findsOneWidget);
    expect(find.byKey(const Key('team-task-several-separator-category:c1')), findsOneWidget);
    expect(find.byKey(const Key('team-task-own-separator-category:c1')), findsNothing);
  });

  testWidgets('own tasks alone still get their line', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board([own]));
    expect(find.byKey(const Key('team-task-own-separator-category:c1')), findsOneWidget);
    expect(find.byKey(const Key('team-task-several-separator-category:c1')), findsNothing);
  });

  testWidgets('a card of event sections only has no list lines (each event has its header)',
      (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board([onOther]));
    expect(find.textContaining('משויכות ל'), findsNothing);
  });
}
