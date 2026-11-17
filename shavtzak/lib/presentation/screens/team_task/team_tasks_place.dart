import '../../../core/services/environment_service.dart';
import '../../../domain/entities/team_member.dart';

/// Where the team tasks screen ("משימות") is shown.
enum TeamTasksPlace {
  /// The "משימות" tab of the member's bottom bar (back on 17/11/2026), shown
  /// to a manager and to a member who owns a task (`memberShowsTeamTasksTab`).
  tab('/user/team-tasks'),

  /// A full screen of its own, opened from the admin home's "משימות" card.
  standalone('/team-tasks');

  const TeamTasksPlace(this.path);

  /// The route, without the environment prefix.
  final String path;

  /// The route in the current environment.
  String get route => '${EnvironmentService.instance.routePrefix}$path';
}

/// Where [user] goes instead of [strippedRoute] (the route without the
/// environment prefix), or null to stay: the standalone screen is the
/// admins' (from the admin home); everyone else has the tab. The router
/// keeps the query (`?task=<id>`, a notification's task) on the way.
String? teamTasksRedirect(String strippedRoute, TeamMember user) {
  if (user.isAdmin) return null;
  final standalone = TeamTasksPlace.standalone.path;
  if (strippedRoute == standalone || strippedRoute.startsWith('$standalone/')) {
    return TeamTasksPlace.tab.path;
  }
  return null;
}

/// Who gets the team-task notifications ("שובצת למשימה"): today an admin.
/// The backend's twin is `canReceiveTaskPush` in functions/src/push.ts:
/// change both together.
bool canGetTeamTaskNotifications(TeamMember user) => user.isAdmin;
