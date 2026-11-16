import '../../../core/services/environment_service.dart';
import '../../../domain/entities/team_member.dart';

/// The team tasks screen ("משימות"): a screen of its own, opened only from
/// the "משימות" card on the admins' home (Omer, 16/11/2026: no tab in the
/// members' bar).
const String teamTasksPath = '/team-tasks';

/// Where the members' tab used to be; old links and saved pages still open it.
const String formerTeamTasksTabPath = '/user/team-tasks';

/// [teamTasksPath] in the current environment.
String get teamTasksRoute => '${EnvironmentService.instance.routePrefix}$teamTasksPath';

/// Where [user] goes instead of [strippedRoute] (the route without the
/// environment prefix), or null to stay: the screen is the admins' only, so
/// anyone else goes to their home tab; the former tab leads an admin to the
/// screen.
String? teamTasksRedirect(String strippedRoute, TeamMember user) {
  bool under(String path) => strippedRoute == path || strippedRoute.startsWith('$path/');
  if (under(formerTeamTasksTabPath)) return user.isAdmin ? teamTasksPath : '/user/assignments';
  if (!user.isAdmin && under(teamTasksPath)) return '/user/assignments';
  return null;
}

/// Who gets the team-task notifications ("שובצת למשימה"): whoever can open
/// this screen, today an admin ([teamTasksRedirect]). The backend's twin is
/// `canReceiveTaskPush` in functions/src/push.ts: change both together.
bool canGetTeamTaskNotifications(TeamMember user) => user.isAdmin;
