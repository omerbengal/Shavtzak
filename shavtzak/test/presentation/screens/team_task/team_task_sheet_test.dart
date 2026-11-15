import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/stage.dart';
import 'package:shavtzak/domain/entities/team_task.dart';
import 'package:shavtzak/presentation/widgets/date_picker_dialog.dart';

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

  final withSubtasks = buildTeamTask(id: 't', title: 'אולם', subtasks: const [
    TeamSubtask(
      id: 's1',
      title: 'הצעת מחיר',
      assigneeIds: ['m1'],
      contacts: [StageContact(id: 'c1', name: 'רונית', phone: '050-1234567', role: 'אולם')],
    ),
    TeamSubtask(id: 's2', title: 'חוזה', assigneeIds: ['m2']),
  ]).copyWith(owners: [dana, yossi]);
  final other = buildTeamTask(id: 'o', title: 'משימה מקורית', assigneeIds: ['m1'])
      .copyWith(owners: [dana]);

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
      expect(find.byKey(Key('team-task-status-option-$label')), findsOneWidget);
    }
  });

  testWidgets('the deadline opens the app date picker, as for a constraint', (tester) async {
    // The calendar's month header needs a tablet's width with the test font.
    await pumpTeamTasks(tester,
        user: manager, board: board([other]), size: const Size(1200, 1000));
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
    final harness =
        await pumpTeamTasks(tester, user: manager, board: board([withSubtasks, other]));
    await openTask(tester, 't');
    await tester.tap(find.byKey(const Key('team-task-status')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-task-status-option-כפילות')));
    await tester.pumpAndSettle();
    expect(find.text('כפילות של איזו משימה?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('duplicate-original-o')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, contains('status:t:duplicate:o'));
  });

  testWidgets('owner can tick only their own subtask', (tester) async {
    final harness = await pumpTeamTasks(tester, user: dana, board: board([withSubtasks]));
    // Her subtask is her row; its contact is on its own screen, with the phone.
    await openTask(tester, 's1');
    expect(find.textContaining('רונית'), findsWidgets);
    // The parent opens from the subtask's "תת-משימה של" line.
    await tester.tap(find.byKey(const Key('team-task-kind')));
    await tester.pumpAndSettle();
    final mineBox = tester.widget<Checkbox>(find.byKey(const Key('team-subtask-check-s1')));
    final theirsBox = tester.widget<Checkbox>(find.byKey(const Key('team-subtask-check-s2')));
    expect(mineBox.onChanged, isNotNull);
    expect(theirsBox.onChanged, isNull);
    await tester.tap(find.byKey(const Key('team-subtask-check-s1')));
    await tester.pump();
    expect(harness.repository.calls, ['subtask:t:s1:true']);
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
          TaskUpdateEntry(id: 'u1', text: 'סגרנו מחיר', at: DateTime(2026, 11, 15), byId: 'm1', byName: 'דנה'),
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
    final harness = await pumpTeamTasks(tester, user: manager, board: board([withSubtasks]));
    await openTask(tester, 't');
    await tester.ensureVisible(find.byKey(const Key('team-task-delete')));
    await tester.tap(find.byKey(const Key('team-task-delete')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, isEmpty);
    await tester.tap(find.byKey(const Key('team-task-delete-confirm')));
    await tester.pumpAndSettle();
    expect(harness.repository.calls, ['delete:t']);
  });

  testWidgets('a delete closes the sheet, also when the list updates first', (tester) async {
    final harness = await pumpTeamTasks(tester, user: manager, board: board([withSubtasks]));
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
    await pumpTeamTasks(tester, user: manager, board: board([withSubtasks]), size: teamWideSize);
    await openTask(tester, 't');
    final panel = tester.getSize(find.byKey(const Key('team-task-panel')));
    expect(panel.width, lessThanOrEqualTo(960));
    expect(find.byKey(const Key('team-task-edit-title')), findsOneWidget);
  });

  testWidgets('a subtask opens in its own task screen: status and log go to it', (tester) async {
    final harness = await pumpTeamTasks(tester, user: manager, board: board([withSubtasks]));
    await tester.tap(find.byKey(const Key('team-tab-all')));
    await tester.pumpAndSettle();
    await openTask(tester, 't');
    expect(find.text('משימת אב'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('team-subtask-row-s1')));
    await tester.tap(find.byKey(const Key('team-subtask-row-s1')));
    await tester.pumpAndSettle();
    expect(find.text('תת-משימה של: אולם'), findsOneWidget);
    // A subtask has no subtasks of its own (the one found is the parent's,
    // under it).
    expect(find.byKey(const Key('team-task-add-subtask')), findsOneWidget);
    await tester.tap(find.byKey(const Key('team-task-status')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('team-task-status-option-בטיפול')).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('team-task-update-field')).last, 'ביקשתי הצעות');
    await tester.tap(find.byKey(const Key('team-task-update-send')).last);
    await tester.pumpAndSettle();
    expect(harness.repository.calls, ['status:t/s1:inProgress', 'log:t/s1:ביקשתי הצעות']);
  });

  testWidgets('adding a first subtask to a task with owners asks first', (tester) async {
    final harness = await pumpTeamTasks(tester, user: manager, board: board([other]));
    await openTask(tester, 'o');
    await tester.ensureVisible(find.byKey(const Key('team-task-add-subtask')));
    await tester.tap(find.byKey(const Key('team-task-add-subtask')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('first-subtask-split')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-team-task-title')), 'חוזה');
    await tester.tap(find.byKey(const Key('new-team-task-save')));
    await tester.pumpAndSettle();
    final saved = harness.repository.updated.single;
    expect(saved.subtasks.single.title, 'חוזה');
    expect(saved.assigneeIds, isEmpty);
  });
}
