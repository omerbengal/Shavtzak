import '../../domain/entities/assignment.dart';
import '../../domain/entities/team_member.dart';
import '../constants/constraint_status.dart';
import 'constraint_event_overlap.dart';

/// The constraints that were added or modified between [original] and
/// [updated], matched by id.
///
/// Removed constraints are deliberately excluded: dropping a constraint can
/// only free a member up, never create a new conflict.
List<DateConstraint> changedConstraints({
  required List<DateConstraint> original,
  required List<DateConstraint> updated,
}) {
  final originalById = {for (final c in original) c.id: c};
  return [
    for (final constraint in updated)
      if (originalById[constraint.id] != constraint) constraint,
  ];
}

/// Existing assignments that the constraints edited in *this* save would block.
///
/// Scoped deliberately narrowly, because the caller offers to delete whatever
/// this returns:
///
/// * Only constraints the admin actually added or changed are considered. The
///   member's other constraints are none of this save's business — and the
///   edit modal hides past and rejected ones, so reporting them names dates the
///   admin cannot even see.
/// * Only `approved` unavailability counts. That mirrors
///   [TeamMember.isAvailableForEvent]: a pending constraint does not block an
///   assignment yet, and an availability constraint grants time rather than
///   taking it away.
/// * Events that already ended are skipped — history is not a conflict to
///   resolve, and deleting those assignments would destroy the record.
/// * Overlap is decided by [constraintOverlapsEvent], the same date+time rule
///   the constraint screens use, so a 16:00–23:59 constraint leaves a
///   09:00–13:00 event on that day alone.
List<Assignment> findNewlyConflictingAssignments({
  required List<DateConstraint> originalConstraints,
  required List<DateConstraint> updatedConstraints,
  required List<Assignment> assignments,
  required DateTime now,
}) {
  final blocking = changedConstraints(
    original: originalConstraints,
    updated: updatedConstraints,
  )
      .where((constraint) =>
          constraint.isUnavailability &&
          constraint.status == ConstraintStatus.approved)
      .toList();

  if (blocking.isEmpty) return const [];

  final today = DateTime(now.year, now.month, now.day);
  final conflicting = <Assignment>[];

  for (final assignment in assignments) {
    final event = assignment.event;
    if (event == null) continue;

    final eventEnd =
        DateTime(event.endDate.year, event.endDate.month, event.endDate.day);
    if (eventEnd.isBefore(today)) continue;

    final isBlocked = blocking.any(
      (constraint) =>
          constraintOverlapsEvent(constraint: constraint, event: event),
    );
    if (isBlocked) conflicting.add(assignment);
  }

  return conflicting;
}
