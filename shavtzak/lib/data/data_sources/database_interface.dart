import '../../domain/entities/admin_device.dart';
import '../../domain/entities/assignment.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';

/// Abstract database interface
/// This allows the app to be backend-agnostic
/// Implementations: FirestoreDatabase, SupabaseDatabase, LocalDatabase, etc.
abstract class DatabaseInterface {
  // ========== Team Members ==========

  /// Get all team members
  Future<List<TeamMember>> getTeamMembers();

  /// Get a team member by ID
  Future<TeamMember?> getTeamMemberById(String id);

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

  // ========== Admin Devices ==========

  /// Get admin device by device ID
  Future<AdminDevice?> getAdminDevice(String deviceId);

  /// Insert a new admin device
  Future<void> insertAdminDevice(AdminDevice device);

  /// Update admin device (e.g., update lastSeen)
  Future<void> updateAdminDevice(AdminDevice device);

  /// Delete an admin device
  Future<void> deleteAdminDevice(String id);

  /// Get all admin devices
  Future<List<AdminDevice>> getAllAdminDevices();

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
}
