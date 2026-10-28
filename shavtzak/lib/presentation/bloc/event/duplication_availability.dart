import 'package:equatable/equatable.dart';

import '../../../core/utils/constraint_labels.dart';
import '../../../core/utils/event_stretch.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/event.dart';

/// How the duplication dialog treats one copied assignment against the new
/// event.
class DuplicationAvailability extends Equatable {
  /// The dialog lists the member as a conflict and starts it marked for removal.
  final bool flagged;

  /// The admin may untick the removal and keep the member. False when the
  /// backend would refuse the member even with `bypassAvailability`, so the
  /// row stays locked to removal and the batch can never fail on a kept member.
  final bool canKeep;

  /// Why the member is flagged, one Hebrew line each. Empty when not flagged.
  final List<String> reasons;

  const DuplicationAvailability({
    required this.flagged,
    this.canKeep = true,
    this.reasons = const [],
  });

  /// Not flagged: copied as is.
  static const DuplicationAvailability clear =
      DuplicationAvailability(flagged: false);

  @override
  List<Object?> get props => [flagged, canKeep, reasons];
}

/// Judges [assignment]'s member against [proposedEvent], the event being
/// created by the duplication (new dates and times).
///
/// In order:
/// 1. member document gone: locked;
/// 2. inactive or archived: locked;
/// 3. can no longer do the role: locked;
/// 4. `allowMultipleAssignments` members are exempt from availability;
/// 5. otherwise the same rule as assigning ([TeamMember.isAvailableForEventWithTime]):
///    a permanent member is flagged with each blocking constraint, a
///    non-permanent one with "didn't give availability" (a new event is never
///    in their list). Both stay keepable: the duplication sends its batch with
///    `bypassAvailability`.
///
/// Rules 1-3 are the ones the backend refuses even with the bypass, and no
/// screen in the app assigns such a member either.
///
/// [window] is the stretch of time the copy would hold the member for: the
/// custom hours moved to the new dates, or null for the new event's own
/// stretch. Only rule 5 reads it, and only for a permanent member.
DuplicationAvailability duplicationAvailability({
  required Assignment assignment,
  required Event proposedEvent,
  WallInterval? window,
}) {
  final member = assignment.teamMember;
  if (member == null) {
    return const DuplicationAvailability(
      flagged: true,
      canKeep: false,
      reasons: ['חבר/ת הצוות לא נמצא/ה'],
    );
  }
  if (!member.isActive || member.isArchived) {
    return const DuplicationAvailability(
      flagged: true,
      canKeep: false,
      reasons: ['לא פעיל/ה'],
    );
  }
  if (!member.canPerformRole(assignment.roleType)) {
    return const DuplicationAvailability(
      flagged: true,
      canKeep: false,
      reasons: ['לא מוסמך/ת לתפקיד'],
    );
  }
  if (member.allowMultipleAssignments) return DuplicationAvailability.clear;

  if (member.isAvailableForEventWithTime(proposedEvent, window: window)) {
    return DuplicationAvailability.clear;
  }

  if (member.isPermanent) {
    return DuplicationAvailability(
      flagged: true,
      reasons: member
          .constraintsBlockingWindow(window ?? eventStretch(proposedEvent))
          .map(constraintStatusLabel)
          .toList(),
    );
  }
  return const DuplicationAvailability(
    flagged: true,
    reasons: ['לא ציין/ה זמינות לאירוע'],
  );
}
