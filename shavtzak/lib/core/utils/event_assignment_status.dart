import '../../domain/entities/event.dart';
import '../../domain/entities/assignment.dart';

/// Enum representing the assignment status of an event
enum EventAssignmentStatus {
  /// No role quotas defined for this event
  noQuotas,

  /// No assignments have been made yet
  none,

  /// Some but not all required positions are filled
  partial,

  /// All required positions are filled
  complete,
}

/// Helper class to calculate assignment status for events
class EventAssignmentStatusHelper {
  /// Calculate the assignment status for an event
  ///
  /// Returns:
  /// - noQuotas: if event has no role requirements (all quotas are 0)
  /// - none: if event has quotas but no assignments
  /// - partial: if some (but not all) positions are filled
  /// - complete: if all positions are filled
  static EventAssignmentStatus calculateStatus(
    Event event,
    List<Assignment> assignments,
  ) {
    // Calculate total required positions
    final totalRequired = event.totalPeopleRequired;

    // If no quotas defined, return noQuotas
    if (totalRequired == 0) {
      return EventAssignmentStatus.noQuotas;
    }

    // Count filled positions
    final filledCount = assignments.length;

    // Determine status based on filled vs required
    if (filledCount == 0) {
      return EventAssignmentStatus.none;
    } else if (filledCount < totalRequired) {
      return EventAssignmentStatus.partial;
    } else {
      return EventAssignmentStatus.complete;
    }
  }
}
