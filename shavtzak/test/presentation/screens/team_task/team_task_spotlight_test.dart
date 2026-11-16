import 'dart:async';

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
    expect(find.text('אחת נסגרה · אחת עודכנה · אחת לפעם אחרת'), findsOneWidget);
    expect(find.text('לפעם אחרת'), findsOneWidget);
    expect(find.text('נדחו'), findsNothing);
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
    expect(find.textContaining('בליץ · '), findsOneWidget);
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

  testWidgets('the updates come in one after the other, all in under half a second',
      (tester) async {
    final busy = task('e', 'הרבה עדכונים', updates: [
      for (var i = 0; i < 8; i++) entry('u$i', DateTime.utc(2026, 11, 10 - i)),
    ]);
    await pumpTeamTasks(tester, user: dana, board: board([busy]));
    await tester.tap(find.byKey(const Key('spotlight-start')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    double opacityOf(String id) => tester
        .widget<Opacity>(find
            .ancestor(of: find.byKey(Key('spotlight-log-$id')), matching: find.byType(Opacity))
            .first)
        .opacity;
    expect(opacityOf('u0'), greaterThan(opacityOf('u3')));
    await tester.pump(const Duration(milliseconds: 400));
    for (final id in ['u0', 'u3', 'u7']) {
      expect(opacityOf(id), 1.0);
    }
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

  testWidgets('a sent update flies from the field up to the log before the card moves on',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('spotlight-update')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('spotlight-update-field')), 'דיברתי עם הספק');
    await tester.ensureVisible(find.byKey(const Key('spotlight-send')));
    await tester.pumpAndSettle();
    final fieldTop =
        tester.getRect(find.byKey(const Key('spotlight-update-field'))).top;
    await tester.tap(find.byKey(const Key('spotlight-send')));
    await tester.pump();
    await tester.pump();
    // Mid-air: one box carries the text, between the field and the log; the
    // row in the log keeps its place empty until it lands.
    await tester.pump(const Duration(milliseconds: 260));
    final flight = find.byKey(const Key('spotlight-update-flight'));
    expect(flight, findsOneWidget);
    expect(find.descendant(of: flight, matching: find.text('דיברתי עם הספק')), findsOneWidget);
    final rowRect = tester.getRect(find.byKey(const Key('spotlight-log-echo')));
    final midTop = tester.getRect(flight).top;
    expect(midTop, lessThan(fieldTop));
    expect(midTop, greaterThan(rowRect.top));
    final hidden = tester.widget<Opacity>(find
        .ancestor(
            of: find.descendant(
                of: find.byKey(const Key('spotlight-log-echo')),
                matching: find.text('דיברתי עם הספק')),
            matching: find.byType(Opacity))
        .first);
    expect(hidden.opacity, 0);
    // Landed: the box is gone, the row is in place, the card still waits.
    await tester.pump(const Duration(milliseconds: 300));
    expect(flight, findsNothing);
    expect(find.byKey(const Key('spotlight-card-c')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('spotlight-updates-c')), matching: find.text('דיברתי עם הספק')),
        findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spotlight-card-b')), findsOneWidget);
  });

  testWidgets(
      'the first save flies at once, while the server still holds the save and the '
      'stream already shows the update (Omer, msg 4004)', (tester) async {
    final harness = await open(tester);
    await tester.tap(find.byKey(const Key('spotlight-update')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('spotlight-update-field')), 'דיברתי עם הספק');
    await tester.ensureVisible(find.byKey(const Key('spotlight-send')));
    await tester.pumpAndSettle();
    // The first save after the app opens waits for the server.
    final server = harness.repository.gate = Completer<void>();
    await tester.tap(find.byKey(const Key('spotlight-send')));
    await tester.pump();
    // Firestore shows the written update in the log before the save returns.
    final sent = TaskUpdateEntry(
        id: 'new', text: 'דיברתי עם הספק', at: DateTime.utc(2026, 11, 15, 8), byId: 'm1',
        byName: 'דנה');
    await harness.deliver(
        tester,
        board([
          recent,
          quiet,
          task('c', 'מוזמנים', link: topic2, updates: [sent]),
          closed,
        ]));
    await tester.pump(const Duration(milliseconds: 200));
    final flight = find.byKey(const Key('spotlight-update-flight'));
    expect(flight, findsOneWidget);
    // Its row waits, unseen, for the box to land.
    final hidden = tester.widget<Opacity>(find
        .ancestor(
            of: find.descendant(
                of: find.byKey(const Key('spotlight-log-new')),
                matching: find.text('דיברתי עם הספק')),
            matching: find.byType(Opacity))
        .first);
    expect(hidden.opacity, 0);
    await tester.pump(const Duration(milliseconds: 400));
    // Landed, but the card stays until the save is confirmed.
    expect(flight, findsNothing);
    expect(find.byKey(const Key('spotlight-card-c')), findsOneWidget);
    server.complete();
    harness.repository.gate = null;
    await tester.pumpAndSettle();
    expect(harness.repository.calls, ['log:c:דיברתי עם הספק']);
    expect(find.byKey(const Key('spotlight-card-b')), findsOneWidget);
  });

  testWidgets('a refused save brings the text back to the field', (tester) async {
    final harness = await open(tester);
    await tester.tap(find.byKey(const Key('spotlight-update')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('spotlight-update-field')), 'דיברתי עם הספק');
    await tester.ensureVisible(find.byKey(const Key('spotlight-send')));
    await tester.pumpAndSettle();
    harness.repository.failWith = Exception('offline');
    await tester.tap(find.byKey(const Key('spotlight-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spotlight-update-flight')), findsNothing);
    expect(find.byKey(const Key('spotlight-card-c')), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('spotlight-update-field')));
    expect(field.controller!.text, 'דיברתי עם הספק');
    expect(find.byKey(const Key('spotlight-log-echo')), findsNothing);
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
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byKey(const Key('spotlight-summary')), findsOneWidget);
    expect(find.byKey(const Key('spotlight-confetti')), findsOneWidget);
    await tester.pumpAndSettle();
    final updated = tester.widget<Text>(find.byKey(const Key('spotlight-stat-1')));
    expect(updated.data, '1');
  });
}
