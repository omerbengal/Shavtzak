import '../../domain/entities/assignment.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';
import '../../core/constants/constraint_status.dart';
import '../../core/constants/calendar_constants.dart';

/// Abstract database interface
/// This allows the app to be backend-agnostic
/// Implementations: FirestoreDatabase, SupabaseDatabase, LocalDatabase, etc.
abstract class DatabaseInterface {
  // ========== Team Members ==========

  /// Get all team members
  Future<List<TeamMember>> getTeamMembers();

  /// Get a team member by ID
  Future<TeamMember?> getTeamMemberById(String id);

  /// Get a team member by unique key (Feature 13: User authentication)
  Future<TeamMember?> getTeamMemberByUniqueKey(String uniqueKey);

  /// Insert a new team member
  Future<void> insertTeamMember(TeamMember member);

  /// Update an existing team member
  Future<void> updateTeamMember(TeamMember member);

  /// Delete a team member
  Future<void> deleteTeamMember(String id);

  
  // ========== Events ==========

  /// Get all events
  Future<List<Event>> getEvents();

  /// Get an event by ID
  Future<Event?> getEventById(String id);

  /// Insert a new event
  Future<void> insertEvent(Event event);

  /// Update an existing event
  Future<void> updateEvent(Event event);

  /// Delete an event
  Future<void> deleteEvent(String id);

  /// Get upcoming events (starts after today)
  Future<List<Event>> getUpcomingEvents();

  /// Get events by date range
  Future<List<Event>> getEventsByDateRange(DateTime start, DateTime end);

  // ========== Assignments ==========

  /// Get all assignments
  Future<List<Assignment>> getAssignments();

  /// Get an assignment by ID
  Future<Assignment?> getAssignmentById(String id);

  /// Get assignments for a specific event
  /// Returns assignments with populated team member data
  Future<List<Assignment>> getAssignmentsByEvent(String eventId);

  /// Get assignments for a specific team member
  /// Returns assignments with populated event data
  Future<List<Assignment>> getAssignmentsByPerson(String teamMemberId);

  /// Get assignments for a date range
  Future<List<Assignment>> getAssignmentsByDateRange(
    DateTime start,
    DateTime end,
  );

  /// Insert a new assignment
  Future<void> insertAssignment(Assignment assignment);

  /// Update an existing assignment
  Future<void> updateAssignment(Assignment assignment);

  /// Delete an assignment
  Future<void> deleteAssignment(String id);

  /// Delete all assignments for an event
  Future<void> deleteAssignmentsByEvent(String eventId);

  /// Delete all assignments for a team member
  Future<void> deleteAssignmentsByPerson(String teamMemberId);

  /// Delete multiple assignments by their IDs in a single batch operation
  Future<void> deleteAssignmentsBatch(List<String> assignmentIds);

  
  // ========== Batch Operations ==========

  /// Insert multiple team members at once (for data import)
  Future<void> insertTeamMembersBatch(List<TeamMember> members);

  /// Insert multiple events at once (for data import)
  Future<void> insertEventsBatch(List<Event> events);

  /// Insert multiple assignments at once (for data import)
  Future<void> insertAssignmentsBatch(List<Assignment> assignments);

  // ========== Utility ==========

  /// Initialize the database connection
  Future<void> initialize();

  /// Close the database connection
  Future<void> close();

  /// Clear all data (for testing purposes only)
  Future<void> clearAllData();

  // ========== Calendar Sync State ==========

  /// Save calendar sync state mapping constraint ID to calendar event ID
  Future<void> saveCalendarSyncState({
    required String constraintId,
    required String calendarEventId,
    required String teamMemberId,
    required CalendarSyncStatus status,
  });

  /// Get calendar event ID for a constraint
  Future<String?> getCalendarEventId(String constraintId);

  /// Get calendar sync state for a constraint
  Future<Map<String, dynamic>?> getCalendarSyncState(String constraintId);

  /// Update calendar sync status for a constraint
  Future<void> updateCalendarSyncStatus(
    String constraintId,
    CalendarSyncStatus status, {
    String? errorMessage,
    int? retryCount,
  });

  /// Remove calendar sync state for a constraint
  Future<void> removeCalendarSyncState(String constraintId);

  /// Atomically create or update calendar sync state and return the appropriate action
  /// Returns a map with 'action' ('create' or 'update') and 'calendarEventId' if updating
  Future<Map<String, dynamic>?> atomicCheckAndSetSyncState(
    String constraintId,
    String teamMemberId,
  );

  /// Get all failed sync states for retry
  Future<List<Map<String, dynamic>>> getFailedSyncStates();

  /// Get all synced constraints across all team members
  Future<List<Map<String, dynamic>>> getSyncedConstraintsForAllMembers();

  /// Update constraint status
  /// If constraintIndex is null, teamMemberIdOrConstraintId is treated as constraintId
  /// If constraintIndex is provided, teamMemberIdOrConstraintId is treated as teamMemberId
  Future<void> updateConstraintStatus(
    String teamMemberIdOrConstraintId,
    int? constraintIndex,
    ConstraintStatus newStatus, {
    String? note,
  });

  /// Get all synced constraints for a team member
  Future<List<Map<String, dynamic>>> getSyncedConstraintsForMember(String teamMemberId);

  /// Get Google Calendar configuration from Firestore
  /// Returns a map containing serviceAccountJson and calendarId
  Future<Map<String, String?>?> getGoogleCalendarConfig();
}
