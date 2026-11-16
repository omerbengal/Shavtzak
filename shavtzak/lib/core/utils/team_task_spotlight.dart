import 'package:equatable/equatable.dart';

import '../../domain/entities/team_task.dart';
import 'israel_calendar.dart';

/// Pure rules of "זרקור" (Spotlight), the quick pass over the viewer's tasks
/// in "המשימות שלי": one task at a time, the quietest first, with quick
/// actions. Most tasks have no deadline (production, 16/11/2026: 68 of 76
/// open ones), so the order comes from the update log, never the deadline.

/// When [task] last moved: its newest update, or null when it has none.
DateTime? lastTeamTaskUpdateAt(TeamTask task) {
  DateTime? newest;
  for (final entry in task.updates) {
    if (newest == null || entry.at.isAfter(newest)) newest = entry.at;
  }
  return newest;
}

/// The whole Israel days since [task]'s newest update (0 = updated today);
/// null when it has no update yet.
int? teamTaskQuietDays(TeamTask task, DateTime now) {
  final last = lastTeamTaskUpdateAt(task);
  if (last == null) return null;
  final today = IsraelCalendar.calendarDay(now);
  final day = IsraelCalendar.calendarDay(last);
  final days = today.difference(day).inDays;
  return days < 0 ? 0 : days;
}

/// From this many quiet days a card says so in orange.
const int spotlightQuietDays = 7;

/// The card's line about how quiet [task] is.
String teamTaskQuietLabel(TeamTask task, DateTime now) {
  final days = teamTaskQuietDays(task, now);
  if (days == null) return 'אין עדכון עדיין';
  if (days == 0) return 'עודכנה היום';
  if (days == 1) return 'עודכנה אתמול';
  return 'שקט $days ימים';
}

/// The tasks Spotlight goes through, in order: of [rows], those still to be
/// done (פתוחה / בטיפול), the quietest first. A task with no update yet is
/// the quietest; among those, the older one first. Ties: the title.
List<TeamTask> spotlightQueue(Iterable<TeamTask> rows) {
  final queue = [
    for (final task in rows)
      if (task.status.isActive) task,
  ];
  queue.sort((a, b) {
    final lastA = lastTeamTaskUpdateAt(a);
    final lastB = lastTeamTaskUpdateAt(b);
    if (lastA == null && lastB != null) return -1;
    if (lastA != null && lastB == null) return 1;
    final byTime = lastA == null ? a.createdAt.compareTo(b.createdAt) : lastA.compareTo(lastB!);
    if (byTime != 0) return byTime;
    return a.title.compareTo(b.title);
  });
  return queue;
}

/// What one pass did, for its last screen: the tasks closed (done or another
/// end status), those that got an update, and those left for later.
class SpotlightTally extends Equatable {
  final Set<String> closed;
  final Set<String> updated;
  final Set<String> skipped;

  const SpotlightTally({
    this.closed = const {},
    this.updated = const {},
    this.skipped = const {},
  });

  /// Every task the pass changed: the list flashes them on the way back.
  Set<String> get touched => {...closed, ...updated};

  /// "2 נסגרו · 2 עודכנו · אחת לפעם אחרת": an updated task that was then closed
  /// counts once, as closed. Empty parts are left out.
  String get summary {
    final updatedOnly = updated.difference(closed).length;
    final parts = [
      if (closed.isNotEmpty) closed.length == 1 ? 'אחת נסגרה' : '${closed.length} נסגרו',
      if (updatedOnly > 0) updatedOnly == 1 ? 'אחת עודכנה' : '$updatedOnly עודכנו',
      if (skipped.isNotEmpty) skipped.length == 1 ? 'אחת לפעם אחרת' : '${skipped.length} לפעם אחרת',
    ];
    return parts.isEmpty ? 'לא שינית כלום' : parts.join(' · ');
  }

  SpotlightTally close(String id) =>
      SpotlightTally(closed: {...closed, id}, updated: updated, skipped: skipped.difference({id}));

  SpotlightTally reopen(String id) =>
      SpotlightTally(closed: closed.difference({id}), updated: updated, skipped: skipped);

  SpotlightTally update(String id) =>
      SpotlightTally(closed: closed, updated: {...updated, id}, skipped: skipped.difference({id}));

  SpotlightTally skip(String id) => SpotlightTally(
        closed: closed,
        updated: updated,
        skipped: closed.contains(id) || updated.contains(id) ? skipped : {...skipped, id},
      );

  @override
  List<Object?> get props => [closed, updated, skipped];
}
