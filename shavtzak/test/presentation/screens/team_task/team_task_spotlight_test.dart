import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';
import '../../../support/team_tasks_harness.dart';

void main() {
  final dana = buildMember(id: 'm1', name: 'דנה');
  final manager = buildMember(id: 'mgr', name: 'מנהלת', isAdmin: true);

  TeamTaskBoard board(List<TeamTask> tasks) => TeamTaskBoard(
        tasks: tasks,
        members: [dana, manager],
        topics: [buildTopic(), buildTopic(id: 'p2', name: 'חנוכה')],
        categories: [buildCategory()],
      );

  TaskUpdateEntry entry(String id, DateTime at) =>
      TaskUpdateEntry(id: id, text: 'עדכון $id', at: at, byId: 'm1', byName: 'דנה');

  const topic1 = TaskLink(TaskLinkType.topic, 'p1');
  const topic2 = TaskLink(TaskLinkType.topic, 'p2');

  TeamTask task(
    String id,
    String title, {
    TaskLink? link,
    List<TaskUpdateEntry> updates = const [],
    String owner = 'm1',
  }) =>
      buildTeamTask(
              id: id, title: title, link: link ?? topic1, assigneeIds: [owner], updates: updates)
          .copyWith(owners: [if (owner == 'm1') dana else manager]);

  final recent = task('a', 'אוטובוסים', updates: [entry('1', DateTime.utc(2026, 11, 14))]);
  final quiet = task('b', 'מקום לאירוע', updates: [entry('2', DateTime.utc(2026, 11, 3))]);
  final never = task('c', 'מוזמנים', link: topic2);
  final closed =
      buildTeamTask(id: 'd', title: 'סגורה', status: TeamTaskStatus.done, link: topic1);

  Future<TeamTasksHarness> open(WidgetTester tester) async {
    final harness =
        await pumpTeamTasks(tester, user: dana, board: board([recent, quiet, never, closed]));
    await tester.tap(find.byKey(const Key('spotlight-start')));
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('"המשימות שלי" has the button with the open count; "כל המשימות" does not',
      (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board([task('m', 'שלי', owner: 'mgr')]));
    expect(find.byKey(const Key('spotlight-start')), findsNothing);
    await tester.tap(find.text('המשימות שלי'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spotlight-start')), findsOneWidget);
    expect(find.text('משימה אחת פתוחה'), findsOneWidget);
  });

  testWidgets('goes through the open tasks, the quietest first', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('spotlight-card-c')), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('spotlight-quiet-c')), matching: find.text('אין עדכון עדיין')),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('spotlight-skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spotlight-card-b')), findsOneWidget);
    expect(find.text('עדכון 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('spotlight-skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spotlight-card-a')), findsOneWidget);
  });

  testWidgets('"סיימתי" sets done and moves on; "ביטול" brings it back', (tester) async {
    final harness = await open(tester);
    await tester.tap(find.byKey(const Key('spotlight-done')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, ['status:c:done']);
    expect(find.text('2/3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('spotlight-undo')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, ['status:c:done', 'status:c:open']);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.byKey(const Key('spotlight-card-c')), findsOneWidget);
  });

  testWidgets('a short update: a chip fills the field, send writes the log and moves on',
      (tester) async {
    final harness = await open(tester);
    await tester.tap(find.byKey(const Key('spotlight-update')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('spotlight-chip-1')));
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const Key('spotlight-update-field')));
    expect(field.controller!.text, 'מחכה למישהו ⏳ ');
    await tester.enterText(find.byKey(const Key('spotlight-update-field')), 'מחכה למישהו ⏳ לטלפון');
    await tester.tap(find.byKey(const Key('spotlight-send')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, ['log:c:מחכה למישהו ⏳ לטלפון']);
    expect(find.byKey(const Key('spotlight-card-b')), findsOneWidget);
  });

  testWidgets('the last screen sums up, and the list flashes what changed', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('spotlight-done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('spotlight-update')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('spotlight-chip-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('spotlight-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('spotlight-skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spotlight-summary')), findsOneWidget);
    expect(find.text('עברת על 3 משימות'), findsOneWidget);
    expect(find.text('אחת נסגרה · אחת עודכנה · אחת נדחתה'), findsOneWidget);
    await tester.tap(find.byKey(const Key('spotlight-finish')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byKey(const Key('spotlight-screen')), findsNothing);
    expect(find.byKey(const Key('team-task-flash-b-1')), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-task-flash-b-1')), findsNothing);
  });

  testWidgets('✕ leaves at any moment', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('spotlight-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spotlight-screen')), findsNothing);
    expect(find.byKey(const Key('team-task-row-a')), findsOneWidget);
  });

  testWidgets('a long press on a card header goes through that card only', (tester) async {
    await pumpTeamTasks(tester, user: dana, board: board([recent, quiet, never]));
    await tester.longPress(find.byKey(const Key('team-task-group-topic:p1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('זרקור · '), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.byKey(const Key('spotlight-card-b')), findsOneWidget);
  });
  testWidgets('a card shows every update of the task, newest first', (tester) async {
    final busy = task('e', 'הרבה עדכונים', updates: [
      entry('9', DateTime.utc(2026, 11, 2)),
      entry('8', DateTime.utc(2026, 11, 1)),
      entry('7', DateTime.utc(2026, 10, 30)),
    ]);
    await pumpTeamTasks(tester, user: dana, board: board([busy]));
    await tester.tap(find.byKey(const Key('spotlight-start')));
    await tester.pumpAndSettle();
    expect(find.text('עדכונים (3)'), findsOneWidget);
    for (final id in ['9', '8', '7']) {
      expect(find.byKey(Key('spotlight-log-$id')), findsOneWidget);
    }
    final top = tester.getTopLeft(find.byKey(const Key('spotlight-log-9'))).dy;
    final bottom = tester.getTopLeft(find.byKey(const Key('spotlight-log-7'))).dy;
    expect(top, lessThan(bottom));
  });

  testWidgets('"לא עכשיו" flings the card off to the side before the next comes in',
      (tester) async {
    await open(tester);
    final start = tester.getCenter(find.byKey(const Key('spotlight-card-c'))).dx;
    await tester.tap(find.byKey(const Key('spotlight-skip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('spotlight-card-c')), findsOneWidget);
    expect(tester.getCenter(find.byKey(const Key('spotlight-card-c'))).dx, lessThan(start - 100));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spotlight-card-c')), findsNothing);
    expect(find.byKey(const Key('spotlight-card-b')), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets('"סיימתי" throws confetti and shows a check; it is gone once settled',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('spotlight-done')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('spotlight-confetti')), findsOneWidget);
    expect(find.byKey(const Key('spotlight-done-check')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spotlight-confetti')), findsNothing);
    expect(find.byKey(const Key('spotlight-card-b')), findsOneWidget);
  });

  testWidgets('a sent update lands in the log before the card moves on', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('spotlight-update')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('spotlight-update-field')), 'דיברתי עם הספק');
    await tester.ensureVisible(find.byKey(const Key('spotlight-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('spotlight-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('spotlight-card-c')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('spotlight-updates-c')), matching: find.text('דיברתי עם הספק')),
        findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spotlight-card-b')), findsOneWidget);
  });

  testWidgets('the summary counts up, with confetti when nothing was left for later',
      (tester) async {
    await pumpTeamTasks(tester, user: dana, board: board([never]));
    await tester.tap(find.byKey(const Key('spotlight-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('spotlight-update')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('spotlight-chip-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('spotlight-send')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.byKey(const Key('spotlight-summary')), findsOneWidget);
    expect(find.byKey(const Key('spotlight-confetti')), findsOneWidget);
    await tester.pumpAndSettle();
    final updated = tester.widget<Text>(find.byKey(const Key('spotlight-stat-1')));
    expect(updated.data, '1');
  });
}
