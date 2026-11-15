import '../../../core/services/environment_service.dart';

/// Where the team tasks screen ("משימות") is shown.
enum TeamTasksPlace {
  /// The "משימות" tab of the member's bottom bar.
  tab('/user/team-tasks'),

  /// A full screen of its own, opened from the admin home's "משימות" card.
  standalone('/team-tasks');

  const TeamTasksPlace(this.path);

  /// The route, without the environment prefix.
  final String path;

  /// The route in the current environment.
  String get route => '${EnvironmentService.instance.routePrefix}$path';
}
