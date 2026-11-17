import 'package:equatable/equatable.dart';

import '../../domain/entities/category.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';
import '../../domain/entities/team_task.dart';
import 'israel_calendar.dart';

/// Pure rules of the team tasks screen ("משימות"): late, permissions,
/// grouping, sorting, the filter and whether a member gets the tab. `now` is
/// always injected.

/// Late = a deadline before today's Israel date while the task is still open
/// or in progress. The deadline day itself is not late.
bool isTeamTaskLate(TeamTask task, DateTime now) {
  final deadline = task.deadlineDate;
  if (deadline == null || !task.status.isActive) return false;
  return deadline.isBefore(IsraelCalendar.calendarDay(now));
}

/// Admins and members with "ניהול משימות" see and edit every task.
bool canManageTeamTasks(TeamMember member) => member.isAdmin || member.canManageTasks;

bool isTeamTaskOwner(TeamTask task, String memberId) => task.ownerIds.contains(memberId);

const String unknownMemberLabel = 'חבר צוות לא ידוע';

/// The owners in [TeamTask.ownerIds] order, with whether each is a permanent
/// team member (the app's mark); an id with no joined member reads
/// "חבר צוות לא ידוע", unmarked.
List<({String id, String name, bool permanent})> teamTaskOwnerChips(TeamTask task) {
  final byId = {for (final member in task.owners) member.id: member};
  return [
    for (final id in task.ownerIds)
      (
        id: id,
        name: byId[id]?.name ?? unknownMemberLabel,
        permanent: byId[id]?.isPermanent ?? false,
      ),
  ];
}

/// The owners' names in [TeamTask.ownerIds] order; an id with no joined member
/// (deleted from the team) reads "חבר צוות לא ידוע".
List<String> teamTaskOwnerNames(TeamTask task) {
  final byId = {for (final member in task.owners) member.id: member.name};
  return [for (final id in task.ownerIds) byId[id] ?? unknownMemberLabel];
}

/// The task's owners as the backend derives them: its assignees, once each.
List<String> teamTaskOwnerIds(TeamTask task) => task.assigneeIds.toSet().toList();

/// What the "המשימות שלי" tab lists for [viewerId]: every task they own.
List<TeamTask> myTeamTaskRows(List<TeamTask> tasks, String viewerId) => [
      for (final task in tasks)
        if (task.ownerIds.contains(viewerId)) task,
    ];

/// One event inside a category's card (16/11/2026): its title row and the
/// tasks linked to that event alone.
class TeamTaskSection extends Equatable {
  /// Unique in the list: the card's key and the event's.
  final String key;
  final String eventId;

  /// The event, or null when it was deleted.
  final Event? event;
  final String label;
  final List<TeamTask> tasks;

  const TeamTaskSection({
    required this.key,
    required this.eventId,
    required this.event,
    required this.label,
    required this.tasks,
  });

  /// The same section with [task] drawn in place of its own version.
  TeamTaskSection withTask(TeamTask task) => TeamTaskSection(
        key: key,
        eventId: eventId,
        event: event,
        label: label,
        tasks: _swapTask(tasks, task),
      );

  @override
  List<Object?> get props => [key, eventId, event, label, tasks];
}

List<TeamTask> _swapTask(List<TeamTask> tasks, TeamTask task) =>
    [for (final t in tasks) t.id == task.id ? task : t];

/// One card of the list (16/11/2026). A category's card holds, on top, the
/// tasks of the category itself ([tasks]), then, as a list of their own, the
/// tasks linked to several events of it ([severalEventTasks], Omer
/// 16/11/2026: two separate lists), then a [sections] entry per event of the
/// category. Any other card (an event with no category, a pending event, a
/// topic, "ללא שיוך", [type] null) has only [tasks].
class TeamTaskGroup extends Equatable {
  final String key;
  final String label;
  final TaskLinkType? type;

  /// What a new task from the card's "+" is linked to; null for "ללא שיוך".
  final TaskLink? link;

  /// The card's own event (an event with no category), for its 👥 button.
  final Event? event;
  final List<TeamTask> tasks;

  /// A category's card: the tasks linked to several of its events, shown
  /// after [tasks] behind a separator.
  final List<TeamTask> severalEventTasks;
  final List<TeamTaskSection> sections;

  const TeamTaskGroup({
    required this.key,
    required this.label,
    required this.type,
    required this.tasks,
    this.link,
    this.event,
    this.severalEventTasks = const [],
    this.sections = const [],
  });

  /// Every task on the card, once each.
  List<TeamTask> get allTasks {
    final seen = <String>{};
    return [
      for (final task in [
        ...tasks,
        ...severalEventTasks,
        for (final section in sections) ...section.tasks,
      ])
        if (seen.add(task.id)) task,
    ];
  }

  /// The same card with [task] drawn in place of its own version, where it
  /// is (the task held in its place, TeamTaskHoldPlace).
  TeamTaskGroup withTask(TeamTask task) => TeamTaskGroup(
        key: key,
        label: label,
        type: type,
        link: link,
        event: event,
        tasks: _swapTask(tasks, task),
        severalEventTasks: _swapTask(severalEventTasks, task),
        sections: [for (final section in sections) section.withTask(task)],
      );

  @override
  List<Object?> get props =>
      [key, label, type, link, event, tasks, severalEventTasks, sections];
}

const String noLinkLabel = 'ללא שיוך';

/// The group's title for [task]'s link. A link whose target is gone (a
/// deleted event, category or topic) still gets a group of its own.
String teamTaskLinkLabel(TeamTask task) {
  final link = task.link;
  if (link == null) return noLinkLabel;
  switch (link.type) {
    case TaskLinkType.event:
      // Several events (16/11/2026): every one still there, by name.
      if (task.hasSeveralEvents && task.events.isNotEmpty) {
        return task.events.map((event) => event.name).join(', ');
      }
      return task.event?.name ?? 'אירוע שנמחק';
    case TaskLinkType.category:
      return task.category?.name ?? 'קטגוריה שנמחקה';
    case TaskLinkType.topic:
      return task.topic?.name ?? 'נושא שנמחק';
    case TaskLinkType.pendingEvent:
      return task.pendingEvent?.name ?? 'אירוע שעוד לא נוצר';
  }
}

/// The order inside a group: still-active tasks first; then the urgency,
/// גבוהה, רגילה, נמוכה (Omer, 16/11/2026); then the deadline (none last) and
/// the title. Done, cancelled and duplicate stay at the bottom, in the same
/// order among themselves.
int compareTeamTasks(TeamTask a, TeamTask b) {
  final activeA = a.status.isActive ? 0 : 1;
  final activeB = b.status.isActive ? 0 : 1;
  if (activeA != activeB) return activeA.compareTo(activeB);
  // The enum runs נמוכה, רגילה, גבוהה: the higher index first.
  final byUrgency = b.urgency.index.compareTo(a.urgency.index);
  if (byUrgency != 0) return byUrgency;
  final byDeadline = _compareDeadlines(a.deadline, b.deadline);
  if (byDeadline != 0) return byDeadline;
  return a.title.compareTo(b.title);
}

int _compareDeadlines(String? a, String? b) {
  if (a == b) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  // yyyy-MM-dd strings compare in date order.
  return a.compareTo(b);
}

/// The order of events (16/11/2026): the ones that have not ended yet (one
/// going on now counts) first, the nearest start first; then the ones that
/// ended, the latest end first. A deleted event (null) goes last.
int compareEventsByNearest(Event? a, Event? b, DateTime now) {
  if (a == null || b == null) return a == null ? (b == null ? 0 : 1) : -1;
  final today = IsraelCalendar.calendarDay(now);
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  final pastA = day(a.endDate).isBefore(today);
  final pastB = day(b.endDate).isBefore(today);
  if (pastA != pastB) return pastA ? 1 : -1;
  final byDate = pastA ? b.endDate.compareTo(a.endDate) : a.startDate.compareTo(b.startDate);
  if (byDate != 0) return byDate;
  return a.name.compareTo(b.name);
}

/// [tasks] as the list's cards (Omer, 16/11/2026):
/// - a card per category, by name (א-ב): on top the tasks linked to the
///   category itself, then those linked to several events of it (such a task
///   shows on every category of its events), then a section per event
///   of the category with the tasks linked to it alone, ordered by
///   [compareEventsByNearest];
/// - an event with no category (or a deleted one) keeps a card of its own,
///   after the categories, in the same event order; a task linked to several
///   events shows on each such event's card;
/// - then the pending events and the topics, each by name; "ללא שיוך" last.
///
/// [categories] name the categories of the tasks' events.
List<TeamTaskGroup> groupTeamTasks(
  List<TeamTask> tasks,
  DateTime now, {
  List<Category> categories = const [],
}) {
  final categoryById = {for (final category in categories) category.id: category};

  final categoryLabels = <String, String>{};
  final categoryTop = <String, List<TeamTask>>{};
  final categorySeveral = <String, List<TeamTask>>{};
  final categorySections = <String, Map<String, List<TeamTask>>>{};
  final sectionEvents = <String, Event?>{};
  final sectionLabels = <String, String>{};
  final otherCards = <String, List<TeamTask>>{};
  final otherLabels = <String, String>{};
  final otherTypes = <String, TaskLinkType?>{};
  final otherLinks = <String, TaskLink?>{};
  final otherEvents = <String, Event?>{};

  void addOther(String key, TeamTask task, String label, TaskLinkType? type, TaskLink? link,
      [Event? event]) {
    final list = otherCards.putIfAbsent(key, () => []);
    if (!list.any((t) => t.id == task.id)) list.add(task);
    otherLabels[key] = label;
    otherTypes[key] = type;
    otherLinks[key] = link;
    if (event != null) otherEvents[key] = event;
  }

  void addCategoryTop(String categoryId, String label, TeamTask task, {bool several = false}) {
    categoryLabels[categoryId] = label;
    final list = (several ? categorySeveral : categoryTop).putIfAbsent(categoryId, () => []);
    if (!list.any((t) => t.id == task.id)) list.add(task);
  }

  for (final task in tasks) {
    final link = task.link;
    if (link == null) {
      addOther('none', task, noLinkLabel, null, null);
      continue;
    }
    switch (link.type) {
      case TaskLinkType.category:
        addCategoryTop(link.id, task.category?.name ?? 'קטגוריה שנמחקה', task);
      case TaskLinkType.topic:
      case TaskLinkType.pendingEvent:
        addOther('${link.type.key}:${link.id}', task, teamTaskLinkLabel(task), link.type, link);
      case TaskLinkType.event:
        final eventsById = {for (final event in task.events) event.id: event};
        if (task.event != null) eventsById[link.id] = task.event!;
        final ids = task.linkedEventIds;
        final several = ids.length > 1;
        for (final id in ids) {
          final event = eventsById[id];
          final categoryId = event?.categoryId;
          final category = categoryId == null ? null : categoryById[categoryId];
          if (event != null && category != null) {
            if (several) {
              addCategoryTop(category.id, category.name, task, several: true);
            } else {
              categoryLabels[category.id] = category.name;
              categorySections
                  .putIfAbsent(category.id, () => {})
                  .putIfAbsent(id, () => [])
                  .add(task);
              sectionEvents[id] = event;
              sectionLabels[id] = event.name;
            }
          } else {
            addOther('event:$id', task, event?.name ?? 'אירוע שנמחק', TaskLinkType.event,
                TaskLink(TaskLinkType.event, id), event);
          }
        }
    }
  }

  final categoryCards = [
    for (final categoryId in categoryLabels.keys)
      TeamTaskGroup(
        key: 'category:$categoryId',
        label: categoryLabels[categoryId]!,
        type: TaskLinkType.category,
        link: TaskLink(TaskLinkType.category, categoryId),
        tasks: [...?categoryTop[categoryId]]..sort(compareTeamTasks),
        severalEventTasks: [...?categorySeveral[categoryId]]..sort(compareTeamTasks),
        sections: [
          for (final entry in (categorySections[categoryId] ?? const <String, List<TeamTask>>{}).entries)
            TeamTaskSection(
              key: 'category:$categoryId/event:${entry.key}',
              eventId: entry.key,
              event: sectionEvents[entry.key],
              label: sectionLabels[entry.key]!,
              tasks: [...entry.value]..sort(compareTeamTasks),
            ),
        ]..sort((a, b) => compareEventsByNearest(a.event, b.event, now)),
      ),
  ]..sort((a, b) => a.label.compareTo(b.label));

  final others = [
    for (final key in otherCards.keys)
      TeamTaskGroup(
        key: key,
        label: otherLabels[key]!,
        type: otherTypes[key],
        link: otherLinks[key],
        event: otherEvents[key],
        tasks: [...otherCards[key]!]..sort(compareTeamTasks),
      ),
  ];
  int rank(TaskLinkType? type) => switch (type) {
        TaskLinkType.event => 0,
        TaskLinkType.pendingEvent => 1,
        TaskLinkType.topic => 2,
        TaskLinkType.category => 2,
        null => 3,
      };
  others.sort((a, b) {
    final byRank = rank(a.type).compareTo(rank(b.type));
    if (byRank != 0) return byRank;
    if (a.type == TaskLinkType.event) {
      final byEvent = compareEventsByNearest(a.event, b.event, now);
      if (byEvent != 0) return byEvent;
    }
    return a.label.compareTo(b.label);
  });
  return [...categoryCards, ...others];
}

/// What the list shows: a set of statuses, optionally some owners (any of
/// them, round 7: several like the statuses), some urgencies (16/11/2026),
/// one link, only the late tasks ("באיחור", round 7) and a search text.
class TeamTaskFilter extends Equatable {
  final Set<TeamTaskStatus> statuses;

  /// The owners shown; empty = everyone.
  final Set<String> ownerIds;

  /// The urgencies shown; empty = every one.
  final Set<TeamTaskUrgency> urgencies;
  final TaskLink? link;

  /// Only the tasks that are late ([isTeamTaskLate]).
  final bool lateOnly;

  /// Words looked up in a task's title and description.
  final String query;

  const TeamTaskFilter({
    required this.statuses,
    this.ownerIds = const {},
    this.urgencies = const {},
    this.link,
    this.lateOnly = false,
    this.query = '',
  });

  /// What is still to be done: "פתוחה" and "בטיפול" (Omer, round 8).
  static const TeamTaskFilter initial = TeamTaskFilter(statuses: {
    TeamTaskStatus.open,
    TeamTaskStatus.inProgress,
  });

  bool get isInitial => this == initial;

  /// Whether the statuses differ from the initial ones (the status chip's
  /// colour; the owner and link have their own chips).
  bool get statusesChanged =>
      statuses.length != initial.statuses.length || !statuses.containsAll(initial.statuses);

  /// Whether any of the filters (status, owner, urgency, link, late) is set.
  bool get anyFilterSet =>
      statusesChanged || ownerIds.isNotEmpty || urgencies.isNotEmpty || link != null || lateOnly;

  /// [query] as [normalizeTeamTaskSearch] makes it; empty = no search.
  String get searchText => normalizeTeamTaskSearch(query);

  TeamTaskFilter copyWith({
    Set<TeamTaskStatus>? statuses,
    Set<String>? ownerIds,
    Set<TeamTaskUrgency>? urgencies,
    TaskLink? Function()? link,
    bool? lateOnly,
    String? query,
  }) =>
      TeamTaskFilter(
        statuses: statuses ?? this.statuses,
        ownerIds: ownerIds ?? this.ownerIds,
        urgencies: urgencies ?? this.urgencies,
        link: link != null ? link() : this.link,
        lateOnly: lateOnly ?? this.lateOnly,
        query: query ?? this.query,
      );

  @override
  List<Object?> get props => [
        statuses.toList()..sort((a, b) => a.index - b.index),
        ownerIds.toList()..sort(),
        urgencies.toList()..sort((a, b) => a.index - b.index),
        link,
        lateOnly,
        query,
      ];
}

/// [tasks] that pass [filter]. An event link matches a task linked to that
/// event among others; a category link also matches the tasks linked to an
/// event of that category ([eventCategoryById]: event id → category id).
/// [now] decides "באיחור" (default: the clock).
List<TeamTask> applyTeamTaskFilter(
  List<TeamTask> tasks,
  TeamTaskFilter filter,
  Map<String, String?> eventCategoryById, {
  DateTime? now,
  Map<String, String> categoryNameById = const {},
}) {
  bool linkMatches(TeamTask task) {
    final wanted = filter.link;
    if (wanted == null) return true;
    final link = task.link;
    if (link == null) return false;
    if (link == wanted) return true;
    if (link.type != TaskLinkType.event) return false;
    final ids = task.linkedEventIds;
    if (wanted.type == TaskLinkType.event) return ids.contains(wanted.id);
    if (wanted.type != TaskLinkType.category) return false;
    String? categoryOf(String id) =>
        eventCategoryById[id] ??
        task.events.where((event) => event.id == id).firstOrNull?.categoryId;
    return ids.any((id) => categoryOf(id) == wanted.id);
  }

  final today = now ?? DateTime.now();
  final search = filter.searchText;
  return [
    for (final task in tasks)
      if (filter.statuses.contains(task.status) &&
          (filter.ownerIds.isEmpty || task.ownerIds.any(filter.ownerIds.contains)) &&
          (filter.urgencies.isEmpty || filter.urgencies.contains(task.urgency)) &&
          linkMatches(task) &&
          (!filter.lateOnly || isTeamTaskLate(task, today)) &&
          (search.isEmpty ||
              teamTaskSearchText(task, eventCategoryById, categoryNameById).contains(search)))
        task,
  ];
}

/// Text made comparable for the search: lower-cased, without Hebrew points
/// (niqqud, cantillation), geresh / gershayim or quotes, and with the spaces
/// collapsed, so "בנגל" finds "עומר בנגל" and צה"ל finds צהל.
String normalizeTeamTaskSearch(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[\u0591-\u05BD\u05BF-\u05C7\u05F3\u05F4\'"`]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Everything the search looks in for [task] (Omer, msg 4500), normalized
/// and in one string: what it belongs to (its link's name, its events and
/// their categories), the title, the description, the update log (texts and
/// writers), the owners' names and the contacts.
String teamTaskSearchText(
  TeamTask task,
  Map<String, String?> eventCategoryById,
  Map<String, String> categoryNameById,
) {
  final parts = <String>[
    if (task.link != null) teamTaskLinkLabel(task),
    for (final event in task.events) event.name,
    if (task.event != null) task.event!.name,
    for (final id in task.linkedEventIds)
      if (categoryNameById[eventCategoryById[id]] case final name?) name,
    task.title,
    task.description,
    for (final entry in task.updates) ...[entry.text, entry.byName ?? ''],
    for (final owner in task.owners) owner.name,
    for (final contact in task.contacts) ...[contact.name, contact.role, contact.phone],
  ];
  return normalizeTeamTaskSearch(parts.join('\n'));
}

/// Whether [member] gets the "משימות" tab: a manager always; anyone else when
/// one of [myTasks] (the tasks they own) is not cancelled or a duplicate.
bool showTeamTasksTab(TeamMember member, List<TeamTask> myTasks) {
  if (canManageTeamTasks(member)) return true;
  return myTasks.any(
      (task) => task.status != TeamTaskStatus.cancelled && task.status != TeamTaskStatus.duplicate);
}

/// The events a task can be linked to: those that have not ended before
/// today's Israel date, the nearest first (Omer, round 2).
List<Event> linkableEvents(List<Event> events, DateTime now) {
  final today = IsraelCalendar.calendarDay(now);
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  return [
    for (final event in events)
      if (!day(event.endDate).isBefore(today)) event,
  ]..sort((a, b) => a.startDate.compareTo(b.startDate));
}
