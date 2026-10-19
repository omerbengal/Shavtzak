import 'package:flutter/foundation.dart';

import '../../../core/services/environment_service.dart';

/// Where the דו יומי screens are shown.
enum TasksPlace {
  /// The "דו יומי" tab of the member's bottom bar, at `/user/du-yomi`.
  tab('/user/du-yomi'),

  /// A full screen of its own, at `/du-yomi`, opened from the admin home.
  standalone('/du-yomi');

  const TasksPlace(this.path);

  /// The event list's route, without the environment prefix.
  final String path;

  /// The event list, in the current environment.
  String get listRoute => '${EnvironmentService.instance.routePrefix}$path';

  /// One event's screen, in the current environment.
  String eventRoute(String eventId) => '$listRoute/$eventId';
}

/// What a [TasksPlace] last showed in this app session, so coming back to it
/// shows the same thing even after the screens were rebuilt.
///
/// Nothing yet means the place opens straight into the nearest event that has
/// not ended. After that it opens the event last looked at, or stays on the
/// list once the member has chosen the list.
abstract final class TasksResume {
  static final Map<TasksPlace, String> _events = {};
  static final Set<TasksPlace> _lists = {};

  static bool isListChosen(TasksPlace place) => _lists.contains(place);

  static String? lastEvent(TasksPlace place) => _events[place];

  static void rememberEvent(TasksPlace place, String eventId) {
    _lists.remove(place);
    _events[place] = eventId;
  }

  static void rememberList(TasksPlace place) {
    _events.remove(place);
    _lists.add(place);
  }

  @visibleForTesting
  static void debugReset() {
    _events.clear();
    _lists.clear();
  }
}
