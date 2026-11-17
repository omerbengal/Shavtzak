import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';
import '../../../support/team_tasks_harness.dart';

/// Omer, msg 4500: "בנגל" found nothing although "עומר בנגל" owns tasks. The
/// search bar of both tabs looks in the owners' names (and the link, the log
/// and the contacts), not only the title and description.
void main() {
  final omer = buildMember(id: 'o1', name: 'עומר בנגל', isAdmin: true);
  final dana = buildMember(id: 'm1', name: 'דנה');
  const topic = TaskLink(TaskLinkType.topic, 'p1');
  final his = buildTeamTask(id: 'a', title: 'להזמין אולם', link: topic, assigneeIds: ['o1'])
      // The topic as the repository fills it in.
      .copyWith(owners: [omer], topic: () => buildTopic());
  final hers = buildTeamTask(id: 'b', title: 'לסדר ציוד', link: topic, assigneeIds: ['m1'])
      .copyWith(owners: [dana]);

  TeamTaskBoard board() => TeamTaskBoard(
        tasks: [his, hers],
        members: [omer, dana],
        topics: [buildTopic()],
        categories: [buildCategory()],
      );

  Future<void> searchFor(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('team-filter-search')), text);
    await tester.pumpAndSettle();
  }

  testWidgets('"כל המשימות": a last name finds that owner\'s tasks', (tester) async {
    await pumpTeamTasks(tester, user: omer, board: board());
    await tester.pumpAndSettle();
    await searchFor(tester, 'בנגל');
    expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
    expect(find.byKey(const Key('team-task-row-b')), findsNothing);
    await searchFor(tester, 'דנה');
    expect(find.byKey(const Key('team-task-row-b')), findsOneWidget);
    expect(find.byKey(const Key('team-task-row-a')), findsNothing);
  });

  testWidgets('"המשימות שלי" searches the same way', (tester) async {
    await pumpTeamTasks(tester, user: omer, board: board());
    await tester.pumpAndSettle();
    await tester.tap(find.text('המשימות שלי'));
    await tester.pumpAndSettle();
    await searchFor(tester, 'בנגל');
    expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
    await searchFor(tester, 'מגדים');
    expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
  });
}
