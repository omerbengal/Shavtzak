import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';
import '../../../support/team_tasks_harness.dart';

void main() {
  final manager = buildMember(id: 'mgr', isAdmin: true);

  Future<TeamTasksHarness> openDialog(WidgetTester tester, TeamTaskBoard board) async {
    final harness = await pumpTeamTasks(tester, user: manager, board: board);
    await tester.tap(find.byKey(const Key('team-tasks-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-tasks-menu-topics')));
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('topic dialog archives and restores', (tester) async {
    final active = buildTopic(id: 'p1', name: 'כללי');
    final archived = buildTopic(id: 'p2', name: 'ישן', isArchived: true);
    final harness = await openDialog(
        tester, TeamTaskBoard(tasks: const [], topics: [active, archived]));
    expect(find.text('כללי'), findsOneWidget);
    expect(find.text('ישן'), findsNothing);

    await tester.tap(find.byKey(const Key('topic-archive-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('topic-show-archived')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('topic-restore-p2')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, ['archiveTopic:p1', 'restoreTopic:p2']);
  });

  testWidgets('topic dialog adds and renames', (tester) async {
    final harness = await openDialog(
        tester, TeamTaskBoard(tasks: const [], topics: [buildTopic(id: 'p1', name: 'כללי')]));
    await tester.enterText(find.byKey(const Key('topic-new-name')), 'נשות מגדים');
    await tester.tap(find.byKey(const Key('topic-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('topic-rename-p1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('topic-rename-field')), 'כללי ושונות');
    await tester.tap(find.byKey(const Key('topic-rename-save')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, ['insertTopic:נשות מגדים', 'updateTopic:p1:כללי ושונות']);
  });

  testWidgets('deleting a topic lists the titles of its tasks, then deletes', (tester) async {
    const link = TaskLink(TaskLinkType.topic, 'p1');
    final harness = await openDialog(
      tester,
      TeamTaskBoard(
        tasks: [
          buildTeamTask(id: 'a', title: 'להזמין אולם', link: link),
          buildTeamTask(id: 'b', title: 'לקנות כיבוד', link: link),
          buildTeamTask(id: 'c', title: 'בנושא אחר', link: const TaskLink(TaskLinkType.topic, 'p2')),
        ],
        topics: [buildTopic(id: 'p1', name: 'כללי'), buildTopic(id: 'p2', name: 'אחר')],
      ),
    );
    await tester.tap(find.byKey(const Key('topic-delete-p1')));
    await tester.pumpAndSettle();
    final items = find.byKey(const Key('topic-delete-items'));
    expect(find.descendant(of: items, matching: find.text('• להזמין אולם')), findsOneWidget);
    expect(find.descendant(of: items, matching: find.text('• לקנות כיבוד')), findsOneWidget);
    expect(find.descendant(of: items, matching: find.text('• בנושא אחר')), findsNothing);
    await tester.tap(find.byKey(const Key('topic-delete-confirm')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, ['deleteTopic:p1']);
  });

  testWidgets('a topic with no tasks says so in the confirm', (tester) async {
    await openDialog(
        tester, TeamTaskBoard(tasks: const [], topics: [buildTopic(id: 'p1', name: 'כללי')]));
    await tester.tap(find.byKey(const Key('topic-delete-p1')));
    await tester.pumpAndSettle();
    expect(find.text('אין משימות עם הנושא הזה.'), findsOneWidget);
    expect(find.byKey(const Key('topic-delete-items')), findsNothing);
  });

  testWidgets('a member who is not a manager has no topics menu', (tester) async {
    await pumpTeamTasks(tester,
        user: buildMember(id: 'm1'), board: const TeamTaskBoard(tasks: []));
    expect(find.byKey(const Key('team-tasks-menu')), findsNothing);
  });
}
