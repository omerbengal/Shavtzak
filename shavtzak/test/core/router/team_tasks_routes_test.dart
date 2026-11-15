import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/environment_service.dart';
import 'package:shavtzak/presentation/screens/team_task/team_tasks_place.dart';

import '../../support/task_fixtures.dart';

void main() {
  tearDown(() => EnvironmentService.instance.setTestMode(false));

  test('admin card opens /team-tasks', () {
    EnvironmentService.instance.setTestMode(false);
    expect(TeamTasksPlace.standalone.route, '/team-tasks');
    expect(TeamTasksPlace.tab.route, '/user/team-tasks');
  });

  test('test prefix routes work', () {
    EnvironmentService.instance.setTestMode(true);
    expect(TeamTasksPlace.standalone.route, '/test/team-tasks');
    expect(TeamTasksPlace.tab.route, '/test/user/team-tasks');
  });

  group('teamTasksRedirect', () {
    test('a member who is not an admin goes from the admin screen to the tab', () {
      expect(teamTasksRedirect('/team-tasks', buildMember(canManageTasks: true)),
          '/user/team-tasks');
      expect(teamTasksRedirect('/team-tasks', buildMember()), '/user/team-tasks');
    });

    test('an admin stays; other routes are not touched', () {
      expect(teamTasksRedirect('/team-tasks', buildMember(isAdmin: true)), isNull);
      expect(teamTasksRedirect('/user/team-tasks', buildMember()), isNull);
      expect(teamTasksRedirect('/tasks', buildMember()), isNull);
      expect(teamTasksRedirect('/du-yomi', buildMember()), isNull);
    });
  });
}
