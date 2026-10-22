import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';
import '../constants/constraint_status.dart';

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
/// Collision is [DateConstraint.blocksEventAssignment], the rule assignment
/// availability uses: recurring constraints count on their matching days and
/// an event's hours run from its assembly time when it has one.
///
/// Sorted approved → pending → rejected, then by member name.
List<EventConstraintCollision> findEventConstraintCollisions({
  required Event event,
  required List<TeamMember> members,
}) {
  final collisions = <EventConstraintCollision>[
    for (final member in members)
      if (member.isPermanent && member.isActive && !member.isArchived)
        for (final constraint in member.constraints)
          if (constraint.isUnavailability &&
              constraint.blocksEventAssignment(event))
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
