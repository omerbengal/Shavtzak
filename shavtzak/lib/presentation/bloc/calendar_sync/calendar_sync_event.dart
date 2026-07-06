import 'package:equatable/equatable.dart';
import '../../../domain/entities/team_member.dart';

/// Base class for calendar sync events
abstract class CalendarSyncEvent extends Equatable {
  const CalendarSyncEvent();

  @override
  List<Object?> get props => [];
}

/// Initialize the calendar sync service
class InitializeCalendarSync extends CalendarSyncEvent {
  final String? calendarId;

  const InitializeCalendarSync({
    this.calendarId,
  });

  @override
  List<Object?> get props => [calendarId];
}

/// Sync a constraint to the calendar when it's approved
class SyncConstraintToCalendar extends CalendarSyncEvent {
  final String constraintId;
  final TeamMember teamMember;
  final DateConstraint constraint;

  const SyncConstraintToCalendar({
    required this.constraintId,
    required this.teamMember,
    required this.constraint,
  });

  @override
  List<Object?> get props => [constraintId, teamMember, constraint];
}

/// Remove a constraint from the calendar
class RemoveConstraintFromCalendar extends CalendarSyncEvent {
  final String constraintId;

  const RemoveConstraintFromCalendar({
    required this.constraintId,
  });

  @override
  List<Object?> get props => [constraintId];
}

/// Sync all approved constraints for a team member
class SyncAllApprovedConstraints extends CalendarSyncEvent {
  final TeamMember teamMember;

  const SyncAllApprovedConstraints({
    required this.teamMember,
  });

  @override
  List<Object?> get props => [teamMember];
}

/// Retry all failed syncs
class RetryFailedSyncs extends CalendarSyncEvent {
  const RetryFailedSyncs();
}

/// Retry a specific failed sync
class RetryFailedSync extends CalendarSyncEvent {
  final String constraintId;
  final TeamMember teamMember;
  final DateConstraint constraint;

  const RetryFailedSync({
    required this.constraintId,
    required this.teamMember,
    required this.constraint,
  });

  @override
  List<Object?> get props => [constraintId, teamMember, constraint];
}

/// Clear sync state for a constraint (used when constraint is deleted)
class ClearConstraintSyncState extends CalendarSyncEvent {
  final String constraintId;

  const ClearConstraintSyncState({
    required this.constraintId,
  });

  @override
  List<Object?> get props => [constraintId];
}

/// Check sync status for a constraint
class CheckSyncStatus extends CalendarSyncEvent {
  final String constraintId;

  const CheckSyncStatus({
    required this.constraintId,
  });

  @override
  List<Object?> get props => [constraintId];
}

/// Validate all synced events with Google Calendar and reject constraints for deleted events
class ValidateSyncedEvents extends CalendarSyncEvent {
  const ValidateSyncedEvents();
}

/// Perform bidirectional sync between app and Google Calendar
class PerformBidirectionalSync extends CalendarSyncEvent {
  const PerformBidirectionalSync();
}

/// Sync app event attendees and constraints from one admin action.
class SyncEventsAndConstraints extends CalendarSyncEvent {
  const SyncEventsAndConstraints();
}

/// Sync an app event to the calendar
class SyncAppEventToCalendar extends CalendarSyncEvent {
  final String eventId;
  final String eventName;
  final DateTime startDate;
  final DateTime endDate;
  final String assemblyTime;
  final String startTime;
  final String actualShowStartTime;
  final String endTime;
  final String? location;

  const SyncAppEventToCalendar({
    required this.eventId,
    required this.eventName,
    required this.startDate,
    required this.endDate,
    required this.assemblyTime,
    required this.startTime,
    required this.actualShowStartTime,
    required this.endTime,
    this.location,
  });

  @override
  List<Object?> get props => [
        eventId,
        eventName,
        startDate,
        endDate,
        assemblyTime,
        startTime,
        actualShowStartTime,
        endTime,
        location,
      ];
}

/// Remove an app event from the calendar
class RemoveAppEventFromCalendar extends CalendarSyncEvent {
  final String eventId;

  const RemoveAppEventFromCalendar({
    required this.eventId,
  });

  @override
  List<Object?> get props => [eventId];
}

/// Add attendee to app event
class AddAttendeeToAppEvent extends CalendarSyncEvent {
  final String eventId;
  final String email;

  const AddAttendeeToAppEvent({
    required this.eventId,
    required this.email,
  });

  @override
  List<Object?> get props => [eventId, email];
}

/// Remove attendee from app event
class RemoveAttendeeFromAppEvent extends CalendarSyncEvent {
  final String eventId;
  final String email;

  const RemoveAttendeeFromAppEvent({
    required this.eventId,
    required this.email,
  });

  @override
  List<Object?> get props => [eventId, email];
}

/// Sync all attendees for app event
class SyncAttendeesForAppEvent extends CalendarSyncEvent {
  final String eventId;

  const SyncAttendeesForAppEvent({
    required this.eventId,
  });

  @override
  List<Object?> get props => [eventId];
}

/// Targeted attendee sync for a single assignment change.
///
/// Unlike [SyncAttendeesForAppEvent] (which re-pushes the whole attendee
/// roster and makes Google email every existing attendee), this notifies only
/// the member who was actually added and/or removed. It falls back to a full
/// re-sync internally only for the "invite all permanent when unassigned"
/// roster transitions, where the entire attendee set genuinely changes.
class SyncAttendeeForAssignmentChange extends CalendarSyncEvent {
  final String eventId;

  /// Member newly assigned by this change (null for a pure delete).
  final String? addedMemberId;

  /// Member whose assignment was removed/reassigned-away (null for a pure
  /// create).
  final String? removedMemberId;

  const SyncAttendeeForAssignmentChange({
    required this.eventId,
    this.addedMemberId,
    this.removedMemberId,
  });

  @override
  List<Object?> get props => [eventId, addedMemberId, removedMemberId];
}

/// Handle team member email changed
class OnTeamMemberEmailChanged extends CalendarSyncEvent {
  final String teamMemberId;
  final String oldEmail;
  final String newEmail;

  const OnTeamMemberEmailChanged({
    required this.teamMemberId,
    required this.oldEmail,
    required this.newEmail,
  });

  @override
  List<Object?> get props => [teamMemberId, oldEmail, newEmail];
}

/// TEMP: Manual one-time backfill for attendee emails on existing constraint events.
class BackfillConstraintEventAttendees extends CalendarSyncEvent {
  const BackfillConstraintEventAttendees();
}

/// Check calendar authentication on admin app entry.
/// Runs once when the admin shell loads to detect manual reconnect needs early.
class CheckCalendarAuthOnAdminAppLoad extends CalendarSyncEvent {
  const CheckCalendarAuthOnAdminAppLoad();
}
