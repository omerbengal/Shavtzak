import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';
import '../../../support/team_tasks_harness.dart';

/// A desktop window (16/11/2026, Omer: "האנימציות של הבליץ לא עובדות
/// בדסקטופ"): Blitz and the list's slide play there as on a phone.
void main() {
  const desktop = Size(1440, 900);
  final dana = buildMember(id: 'm1', name: 'דנה');
  const topic = TaskLink(TaskLinkType.topic, 'p1');

  TeamTask task(String id, String title) =>
      buildTeamTask(id: id, title: title, link: topic, assigneeIds: ['m1'])
          .copyWith(owners: [dana]);

  TeamTaskBoard board(List<TeamTask> tasks) => TeamTaskBoard(
        tasks: tasks,
        members: [dana],
        topics: [buildTopic()],
        categories: [buildCategory()],
      );

  testWidgets('Blitz: "לא עכשיו" winds up and flings the card on a desktop window',
      (tester) async {
    await pumpTeamTasks(tester,
        user: dana, board: board([task('a', 'אוטובוסים'), task('b', 'מקום')]), size: desktop);
    await tester.tap(find.byKey(const Key('spotlight-start')));
    await tester.pumpAndSettle();
    final card = find.byKey(const Key('spotlight-card-a')).evaluate().isEmpty
        ? find.byKey(const Key('spotlight-card-b'))
        : find.byKey(const Key('spotlight-card-a'));
    final start = tester.getCenter(card).dx;
    await tester.tap(find.byKey(const Key('spotlight-skip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final mid = tester.getCenter(card).dx;
    // Wound up to the left, then flung to the right (mirrored, msg 4500).
    expect(mid, lessThan(start - 30));
    await tester.pump(const Duration(milliseconds: 660));
    expect(card, findsOneWidget);
    expect(tester.getCenter(card).dx, greaterThan(start + 100));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(find.text('2/2'), findsOneWidget);
  });

  testWidgets('the list slides right over 500 ms when a task opens, and back on close',
      (tester) async {
    await pumpTeamTasks(tester, user: dana, board: board([task('a', 'אוטובוסים')]), size: desktop);
    final row = find.byKey(const Key('team-task-row-a'));
    final before = tester.getCenter(row).dx;
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final halfway = tester.getCenter(row).dx;
    await tester.pumpAndSettle();
    final opened = tester.getCenter(row).dx;
    expect(opened, greaterThan(before + 100));
    // Midway, not jumped: well between where it was and where it ends.
    expect(halfway, greaterThan(before + 20));
    expect(halfway, lessThan(opened - 20));

    await tester.tap(find.byKey(const Key('team-task-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    final closing = tester.getCenter(row).dx;
    expect(closing, lessThan(opened - 20));
    expect(closing, greaterThan(before + 20));
    await tester.pumpAndSettle();
    expect(tester.getCenter(row).dx, closeTo(before, 1));
  });
}
