import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/environment_service.dart';
import 'package:shavtzak/presentation/screens/team_task/team_tasks_place.dart';
import 'package:shavtzak/presentation/screens/user/user_navigation_shell.dart';

import '../../support/task_fixtures.dart';

void main() {
  tearDown(() => EnvironmentService.instance.setTestMode(false));

  test('the admin card opens /team-tasks, the members have /user/team-tasks', () {
    EnvironmentService.instance.setTestMode(false);
    expect(TeamTasksPlace.standalone.route, '/team-tasks');
    expect(TeamTasksPlace.tab.route, '/user/team-tasks');
  });

  test('test prefix routes work', () {
    EnvironmentService.instance.setTestMode(true);
    expect(TeamTasksPlace.standalone.route, '/test/team-tasks');
    expect(TeamTasksPlace.tab.route, '/test/user/team-tasks');
  });

  test('the משימות tab is the 4th of the members bar (back on 17/11/2026)', () {
    expect(memberTabRoutes(withTeamTasks: true),
        ['/user/assignments', '/user/constraints', '/user/du-yomi', '/user/team-tasks']);
    expect(memberTabRoutes(withTeamTasks: true)[kTeamTasksTab], TeamTasksPlace.tab.path);
  });

  group('teamTasksRedirect', () {
    test('a member who is not an admin goes from the admin screen to the tab', () {
      expect(teamTasksRedirect('/team-tasks', buildMember(canManageTasks: true)),
          '/user/team-tasks');
      expect(teamTasksRedirect('/team-tasks', buildMember()), '/user/team-tasks');
    });

    test('an admin stays; other routes are not touched', () {
      expect(teamTasksRedirect('/team-tasks', buildMember(isAdmin: true)), isNull);
      expect(teamTasksRedirect('/user/team-tasks', buildMember(isAdmin: true)), isNull);
      expect(teamTasksRedirect('/user/team-tasks', buildMember()), isNull);
      expect(teamTasksRedirect('/tasks', buildMember()), isNull);
      expect(teamTasksRedirect('/du-yomi', buildMember()), isNull);
      expect(teamTasksRedirect('/team-tasks-x', buildMember()), isNull);
    });
  });

  test('task notifications: every active, unarchived member (17/11/2026)', () {
    expect(canGetTeamTaskNotifications(buildMember()), isTrue);
    expect(canGetTeamTaskNotifications(buildMember(isAdmin: true)), isTrue);
    expect(canGetTeamTaskNotifications(buildMember(isActive: false)), isFalse);
    expect(canGetTeamTaskNotifications(buildMember(isArchived: true)), isFalse);
    expect(
        canGetTeamTaskNotifications(buildMember(isAdmin: true, isArchived: true)),
        isFalse);
  });
}
