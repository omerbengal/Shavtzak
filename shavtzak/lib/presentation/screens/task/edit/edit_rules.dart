import '../../../../core/utils/search_utils.dart';
import '../../../../core/utils/task_progress.dart';
import '../../../../core/utils/task_utils.dart';
import '../../../../core/utils/validators.dart';
import '../../../../domain/entities/stage.dart';
import '../../../../domain/entities/subtask.dart';
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

// ---- order among tasks due at the same moment ----

/// Whether [moved] may be dropped beside [target] to change its place:
/// another task of the same stage, due at the same moment.
bool canReorderOnto(TaskItem moved, TaskItem target) =>
    moved.id != target.id &&
    moved.stageId == target.stageId &&
    moved.dueAt == target.dueAt;

/// [stageTasks] (in screen order) with [moved] put just before [target], or
/// just after it when [after], every task numbered by its new place.
///
/// Numbering the whole stage keeps it consistent: the tasks are sorted by
/// time first, so a number only decides among tasks due at the same moment.
List<TaskItem> reorderedStageTasks(
  List<TaskItem> stageTasks,
  TaskItem moved,
  TaskItem target, {
  required bool after,
}) {
  final rest = [
    for (final task in stageTasks)
      if (task.id != moved.id) task,
  ];
  final at = rest.indexWhere((task) => task.id == target.id);
  if (at < 0) return stageTasks;
  rest.insert(after ? at + 1 : at, moved);
  return [
    for (var i = 0; i < rest.length; i++) rest[i].copyWith(order: i),
  ];
}

/// Whether [reordered] puts any task in another place than [before] had it.
bool orderChanged(List<TaskItem> before, List<TaskItem> reordered) {
  if (before.length != reordered.length) return true;
  for (var i = 0; i < before.length; i++) {
    if (before[i].id != reordered[i].id) return true;
  }
  return false;
}

// ---- copying one value from a task to another ----

/// The values of a task that can be dragged onto another task.
enum TaskField {
  time('שעת התייצבות', 'שעת ההתייצבות'),
  description('תיאור', 'התיאור'),
  assignees('אחראים', 'האחראים'),
  subtasks('תתי-משימות', 'תתי-המשימות');

  const TaskField(this.label, this.definite);

  /// The value's Hebrew name: "תיאור".
  final String label;

  /// The same with "the": "התיאור".
  final String definite;
}

/// Whether [task] has nothing in [field].
bool isTaskFieldEmpty(TaskItem task, TaskField field) {
  switch (field) {
    case TaskField.time:
      return (task.assemblyTime ?? '').isEmpty;
    case TaskField.description:
      return task.description.trim().isEmpty;
    case TaskField.assignees:
      return task.assigneeIds.isEmpty;
    case TaskField.subtasks:
      return task.subtasks.isEmpty;
  }
}

/// Whether [a] and [b] already hold the same [field]: assignees in any
/// order, subtasks by their titles.
bool sameTaskField(TaskItem a, TaskItem b, TaskField field) {
  switch (field) {
    case TaskField.time:
      return (a.assemblyTime ?? '') == (b.assemblyTime ?? '');
    case TaskField.description:
      return a.description == b.description;
    case TaskField.assignees:
      return a.assigneeIds.toSet().length == b.assigneeIds.toSet().length &&
          a.assigneeIds.toSet().containsAll(b.assigneeIds);
    case TaskField.subtasks:
      if (a.subtasks.length != b.subtasks.length) return false;
      for (var i = 0; i < a.subtasks.length; i++) {
        if (a.subtasks[i].title != b.subtasks[i].title) return false;
      }
      return true;
  }
}

/// Whether [from] may hand its [field] to [to]: another task of the same
/// stage, with something to hand over.
bool canCopyField(TaskItem from, TaskItem to, TaskField field) =>
    from.id != to.id &&
    from.stageId == to.stageId &&
    !isTaskFieldEmpty(from, field);

/// [to] with [from]'s [field] in place of its own. Copied subtasks are new
/// ones ([newId] for each) and not ticked, so ticking one never ticks the
/// other.
TaskItem copyTaskField(
  TaskItem from,
  TaskItem to,
  TaskField field, {
  required String Function() newId,
}) {
  switch (field) {
    case TaskField.time:
      return to.copyWith(assemblyTime: from.assemblyTime);
    case TaskField.description:
      return to.copyWith(description: from.description);
    case TaskField.assignees:
      return to.copyWith(
        assigneeIds: [...from.assigneeIds],
        assignees: [...from.assignees],
      );
    case TaskField.subtasks:
      return to.copyWith(subtasks: [
        for (final subtask in from.subtasks)
          Subtask(id: newId(), title: subtask.title),
      ]);
  }
}
