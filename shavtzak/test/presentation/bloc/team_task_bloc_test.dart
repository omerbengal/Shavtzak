import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/crud_action_result.dart';
import 'package:shavtzak/core/utils/team_task_rules.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_task.dart';
import 'package:shavtzak/presentation/bloc/team_task/team_task_bloc.dart';

import '../../support/fake_team_task_repository.dart';
import '../../support/task_fixtures.dart';
import '../../support/team_task_fixtures.dart';

void main() {
  late FakeTeamTaskRepository repository;
  late TeamTaskBloc bloc;
  final now = DateTime.utc(2026, 11, 15, 8);

  final dana = buildMember(id: 'm1', name: 'דנה');
  final yossi = buildMember(id: 'm2', name: 'יוסי');
  final manager = buildMember(id: 'mgr', name: 'מנהל', isAdmin: true);

  final mine = buildTeamTask(id: 'a', title: 'שלי', assigneeIds: ['m1'])
      .copyWith(owners: [dana]);
  final theirs = buildTeamTask(id: 'b', title: 'של יוסי', assigneeIds: ['m2'])
      .copyWith(owners: [yossi]);

  setUp(() {
    repository = FakeTeamTaskRepository();
    bloc = TeamTaskBloc(repository: repository, clock: () => now);
  });

  tearDown(() => bloc.close());

  Future<TeamTasksLoaded> loaded(bool Function(TeamTasksLoaded) test) async {
    final current = bloc.state;
    if (current is TeamTasksLoaded && test(current)) return current;
    return await bloc.stream
        .where((s) => s is TeamTasksLoaded && test(s))
        .cast<TeamTasksLoaded>()
        .first
        .timeout(const Duration(seconds: 2));
  }

  test('manager gets all and mine', () async {
    final managersTask = buildTeamTask(id: 'c', assigneeIds: ['mgr']);
    bloc.add(TeamTasksSubscribe(manager));
    await pumpEventQueue();
    repository.controller.add(TeamTaskBoard(tasks: [mine, theirs, managersTask]));
    final state = await loaded((s) => s.all.length == 3);
    expect(state.canManage, isTrue);
    expect(state.mine.map((t) => t.id), ['c']);
    expect(repository.viewers.single, manager);
  });

  test('owner gets only mine and canManage false', () async {
    bloc.add(TeamTasksSubscribe(dana));
    await pumpEventQueue();
    repository.controller.add(TeamTaskBoard(tasks: [mine]));
    final state = await loaded((s) => s.all.isNotEmpty);
    expect(state.canManage, isFalse);
    expect(state.mine.map((t) => t.id), ['a']);
    expect(state.mineGroups.single.tasks.single.id, 'a');
  });

  test('the filter hides cancelled tasks until it is changed', () async {
    final cancelled = buildTeamTask(id: 'x', status: TeamTaskStatus.cancelled);
    bloc.add(TeamTasksSubscribe(manager));
    await pumpEventQueue();
    repository.controller.add(TeamTaskBoard(tasks: [mine, cancelled]));
    var state = await loaded((s) => s.all.length == 2);
    expect(state.allGroups.expand((g) => g.tasks).map((t) => t.id), ['a']);
    bloc.add(TeamTaskFilterChanged(
        TeamTaskFilter.initial.copyWith(statuses: TeamTaskStatus.values.toSet())));
    state = await loaded((s) => s.allGroups.expand((g) => g.tasks).length == 2);
    expect(state.filter.statuses, hasLength(5));
  });

  test('optimistic status then rollback on error', () async {
    bloc.add(TeamTasksSubscribe(dana));
    await pumpEventQueue();
    repository.controller.add(TeamTaskBoard(tasks: [mine]));
    await loaded((s) => s.all.isNotEmpty);

    repository.gate = Completer<void>();
    repository.failWith = Exception('Failed backend mutation teamTask.setStatus: אין הרשאה');
    final completion = CrudActionCompleter();
    bloc.add(SetTeamTaskStatus('a', TeamTaskStatus.inProgress, completion: completion));
    await loaded((s) => s.all.single.status == TeamTaskStatus.inProgress);

    repository.gate!.complete();
    final result = await completion.future;
    expect(result.isFailure, isTrue);
    expect(result.message, 'אין הרשאה');
    await loaded((s) => s.all.single.status == TeamTaskStatus.open);
    expect(repository.calls, ['status:a:inProgress']);
  });

  test('optimistic status, kept once the backend accepts', () async {
    bloc.add(TeamTasksSubscribe(dana));
    await pumpEventQueue();
    repository.controller.add(TeamTaskBoard(tasks: [mine]));
    await loaded((s) => s.all.isNotEmpty);
    final completion = CrudActionCompleter();
    bloc.add(SetTeamTaskStatus('a', TeamTaskStatus.done, completion: completion));
    await loaded((s) => s.all.single.status == TeamTaskStatus.done);
    expect((await completion.future).isSuccess, isTrue);
    expect(repository.calls, ['status:a:done']);
  });

  test('a manager adding an owner shows the new name at once, not as unknown', () async {
    bloc.add(TeamTasksSubscribe(manager));
    await pumpEventQueue();
    repository.controller.add(TeamTaskBoard(tasks: [mine], members: [dana, yossi, manager]));
    await loaded((s) => s.all.isNotEmpty);
    repository.gate = Completer<void>();
    bloc.add(UpdateTeamTask(mine.copyWith(assigneeIds: ['m1', 'm2'], ownerIds: ['m1', 'm2'])));
    final state = await loaded((s) => s.all.single.ownerIds.length == 2);
    expect(teamTaskOwnerNames(state.all.single), ['דנה', 'יוסי']);
    repository.gate!.complete();
  });

  test('a manager linking a task to several events and raising its urgency: shown at once',
      () async {
    final first = buildEvent(id: 'e1', name: 'ראשון');
    final second = buildEvent(id: 'e2', name: 'שני');
    bloc.add(TeamTasksSubscribe(manager));
    await pumpEventQueue();
    repository.controller.add(
        TeamTaskBoard(tasks: [mine], events: [first, second], members: [dana, manager]));
    await loaded((s) => s.all.isNotEmpty);
    repository.gate = Completer<void>();
    bloc.add(UpdateTeamTask(mine.copyWith(
      link: () => const TaskLink(TaskLinkType.event, 'e1'),
      eventIds: ['e1', 'e2'],
      urgency: TeamTaskUrgency.high,
    )));
    final state = await loaded((s) => s.all.single.urgency == TeamTaskUrgency.high);
    expect(state.all.single.events.map((e) => e.name), ['ראשון', 'שני']);
    expect(state.all.single.hasSeveralEvents, isTrue);
    repository.gate!.complete();
  });

  test('an owner archived as a member shows as unknown', () async {
    final task = buildTeamTask(id: 't', assigneeIds: ['m1', 'gone']).copyWith(owners: [dana]);
    expect(teamTaskOwnerNames(task), ['דנה', 'חבר צוות לא ידוע']);
  });

  test('a task of a deleted event lands in the "אירוע שנמחק" group', () async {
    final orphan = buildTeamTask(id: 'o')
        .copyWith(link: () => const TaskLink(TaskLinkType.event, 'gone'));
    bloc.add(TeamTasksSubscribe(manager));
    await pumpEventQueue();
    repository.controller.add(TeamTaskBoard(tasks: [orphan]));
    final state = await loaded((s) => s.all.isNotEmpty);
    expect(state.allGroups.single.label, 'אירוע שנמחק');
  });

  test('a duplicate of a deleted task is labelled (המקורית נמחקה)', () async {
    final dup = buildTeamTask(id: 'd', status: TeamTaskStatus.duplicate, duplicateOfId: 'gone');
    final dup2 = buildTeamTask(id: 'e', status: TeamTaskStatus.duplicate, duplicateOfId: 'a');
    bloc.add(TeamTasksSubscribe(manager));
    await pumpEventQueue();
    repository.controller.add(TeamTaskBoard(tasks: [mine, dup, dup2]));
    final state = await loaded((s) => s.all.length == 3);
    expect(state.duplicateOriginalLabel(dup), '(המקורית נמחקה)');
    expect(state.duplicateOriginalLabel(dup2), 'שלי');
  });

  test('mutations go to the repository and report through the completer', () async {
    bloc.add(TeamTasksSubscribe(manager));
    await pumpEventQueue();
    repository.controller.add(TeamTaskBoard(tasks: [mine]));
    await loaded((s) => s.all.isNotEmpty);
    final results = <CrudActionCompleter>[for (var i = 0; i < 4; i++) CrudActionCompleter()];
    bloc.add(CreateTeamTask(mine, completion: results[0]));
    bloc.add(UpdateTeamTask(mine, completion: results[1]));
    bloc.add(AddTeamTaskUpdate('a', 'עדכון', completion: results[2]));
    bloc.add(DeleteTeamTask('a', completion: results[3]));
    for (final completion in results) {
      expect((await completion.future).isSuccess, isTrue);
    }
    expect(repository.calls, ['insert:שלי', 'update:a', 'log:a:עדכון', 'delete:a']);
  });

  test('after a stream error the same viewer subscribes again', () async {
    bloc.add(TeamTasksSubscribe(dana));
    await pumpEventQueue();
    repository.controller.addError(Exception('permission-denied'));
    await bloc.stream.firstWhere((s) => s is TeamTasksError).timeout(const Duration(seconds: 2));
    bloc.add(TeamTasksSubscribe(dana));
    await pumpEventQueue();
    expect(repository.viewers, hasLength(2));
    repository.controller.add(TeamTaskBoard(tasks: [mine]));
    final state = await loaded((s) => s.all.isNotEmpty);
    expect(state.mine.single.id, 'a');
  });

  test('a change to the viewer that keeps id and rights does not re-subscribe', () async {
    bloc.add(TeamTasksSubscribe(dana));
    await pumpEventQueue();
    repository.controller.add(TeamTaskBoard(tasks: [mine]));
    await loaded((s) => s.all.isNotEmpty);
    final renamed = buildMember(id: 'm1', name: 'דנה כהן');
    bloc.add(TeamTasksSubscribe(renamed));
    final state = await loaded((s) => s.viewer.name == 'דנה כהן');
    expect(repository.viewers, hasLength(1));
    expect(state.all.single.id, 'a');
    // Gaining "ניהול משימות" is a new query.
    bloc.add(TeamTasksSubscribe(buildMember(id: 'm1', canManageTasks: true)));
    await pumpEventQueue();
    expect(repository.viewers, hasLength(2));
  });
}
