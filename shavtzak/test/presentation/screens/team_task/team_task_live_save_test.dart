import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/debounced_saver.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_task.dart';
import 'package:shavtzak/presentation/bloc/team_task/team_task_bloc.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';
import '../../../support/team_tasks_harness.dart';

/// Omer, 16/11/2026 (msg 4207): an existing task's owners and events have no
/// save button: every tick saves, rapid ticks as one call, a refusal rolls
/// back, closing the picker sends what waits. A new task's form is unchanged.
void main() {
  final dana = buildMember(id: 'm1', name: 'דנה');
  final yossi = buildMember(id: 'm2', name: 'יוסי');
  final manager = buildMember(id: 'mgr', name: 'מנהלת', isAdmin: true);
  final first = buildEvent(id: 'e1', name: 'ראשון', startDate: DateTime(2099, 1, 10));
  final second = buildEvent(id: 'e2', name: 'שני', startDate: DateTime(2099, 2, 10));

  final hall = buildTeamTask(id: 't', title: 'אולם', assigneeIds: ['m1']).copyWith(owners: [dana]);
  final onEvent = buildTeamTask(
    id: 'ev',
    title: 'של אירוע',
    assigneeIds: ['m1'],
    link: const TaskLink(TaskLinkType.event, 'e1'),
    eventIds: const ['e1'],
    event: first,
    events: [first],
  ).copyWith(owners: [dana]);

  TeamTaskBoard board(List<TeamTask> tasks) => TeamTaskBoard(
        tasks: tasks,
        members: [dana, yossi, manager],
        events: [first, second],
      );

  Future<TeamTasksHarness> openTask(WidgetTester tester, TeamTask task) async {
    final harness =
        await pumpTeamTasks(tester, user: manager, board: board([task]), size: teamWideSize);
    await tester.tap(find.byKey(const Key('team-tab-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('team-task-row-${task.id}')));
    await tester.pumpAndSettle();
    return harness;
  }

  // The event's name in the picker (the board shows it too).
  Finder name(String id, String text) =>
      find.descendant(of: find.byKey(Key('task-link-option-$id')), matching: find.text(text));

  final wait = DebouncedSaver.defaultDelay + const Duration(milliseconds: 50);

  testWidgets('owners: no save button; rapid ticks are one update with all of them',
      (tester) async {
    final harness = await openTask(tester, hall);
    await tester.tap(find.byKey(const Key('team-task-edit-owners')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-value-save')), findsNothing);
    expect(find.text('שמירה'), findsNothing);

    await tester.tap(find.byKey(const Key('edit-assignee-m2')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('edit-assignee-mgr')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(harness.repository.updated, isEmpty);
    // The task shows the new owners at once, before anything is sent.
    final shown = (harness.bloc.state as TeamTasksLoaded).taskById('t')!;
    expect(shown.assigneeIds, ['m1', 'm2', 'mgr']);

    await tester.pump(wait);
    await tester.pumpAndSettle();
    expect(harness.repository.updated, hasLength(1));
    expect(harness.repository.updated.single.assigneeIds, ['m1', 'm2', 'mgr']);
  });

  testWidgets('owners: a refused save rolls the ticks back and says so', (tester) async {
    final harness = await openTask(tester, hall);
    harness.repository.failWith =
        Exception('Failed backend mutation teamTask.update: אין הרשאה');
    await tester.tap(find.byKey(const Key('team-task-edit-owners')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-assignee-m2')));
    await tester.pump(wait);
    await tester.pumpAndSettle();
    expect(harness.repository.updated, hasLength(1));
    expect(find.text('אין הרשאה'), findsOneWidget);
    final box = tester.widget<CheckboxListTile>(find.byKey(const Key('edit-assignee-m2')));
    expect(box.value, isFalse);
    final shown = (harness.bloc.state as TeamTasksLoaded).taskById('t')!;
    expect(shown.assigneeIds, ['m1']);
  });

  testWidgets('owners: closing right after a tick sends it at once', (tester) async {
    final harness = await openTask(tester, hall);
    await tester.tap(find.byKey(const Key('team-task-edit-owners')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-assignee-m2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('live-owners-close')));
    await tester.pump();
    await tester.pump();
    expect(harness.repository.updated.single.assigneeIds, ['m1', 'm2']);
    await tester.pump(wait);
    await tester.pumpAndSettle();
    expect(harness.repository.updated, hasLength(1));
  });

  testWidgets('events: a tap on an event name saves it, no button; none marked is not saved',
      (tester) async {
    final harness = await openTask(tester, onEvent);
    await tester.tap(find.byKey(const Key('team-task-edit-link')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-link-confirm-events')), findsNothing);
    expect(find.text('סגירה'), findsOneWidget);

    await tester.tap(name('e2', 'שני'));
    await tester.pump(wait);
    await tester.pumpAndSettle();
    expect(harness.repository.updated.single.linkedEventIds, ['e1', 'e2']);
    // Still open: more events can be marked.
    expect(find.byKey(const Key('task-link-search')), findsOneWidget);

    // Unmark both: a hint, nothing sent, the saved events stay.
    await tester.tap(name('e2', 'שני'));
    await tester.pump();
    await tester.tap(name('e1', 'ראשון'));
    await tester.pump(wait);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('task-link-no-event-hint')), findsOneWidget);
    expect(harness.repository.updated, hasLength(1));
    await tester.tap(find.byKey(const Key('task-link-close')));
    await tester.pumpAndSettle();
    expect(harness.repository.updated, hasLength(1));
    final shown = (harness.bloc.state as TeamTasksLoaded).taskById('ev')!;
    expect(shown.linkedEventIds, ['e1', 'e2']);
  });
}
