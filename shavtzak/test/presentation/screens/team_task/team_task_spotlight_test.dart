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
    // First a slow, wide wind-up to the right (Omer, msgs 4024 / 4038): still
    // going at 200ms...
    await tester.pump(const Duration(milliseconds: 200));
    final mid = tester.getCenter(find.byKey(const Key('spotlight-card-c'))).dx;
    expect(mid, greaterThan(start + 30));
    // ...further right at the peak...
    await tester.pump(const Duration(milliseconds: 260));
    expect(tester.getCenter(find.byKey(const Key('spotlight-card-c'))).dx, greaterThan(mid + 10));
    // ...then flung off to the left.
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
    // Near the top of its jump it comes toward the viewer: well over its size.
    final jump = tester.widget<Transform>(
        find.ancestor(of: flight, matching: find.byType(Transform)).first);
    expect(jump.transform.getMaxScaleOnAxis(), greaterThan(1.5));
    // Landed: the box is gone, the row is in place, the card still waits.
    await tester.pump(const Duration(milliseconds: 640));
    expect(flight, findsNothing);
    expect(find.byKey(const Key('spotlight-card-c')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('spotlight-updates-c')), matching: find.text('דיברתי עם הספק')),
        findsOneWidget);
    // "בום": the row squashes, the log under it shakes, dust flies.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('spotlight-log-squash')), findsOneWidget);
    expect(find.byKey(const Key('spotlight-log-shake')), findsOneWidget);
    expect(find.byKey(const Key('spotlight-update-dust')), findsOneWidget);
    expect(find.byKey(const Key('spotlight-card-c')), findsOneWidget);
    // All settled and cleared before the card moves on.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('spotlight-log-squash')), findsNothing);
    expect(find.byKey(const Key('spotlight-log-shake')), findsNothing);
    expect(find.byKey(const Key('spotlight-update-dust')), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spotlight-card-b')), findsOneWidget);
    expect(find.byKey(const Key('spotlight-update-dust')), findsNothing);
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
    await tester.pump(const Duration(milliseconds: 700));
    // Landed, but the card stays until the save is confirmed.
    expect(flight, findsNothing);
    expect(find.byKey(const Key('spotlight-card-c')), findsOneWidget);
    // The "בום" plays out while the server still holds the save.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('spotlight-update-dust')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('spotlight-update-dust')), findsNothing);
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
    // Flight, "בום" and the card's way out, frame by frame.
    for (var i = 0; i < 32; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('spotlight-summary')), findsOneWidget);
    expect(find.byKey(const Key('spotlight-confetti')), findsOneWidget);
    await tester.pumpAndSettle();
    final updated = tester.widget<Text>(find.byKey(const Key('spotlight-stat-1')));
    expect(updated.data, '1');
  });

  testWidgets('the status menu has no "בוצעה"; a new status turns "סיימתי" into "למשימה הבאה"',
      (tester) async {
    final harness = await open(tester);
    await tester.tap(find.byKey(const Key('spotlight-status')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-task-status-option-בוצעה')), findsNothing);
    expect(find.byKey(const Key('team-task-status-option-בטיפול')), findsOneWidget);
    await tester.tap(find.byKey(const Key('team-task-status-option-בטיפול')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, ['status:c:inProgress']);
    // Still on the same card, with the next button instead of the green one.
    expect(find.byKey(const Key('spotlight-card-c')), findsOneWidget);
    expect(find.byKey(const Key('spotlight-done')), findsNothing);
    final next = tester.widget<FilledButton>(find.byKey(const Key('spotlight-next')));
    expect(find.text('למשימה הבאה'), findsOneWidget);
    expect(next.style!.backgroundColor!.resolve({}), isNot(const Color(0xFF2E7D32)));
    await tester.tap(find.byKey(const Key('spotlight-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('spotlight-card-b')), findsOneWidget);
    expect(find.byKey(const Key('spotlight-done')), findsOneWidget);
    await tester.tap(find.byKey(const Key('spotlight-skip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('spotlight-skip')));
    await tester.pumpAndSettle();
    expect(find.text('אחת עודכנה · 2 לפעם אחרת'), findsOneWidget);
  });

  testWidgets('a short phone screen (Safari with its bars) shows the whole card and every button',
      (tester) async {
    // As on Omer's screen (msg 4070): a short title, three lines of description.
    final busy = task('c', 'לפתוח קישור', link: topic2, updates: [
      for (var i = 1; i <= 8; i++) entry('u$i', DateTime.utc(2026, 11, i)),
    ]).copyWith(description: 'בנגל: לפתוח קישור\nעומר: להפיץ\nיובל: שליחת לוז');
    await pumpTeamTasks(tester,
        user: dana, board: board([busy]), size: const Size(390, 664));
    await tester.tap(find.byKey(const Key('spotlight-start')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final screen = tester.getRect(find.byKey(const Key('spotlight-screen')));
    for (final key in ['spotlight-update', 'spotlight-done', 'spotlight-skip', 'spotlight-status']) {
      final rect = tester.getRect(find.byKey(Key(key)));
      expect(rect.bottom, lessThanOrEqualTo(screen.bottom), reason: key);
    }
    // Nothing to scroll: it all fits, the log scrolls inside the card.
    final page = tester.state<ScrollableState>(find.descendant(
        of: find.byKey(const Key('spotlight-page-scroll')), matching: find.byType(Scrollable)).first);
    expect(page.position.maxScrollExtent, 0);
    final log = tester.state<ScrollableState>(find.descendant(
        of: find.byKey(const Key('spotlight-updates-scroll-c')), matching: find.byType(Scrollable)).first);
    expect(log.position.maxScrollExtent, greaterThan(0));
    final card = tester.getRect(find.byKey(const Key('spotlight-card-c')));
    expect(card.bottom, lessThan(tester.getRect(find.byKey(const Key('spotlight-done'))).top));
  });

  testWidgets('a very short screen keeps one update of the log in sight and scrolls instead',
      (tester) async {
    final busy = task('c', 'בנגל: לפתוח קישור למחזור 26-27/11 ולשלוח לכל הצוות', link: topic2, updates: [
      for (var i = 1; i <= 8; i++) entry('u$i', DateTime.utc(2026, 11, i)),
    ]).copyWith(description: 'שורה ראשונה\nשורה שנייה\nשורה שלישית\nשורה רביעית');
    await pumpTeamTasks(tester, user: dana, board: board([busy]), size: const Size(390, 520));
    await tester.tap(find.byKey(const Key('spotlight-start')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final log = tester.state<ScrollableState>(find.descendant(
        of: find.byKey(const Key('spotlight-updates-scroll-c')), matching: find.byType(Scrollable)).first);
    expect(log.position.viewportDimension, greaterThanOrEqualTo(83));
    expect(find.text('שורה שלישית', findRichText: true), findsNothing);
    final page = tester.state<ScrollableState>(find.descendant(
        of: find.byKey(const Key('spotlight-page-scroll')), matching: find.byType(Scrollable)).first);
    expect(page.position.maxScrollExtent, greaterThan(0));
    await tester.drag(find.byKey(const Key('spotlight-page-scroll')), const Offset(0, -400));
    await tester.pumpAndSettle();
    final screen = tester.getRect(find.byKey(const Key('spotlight-screen')));
    expect(tester.getRect(find.byKey(const Key('spotlight-status'))).bottom,
        lessThanOrEqualTo(screen.bottom));
  });

  testWidgets('the status chip shows the status circle too, and it changes with the status',
      (tester) async {
    await open(tester);
    final chip = find.byKey(const Key('spotlight-status-chip'));
    expect(find.descendant(of: chip, matching: find.byKey(const Key('team-status-icon-open'))),
        findsOneWidget);
    expect(find.descendant(of: chip, matching: find.text('פתוחה')), findsOneWidget);
    await tester.tap(find.byKey(const Key('spotlight-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-task-status-option-בטיפול')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: chip, matching: find.byKey(const Key('team-status-icon-inProgress'))),
        findsOneWidget);
    expect(find.descendant(of: chip, matching: find.byKey(const Key('team-status-icon-open'))),
        findsNothing);
  });

  testWidgets('on a phone the card fills the height, with no gap above or below it',
      (tester) async {
    // Omer, msg 4085: the installed app has more height than the card needs.
    final short = task('c', 'משימה קצרה', link: topic2, updates: [entry('u1', DateTime.utc(2026, 11, 1))]);
    await pumpTeamTasks(tester, user: dana, board: board([short]), size: const Size(390, 844));
    await tester.tap(find.byKey(const Key('spotlight-start')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final progress = tester.getRect(find.byKey(const Key('spotlight-progress')));
    final card = tester.getRect(find.byKey(const Key('spotlight-card-c')));
    final buttons = tester.getRect(find.byKey(const Key('spotlight-update')));
    final screen = tester.getRect(find.byKey(const Key('spotlight-screen')));
    // Only the page's padding and the shadow's room between them.
    expect(card.top - progress.bottom, lessThan(40));
    expect(buttons.top - card.bottom, lessThan(50));
    expect(tester.getRect(find.byKey(const Key('spotlight-status'))).bottom,
        lessThanOrEqualTo(screen.bottom));
    // The log takes the room.
    expect(tester.getRect(find.byKey(const Key('spotlight-updates-c'))).height, greaterThan(250));
  });

  testWidgets('on a wide window the card keeps its own height, centred', (tester) async {
    final short = task('c', 'משימה קצרה', link: topic2, updates: [entry('u1', DateTime.utc(2026, 11, 1))]);
    await pumpTeamTasks(tester, user: dana, board: board([short]), size: const Size(1280, 1000));
    await tester.tap(find.byKey(const Key('spotlight-start')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final progress = tester.getRect(find.byKey(const Key('spotlight-progress')));
    final card = tester.getRect(find.byKey(const Key('spotlight-card-c')));
    final screen = tester.getRect(find.byKey(const Key('spotlight-screen')));
    final status = tester.getRect(find.byKey(const Key('spotlight-status')));
    expect(card.top - progress.bottom, greaterThan(100));
    // About as much room under the buttons as above the card.
    expect(((screen.bottom - status.bottom) - (card.top - progress.bottom)).abs(), lessThan(60));
  });

  testWidgets('the "ביטול" bar floats above the buttons, never over them', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('spotlight-done')));
    await tester.pumpAndSettle();
    // The bar's own box (the SnackBar widget's box also holds its margin).
    final bar = tester.getRect(find
        .descendant(of: find.byKey(const Key('spotlight-undo-bar')), matching: find.byType(Material))
        .first);
    expect(bar.bottom, lessThanOrEqualTo(tester.getRect(find.byKey(const Key('spotlight-update'))).top));
    await tester.tap(find.byKey(const Key('spotlight-skip')));
    await tester.pumpAndSettle();
    expect(find.text('3/3'), findsOneWidget);
  });

  group('back to the tasks already seen (Omer, msg 4455)', () {
    Future<void> skip(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('spotlight-skip')));
      await tester.pumpAndSettle();
    }

    Future<void> back(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('spotlight-back')));
      await tester.pumpAndSettle();
    }

    String current() => ['a', 'b', 'c']
        .firstWhere((id) => find.byKey(Key('spotlight-card-$id')).evaluate().isNotEmpty);

    testWidgets('one card at a time down to the first, with no way back from it', (tester) async {
      await open(tester);
      bool backEnabled() =>
          tester.widget<FilledButton>(find.byKey(const Key('spotlight-back'))).onPressed != null;
      expect(backEnabled(), isFalse);
      await skip(tester);
      expect(backEnabled(), isTrue);
      await skip(tester);
      expect(current(), 'a');
      expect(find.text('3/3'), findsOneWidget);
      await back(tester);
      expect(current(), 'b');
      expect(find.text('2/3'), findsOneWidget);
      await back(tester);
      expect(current(), 'c');
      expect(find.text('1/3'), findsOneWidget);
      expect(backEnabled(), isFalse);
    });

    testWidgets('forward again keeps the order: nothing skipped, nothing twice', (tester) async {
      await open(tester);
      final seen = [current()];
      await skip(tester);
      seen.add(current());
      await back(tester);
      seen.add(current());
      await skip(tester);
      seen.add(current());
      await skip(tester);
      seen.add(current());
      expect(seen, ['c', 'b', 'c', 'b', 'a']);
      await skip(tester);
      expect(find.byKey(const Key('spotlight-summary')), findsOneWidget);
      expect(find.text('עברת על 3 משימות'), findsOneWidget);
      // Skipped twice, counted once.
      expect(find.text('3 לפעם אחרת'), findsOneWidget);
    });

    testWidgets('the card it returns to shows its updates now and takes another one',
        (tester) async {
      final harness = await open(tester);
      await tester.tap(find.byKey(const Key('spotlight-update')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('spotlight-update-field')), 'דיברתי עם הספק');
      await tester.ensureVisible(find.byKey(const Key('spotlight-send')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('spotlight-send')));
      await tester.pumpAndSettle();
      expect(current(), 'b');
      // The stream brings the saved update.
      final saved = task('c', 'מוזמנים', link: topic2, updates: [
        TaskUpdateEntry(
            id: 'n1',
            text: 'דיברתי עם הספק',
            at: DateTime.utc(2026, 11, 15, 8),
            byId: 'm1',
            byName: 'דנה'),
      ]);
      await harness.deliver(tester, board([recent, quiet, saved, closed]));
      await tester.pumpAndSettle();
      await back(tester);
      expect(current(), 'c');
      expect(find.byKey(const Key('spotlight-log-n1')), findsOneWidget);
      expect(find.text('דיברתי עם הספק'), findsOneWidget);
      await tester.tap(find.byKey(const Key('spotlight-update')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('spotlight-update-field')), 'הספק אישר');
      await tester.ensureVisible(find.byKey(const Key('spotlight-send')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('spotlight-send')));
      await tester.pumpAndSettle();
      expect(harness.repository.calls, ['log:c:דיברתי עם הספק', 'log:c:הספק אישר']);
      expect(current(), 'b');
      expect(find.text('2/3'), findsOneWidget);
    });

    testWidgets('a task closed on the way stays in its place, shown closed, and can reopen',
        (tester) async {
      final harness = await open(tester);
      await tester.tap(find.byKey(const Key('spotlight-done')));
      await tester.pumpAndSettle();
      expect(current(), 'b');
      await back(tester);
      expect(current(), 'c');
      expect(
          find.descendant(
              of: find.byKey(const Key('spotlight-status-chip')), matching: find.text('בוצעה')),
          findsOneWidget);
      // "סיימתי" would change nothing: it moves on instead.
      expect(find.byKey(const Key('spotlight-done')), findsNothing);
      expect(find.byKey(const Key('spotlight-next')), findsOneWidget);
      await tester.tap(find.byKey(const Key('spotlight-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('team-task-status-option-בטיפול')));
      await tester.pumpAndSettle();
      expect(harness.repository.calls, ['status:c:done', 'status:c:inProgress']);
      expect(current(), 'c');
      await tester.tap(find.byKey(const Key('spotlight-next')));
      await tester.pumpAndSettle();
      expect(current(), 'b');
      await skip(tester);
      await skip(tester);
      // Reopened: no longer counted as closed, counted as updated.
      expect(find.text('אחת עודכנה · 2 לפעם אחרת'), findsOneWidget);
    });

    testWidgets('the card leaves backwards, to the right, the mirror of "למשימה הבאה"',
        (tester) async {
      await open(tester);
      await skip(tester);
      final start = tester.getCenter(find.byKey(const Key('spotlight-card-b'))).dx;
      await tester.tap(find.byKey(const Key('spotlight-back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
          tester.getCenter(find.byKey(const Key('spotlight-card-b'))).dx, greaterThan(start + 40));
      await tester.pumpAndSettle();
      expect(current(), 'c');
      expect(find.byKey(const Key('spotlight-card-b')), findsNothing);
    });

    // Geometry only: the test font draws every letter as a full square, far
    // wider than Rubik, so whether the words fit is checked in a browser.
    for (final width in [400.0, 1280.0]) {
      testWidgets(
          '"אחורה" sits right of the four buttons, centred on them, adding no height '
          '(${width.round()} px)', (tester) async {
        await pumpTeamTasks(tester,
            user: dana, board: board([recent, quiet, never, closed]), size: Size(width, 800));
        await tester.tap(find.byKey(const Key('spotlight-start')));
        await tester.pumpAndSettle();
        await skip(tester);
        expect(tester.takeException(), isNull);
        final back = tester.getRect(find.byKey(const Key('spotlight-back')));
        final update = tester.getRect(find.byKey(const Key('spotlight-update')));
        final done = tester.getRect(find.byKey(const Key('spotlight-done')));
        final skipRect = tester.getRect(find.byKey(const Key('spotlight-skip')));
        final status = tester.getRect(find.byKey(const Key('spotlight-status')));
        // On the screen's right (RTL start), beside the whole block.
        for (final r in [update, done, skipRect, status]) {
          expect(back.left, greaterThan(r.right));
        }
        // Centred on the two rows.
        expect((back.center.dy - (update.top + status.bottom) / 2).abs(), lessThan(1));
        // No more height than the two rows.
        expect(back.height, lessThanOrEqualTo(status.bottom - update.top));
        expect(back.width, lessThan(update.width));
      });
    }
  });
}
