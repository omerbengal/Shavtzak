import '../../../core/utils/event_stretch.dart';
import '../../../domain/entities/assignment.dart';

/// The custom hours one copied assignment carries: both strings are set, as
/// `yyyy-MM-ddTHH:mm` on the Israel wall clock.
typedef CopiedHours = ({String? start, String? end});

/// The hours each copy carries when an event is duplicated with its custom
/// hours, keyed by the id of the assignment it is copied from. A copy that
/// carries none has no entry.
///
/// Hours move by [shiftDays] whole calendar days (the clock times stay).
///
/// The backend wants one set of hours per member in an event, so a member
/// either brings their hours to every copy or to none:
/// - an ordinary member's hours are those of the first of their assignments
///   that holds usable hours, moved, and every copy of theirs gets that pair,
///   also a copy whose source row held none;
/// - a member flagged `allowMultipleAssignments` stands for different people
///   per slot, so each of their copies is moved by its own hours;
/// - hours that cannot be read count as none;
/// - an ordinary member with any assignment id in [dropped] gets no hours on
///   any copy, so a partial set of ids can never leave them with a mix.
Map<String, CopiedHours> movedCustomHours(
  List<Assignment> assignments,
  int shiftDays, {
  Set<String> dropped = const {},
}) {
  final ordinaryHours = <String, CopiedHours?>{};
  final ordinaryDropped = <String>{};
  for (final assignment in assignments) {
    if (_isPool(assignment)) continue;
    if (dropped.contains(assignment.id)) {
      ordinaryDropped.add(assignment.teamMemberId);
    }
    if (ordinaryHours[assignment.teamMemberId] == null) {
      ordinaryHours[assignment.teamMemberId] = _moved(assignment, shiftDays);
    }
  }

  final result = <String, CopiedHours>{};
  for (final assignment in assignments) {
    final CopiedHours? hours;
    if (_isPool(assignment)) {
      hours = dropped.contains(assignment.id)
          ? null
          : _moved(assignment, shiftDays);
    } else if (ordinaryDropped.contains(assignment.teamMemberId)) {
      hours = null;
    } else {
      hours = ordinaryHours[assignment.teamMemberId];
    }
    if (hours != null) result[assignment.id] = hours;
  }
  return result;
}

/// Whether [assignment]'s member is exempt from the one-set-of-hours rule.
bool _isPool(Assignment assignment) =>
    assignment.teamMember?.allowMultipleAssignments == true;

/// [assignment]'s own hours moved by [shiftDays]; null when it has none.
CopiedHours? _moved(Assignment assignment, int shiftDays) {
  if (!assignment.hasCustomHours) return null;
  final start = shiftWallMoment(assignment.customStartAt, shiftDays);
  final end = shiftWallMoment(assignment.customEndAt, shiftDays);
  if (start == null || end == null) return null;
  return (start: start, end: end);
}
