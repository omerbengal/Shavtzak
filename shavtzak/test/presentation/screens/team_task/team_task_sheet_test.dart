import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/team_task.dart';
import 'package:shavtzak/presentation/widgets/date_picker_dialog.dart';
import 'package:shavtzak/presentation/screens/team_task/widgets/team_task_style.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';
import '../../../support/team_tasks_harness.dart';

void main() {
  final dana = buildMember(id: 'm1', name: 'דנה');
  final yossi = buildMember(id: 'm2', name: 'יוסי');
  final manager = buildMember(id: 'mgr', name: 'מנהלת', isAdmin: true);

  TeamTaskBoard board(List<TeamTask> tasks) => TeamTaskBoard(
        tasks: tasks,
        members: [dana, yossi, manager],
        topics: [buildTopic()],
      );

  final hall = buildTeamTask(id: 't', title: 'אולם', assigneeIds: ['m1', 'm2'])
      .copyWith(owners: [dana, yossi], contacts: const [
    StageContact(id: 'c1', name: 'רונית', phone: '050-1234567', role: 'אולם'),
  ]);
  final other =
      buildTeamTask(id: 'o', title: 'משימה מקורית', assigneeIds: ['m1']).copyWith(owners: [dana]);

  Future<void> openTask(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key('team-task-row-$id')));
    await tester.pumpAndSettle();
  }

  testWidgets('status menu shows the five Hebrew labels', (tester) async {
    await pumpTeamTasks(tester, user: dana, board: board([other]));
    await openTask(tester, 'o');
    await tester.tap(find.byKey(const Key('team-task-status')));
    await tester.pumpAndSettle();
    for (final label in ['פתוחה', 'בטיפול', 'בוצעה', 'לא רלוונטי/בוטל', 'כפילות']) {
      final option = find.byKey(Key('team-task-status-option-$label'));
      expect(option, findsOneWidget);
      // Its status circle on the right of the word (round 5).
      final icon = find.descendant(of: option, matching: find.byType(TeamTaskStatusIcon));
      final word = find.descendant(of: option, matching: find.text(label));
      expect(tester.getCenter(icon).dx, greaterThan(tester.getRect(word).right));
    }
  });

  testWidgets('the deadline opens the app date picker, as for a constraint', (tester) async {
    // The calendar's month header needs a tablet's width with the test font.
    await pumpTeamTasks(tester, user: manager, board: board([other]), size: const Size(1200, 1000));
    await openTask(tester, 'o');
    await tester.tap(find.byKey(const Key('team-task-edit-deadline')));
    await tester.pumpAndSettle();
    final picker = tester.widget<DualCalendarDatePicker>(find.byType(DualCalendarDatePicker));
    expect(find.byType(DatePickerDialog), findsNothing);
    // Today and later only, and no event frames (round 2, bugs 2-3).
    final now = DateTime.now();
    expect(picker.minDate, DateTime(now.year, now.month, now.day));
    expect(picker.highlightedDates, isEmpty);
  });

  testWidgets('choosing כפילות asks for the original', (tester) async {
    final harness = await pumpTeamTasks(tester, user: manager, board: board([hall, other]));
    await openTask(tester, 'o');
    await tester.tap(find.byKey(const Key('team-task-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-task-status-option-כפילות')));
    await tester.pumpAndSettle();
    expect(find.text('כפילות של איזו משימה?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('duplicate-original-t')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, contains('status:o:duplicate:t'));
  });

  testWidgets('the send button spins until the update is saved (round 4)', (tester) async {
    final harness = await pumpTeamTasks(tester, user: dana, board: board([other]));
    await openTask(tester, 'o');
    await tester.enterText(find.byKey(const Key('team-task-update-field')), 'עדכון');
    final gate = harness.repository.gate = Completer<void>();
    await tester.tap(find.byKey(const Key('team-task-update-send')));
    await tester.pump();
    expect(find.byKey(const Key('team-task-update-sending')), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('team-task-update-sending')), findsNothing);
  });

  testWidgets('adding an update shows it first', (tester) async {
    final logged = other.copyWith(updates: [
      TaskUpdateEntry(id: 'u0', text: 'ישן', at: DateTime(2026, 11, 2), byId: 'm1', byName: 'דנה'),
    ]);
    final harness = await pumpTeamTasks(tester, user: dana, board: board([logged]));
    await openTask(tester, 'o');
    await tester.enterText(find.byKey(const Key('team-task-update-field')), 'סגרנו מחיר');
    await tester.tap(find.byKey(const Key('team-task-update-send')));
    await tester.pump();
    expect(harness.repository.calls, ['log:o:סגרנו מחיר']);
    // The stream brings it back, newest first.
    await harness.deliver(
      tester,
      board([
        logged.copyWith(updates: [
          TaskUpdateEntry(
              id: 'u1', text: 'סגרנו מחיר', at: DateTime(2026, 11, 15), byId: 'm1', byName: 'דנה'),
          ...logged.updates,
        ]),
      ]),
    );
    await tester.pumpAndSettle();
    final first = tester.getTopLeft(find.text('סגרנו מחיר').last).dy;
    final second = tester.getTopLeft(find.text('ישן')).dy;
    expect(first, lessThan(second));
  });

  testWidgets('manager deletes only after the confirm', (tester) async {
    final harness = await pumpTeamTasks(tester, user: manager, board: board([hall]));
    await openTask(tester, 't');
    await tester.ensureVisible(find.byKey(const Key('team-task-delete')));
    await tester.tap(find.byKey(const Key('team-task-delete')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, isEmpty);
    await tester.tap(find.byKey(const Key('team-task-delete-confirm')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, ['delete:t']);
  });

  testWidgets('the header: the description under the title, a red 🗑 beside ✕',
      (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board([hall]));
    await openTask(tester, 't');
    final delete = tester.getRect(find.byKey(const Key('team-task-delete')));
    final close = tester.getRect(find.byKey(const Key('team-task-close')));
    expect((delete.center.dy - close.center.dy).abs(), lessThan(2));
    expect((delete.center.dx - close.center.dx).abs(), lessThan(60));
    final icon = tester.widget<Icon>(find.descendant(
        of: find.byKey(const Key('team-task-delete')), matching: find.byType(Icon)));
    expect(icon.color, Colors.red);
    final title = tester.getRect(find.byKey(const Key('team-task-edit-title')));
    final description = tester.getRect(find.byKey(const Key('team-task-edit-description')));
    final divider = tester.getRect(find.descendant(
        of: find.byKey(const Key('team-task-panel')), matching: find.byType(Divider)).first);
    expect(description.top, greaterThanOrEqualTo(title.bottom - 1));
    expect(description.bottom, lessThanOrEqualTo(divider.top + 1));
  });

  testWidgets('a delete closes the sheet, also when the list updates first', (tester) async {
    final harness = await pumpTeamTasks(tester, user: manager, board: board([hall]));
    await openTask(tester, 't');
    await tester.ensureVisible(find.byKey(const Key('team-task-delete')));
    await tester.tap(find.byKey(const Key('team-task-delete')));
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    harness.repository.gate = gate;
    await tester.tap(find.byKey(const Key('team-task-delete-confirm')));
    await tester.pump();
    // The stream drops the task while the confirm still waits for the backend.
    await harness.deliver(tester, board([]));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(ModalBarrier), findsOneWidget); // the app's own route only
  });

  testWidgets('an owner sees no delete and no editing', (tester) async {
    await pumpTeamTasks(tester, user: dana, board: board([other]));
    await openTask(tester, 'o');
    expect(find.byKey(const Key('team-task-delete')), findsNothing);
    expect(find.byKey(const Key('team-task-edit-title')), findsNothing);
  });

  testWidgets('wide window shows the task in a centred panel', (tester) async {
    await pumpTeamTasks(tester, user: manager, board: board([hall]), size: teamWideSize);
    await openTask(tester, 't');
    final panel = tester.getSize(find.byKey(const Key('team-task-panel')));
    expect(panel.width, lessThanOrEqualTo(960));
    expect(find.byKey(const Key('team-task-edit-title')), findsOneWidget);
  });

}
