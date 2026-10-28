import '../../domain/entities/assignment.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';
import '../constants/constraint_status.dart';
import 'event_stretch.dart';

/// One permanent member's unavailability constraint that falls on an event.
class EventConstraintCollision {
  final TeamMember member;
  final DateConstraint constraint;

  const EventConstraintCollision({
    required this.member,
    required this.constraint,
  });
}

/// Every unavailability constraint of an active, permanent member that
/// collides with [event], whatever its status (approved, pending or rejected).
///
/// Collision is [constraintOverlapsStretch], the rule assignment availability
/// uses: recurring constraints count on their matching days and an event's
/// hours run from its assembly time when it has one.
///
/// A member is judged against the windows they hold in the event: each of
/// their assignments' own window ([Assignment.windowIn], their custom hours
/// when they have them). [assignments] are the event's assignments; ones from
/// other events are ignored. A member with no assignment in the event, or whose
/// assignments carry no usable hours, is judged against the event's whole
/// stretch, as before. A member in several roles with different hours is listed
/// for a constraint when it overlaps at least one of their windows.
///
/// Sorted approved → pending → rejected, then by member name.
List<EventConstraintCollision> findEventConstraintCollisions({
  required Event event,
  required List<TeamMember> members,
  List<Assignment> assignments = const [],
}) {
  final stretch = eventStretch(event);
  final windowsByMember = <String, List<WallInterval>>{};
  for (final assignment in assignments) {
    if (assignment.eventId != event.id) continue;
    windowsByMember
        .putIfAbsent(assignment.teamMemberId, () => <WallInterval>[])
        .add(assignment.windowIn(event));
  }

  final collisions = <EventConstraintCollision>[
    for (final member in members)
      if (member.isPermanent && member.isActive && !member.isArchived)
        for (final constraint in member.constraints)
          if (constraint.isUnavailability &&
              (windowsByMember[member.id] ?? [stretch]).any(
                  (window) => constraintOverlapsStretch(constraint, window)))
            EventConstraintCollision(member: member, constraint: constraint),
  ];

  int statusRank(ConstraintStatus status) => switch (status) {
        ConstraintStatus.approved => 0,
        ConstraintStatus.pending => 1,
        ConstraintStatus.rejected => 2,
      };

  collisions.sort((a, b) {
    final byStatus = statusRank(a.constraint.status)
        .compareTo(statusRank(b.constraint.status));
    if (byStatus != 0) return byStatus;
    return a.member.name.compareTo(b.member.name);
  });
  return collisions;
}
