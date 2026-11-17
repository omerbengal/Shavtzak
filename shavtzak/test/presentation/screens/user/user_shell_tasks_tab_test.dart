import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_task.dart';
import 'package:shavtzak/presentation/bloc/team_task/team_task_bloc.dart';
import 'package:shavtzak/presentation/screens/user/user_navigation_shell.dart';

import '../../../support/fake_team_task_repository.dart';
import '../../../support/task_fixtures.dart';
import '../../../support/team_task_fixtures.dart';

void main() {
  final dana = buildMember(id: 'm1');

  Future<TeamTaskState> stateFor(List<TeamTask> tasks, {bool manage = false}) async {
    final repository = FakeTeamTaskRepository();
    final bloc = TeamTaskBloc(repository: repository);
    addTearDown(bloc.close);
    final viewer = buildMember(id: 'm1', canManageTasks: manage);
    bloc.add(TeamTasksSubscribe(viewer));
    await pumpEventQueue();
    repository.controller.add(TeamTaskBoard(tasks: tasks));
    return bloc.stream.firstWhere((s) => s is TeamTasksLoaded);
  }

  test('tab hidden for a member with no tasks', () async {
    final state = await stateFor(const []);
    expect(memberShowsTeamTasksTab(dana, state, currentIndex: 0), isFalse);
    expect(memberTabRoutes(withTeamTasks: false),
        ['/user/assignments', '/user/constraints', '/user/du-yomi']);
  });

  test('tab hidden before the tasks arrive', () {
    expect(memberShowsTeamTasksTab(dana, const TeamTasksInitial(), currentIndex: 0), isFalse);
  });

  test('tab shown for an owner and for canManageTasks', () async {
    final owned = await stateFor([buildTeamTask(assigneeIds: ['m1'])]);
    expect(memberShowsTeamTasksTab(dana, owned, currentIndex: 0), isTrue);
    expect(
      memberShowsTeamTasksTab(buildMember(id: 'm1', canManageTasks: true),
          const TeamTasksInitial(), currentIndex: 0),
      isTrue,
    );
    expect(memberTabRoutes(withTeamTasks: true).last, '/user/team-tasks');
  });

  test('a member already on the tab keeps it', () {
    expect(memberShowsTeamTasksTab(dana, const TeamTasksInitial(), currentIndex: 3), isTrue);
  });
}
