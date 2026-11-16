import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/environment_service.dart';
import 'package:shavtzak/presentation/screens/team_task/team_tasks_place.dart';
import 'package:shavtzak/presentation/screens/user/user_navigation_shell.dart';

import '../../support/task_fixtures.dart';

void main() {
  tearDown(() => EnvironmentService.instance.setTestMode(false));

  test('the admin card opens /team-tasks, with the test prefix in /test', () {
    EnvironmentService.instance.setTestMode(false);
    expect(teamTasksRoute, '/team-tasks');
    EnvironmentService.instance.setTestMode(true);
    expect(teamTasksRoute, '/test/team-tasks');
  });

  test('the members\' bar has no "משימות" tab (Omer, 16/11/2026)', () {
    expect(memberTabRoutes, ['/user/assignments', '/user/constraints', '/user/du-yomi']);
  });

  group('teamTasksRedirect', () {
    test('only admins open the screen; anyone else goes home', () {
      expect(teamTasksRedirect('/team-tasks', buildMember()), '/user/assignments');
      expect(teamTasksRedirect('/team-tasks', buildMember(canManageTasks: true)),
          '/user/assignments');
      expect(teamTasksRedirect('/team-tasks', buildMember(isAdmin: true)), isNull);
    });

    test('the former members\' tab leads an admin to the screen, anyone else home', () {
      expect(teamTasksRedirect('/user/team-tasks', buildMember(isAdmin: true)), '/team-tasks');
      expect(teamTasksRedirect('/user/team-tasks', buildMember()), '/user/assignments');
    });

    test('other routes stay', () {
      expect(teamTasksRedirect('/tasks', buildMember()), isNull);
      expect(teamTasksRedirect('/du-yomi', buildMember()), isNull);
      expect(teamTasksRedirect('/team-tasks-x', buildMember()), isNull);
      expect(teamTasksRedirect('/user/assignments', buildMember(isAdmin: true)), isNull);
    });
  });
}
