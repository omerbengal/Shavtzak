import '../../../../core/utils/search_utils.dart';
import '../../../../core/utils/task_progress.dart';
import '../../../../core/utils/task_utils.dart';
import '../../../../core/utils/validators.dart';
import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/task_item.dart';
import '../../../../domain/entities/team_member.dart';

/// The editing screen's rules, as pure functions.

/// Why a stage's start and end cannot be saved, or null when they can. The
/// same messages as the stage form.
String? validateStageTimes(String start, String end) {
  if (start.isNotEmpty && !isValidDueTime(start)) {
    return 'שעת ההתחלה אינה תקינה. יש להזין שעה כמו 08:00, או להשאיר ריק.';
  }
  if (end.isNotEmpty && !isValidDueTime(end)) {
    return 'שעת הסיום אינה תקינה. יש להזין שעה כמו 10:45, או להשאיר ריק.';
  }
  if (end.isNotEmpty && start.isEmpty) return 'שעת סיום דורשת שעת התחלה.';
  if (end.isNotEmpty && end.compareTo(start) <= 0) {
    return 'שעת הסיום חייבת להיות אחרי שעת ההתחלה.';
  }
  return null;
}

/// Why an assembly time cannot be saved, or null.
String? validateAssemblyTime(String time) {
  if (time.isEmpty || isValidDueTime(time)) return null;
  return 'שעת ההתייצבות אינה תקינה. יש להזין שעה כמו 08:30, או להשאיר ריק.';
}

/// Why a list of contacts cannot be saved, or null.
String? validateContacts(List<StageContact> contacts) {
  for (final contact in contacts) {
    if (contact.name.trim().isEmpty) return 'לכל איש קשר נדרש שם.';
    final phoneError = Validators.validatePhoneNumber(contact.phone);
    if (phoneError != null) return 'הטלפון של ${contact.name}: $phoneError';
  }
  return null;
}

String? validateRequiredText(String text, String what) =>
    text.trim().isEmpty ? 'חובה להזין $what' : null;

String? validateAssignees(List<String> ids) =>
    ids.isEmpty ? 'חובה לבחור לפחות אחראי אחד' : null;

/// Who the "אחראי" filter offers: the event's assignees now, and anyone named
/// on one of its tasks, so a task still held by someone taken off the event
/// can be found. By name.
List<TeamMember> assigneeFilterMembers(
  EventTaskBoard board,
  List<TeamMember> eventAssignees,
) {
  final byId = {for (final member in eventAssignees) member.id: member};
  for (final task in board.tasks) {
    for (final member in task.assignees) {
      byId.putIfAbsent(member.id, () => member);
    }
  }
  return byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

/// The tasks of [stage] the filters keep. A stage whose title matches the
/// query keeps all its tasks that pass the assignee filter.
List<TaskItem> visibleStageTasks(
  EventTaskBoard board,
  Stage stage, {
  required String query,
  required String? assigneeId,
  required DateTime now,
}) {
  final tasks = board.tasksOf(stage.id);
  final stageMatches = query.trim().isNotEmpty &&
      normalizeForSearch(stage.title)
          .toLowerCase()
          .contains(normalizeForSearch(query.trim()).toLowerCase());
  return filterTasks(
    tasks,
    now: now,
    query: stageMatches ? '' : query,
    onlyAssigneeId: assigneeId,
  );
}

/// The members' first names, for the assignees cell.
String firstName(String name) {
  final trimmed = name.trim();
  final space = trimmed.indexOf(' ');
  return space < 0 ? trimmed : trimmed.substring(0, space);
}

/// Up to two initials, for the assignee circle.
String initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  return parts.take(2).map((part) => part.substring(0, 1)).join();
}

/// How fast the list scrolls while a dragged task is held at [pointerY],
/// in px per second: negative (up) within [edge] of the list's [top],
/// positive (down) within [edge] of its [bottom], zero elsewhere. Faster
/// nearer the edge, up to [maxSpeed] at it or beyond.
double edgeScrollSpeed({
  required double pointerY,
  required double top,
  required double bottom,
  required double edge,
  required double maxSpeed,
}) {
  final fromTop = pointerY - top;
  if (fromTop < edge) {
    return -maxSpeed * ((edge - fromTop) / edge).clamp(0.0, 1.0);
  }
  final fromBottom = bottom - pointerY;
  if (fromBottom < edge) {
    return maxSpeed * ((edge - fromBottom) / edge).clamp(0.0, 1.0);
  }
  return 0;
}
