import '../../domain/entities/assignment.dart';
import '../../domain/entities/assignment_label.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/checklist_item.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/preset.dart';
import '../../domain/entities/role.dart';
import '../../domain/entities/team_member.dart';
import '../../core/constants/constraint_status.dart';
import '../../core/constants/calendar_constants.dart';

/// A request to raise an event's role quota to AT LEAST [count], applied
/// atomically inside [DatabaseInterface.saveAssignmentsBatch]. Used to
/// "restore to quota" when an admin overrides a Save-time conflict whose slot
/// had vanished (the role's quota shrank under a staged edit) — so the
/// re-created assignment lands in-quota instead of off-quota. The backend
/// applies `max(current, count)`, so a concurrent increase is never clobbered.
typedef EventQuotaBump = ({String eventId, String roleType, int count});

/// A request to set an event's role quota to EXACTLY [target] atomically inside
/// [DatabaseInterface.saveAssignmentsBatch] — the staged quota lower/set path.
/// [expected] is the client's baseline quota, used for optimistic-concurrency
/// (the backend rejects the whole save when live ∉ {expected, target}). Unlike
/// [EventQuotaBump] (max-merge raise), this can LOWER a quota.
typedef EventQuotaSet = ({String eventId, String roleType, int target, int expected});

/// Abstract database interface
/// This allows the app to be backend-agnostic
/// Implementations: FirestoreDatabase, SupabaseDatabase, LocalDatabase, etc.
abstract class DatabaseInterface {
  // ========== Team Members ==========

  /// Get all team members
  Future<List<TeamMember>> getTeamMembers();

  /// Watch all team members in real-time
  Stream<List<TeamMember>> watchTeamMembers();

  /// Get a team member by ID
  Future<TeamMember?> getTeamMemberById(String id);

  /// Get a team member by unique key (Feature 13: User authentication)
  Future<TeamMember?> getTeamMemberByUniqueKey(String uniqueKey);

  /// Insert a new team member
  Future<void> insertTeamMember(TeamMember member);

  /// Update an existing team member
  /// NOTE: This method does NOT update passcode fields to prevent race conditions
  /// when the app is open on multiple devices. Use updateTeamMemberPasscode/
  /// clearTeamMemberPasscode for passcode operations.
  Future<void> updateTeamMember(TeamMember member);

  /// Update passcode for a team member (field-specific, avoids race conditions)
  Future<void> updateTeamMemberPasscode(String id, String passcode, int length);

  /// Clear passcode for a team member (field-specific, avoids race conditions)
  Future<void> clearTeamMemberPasscode(String id);

  /// Delete a team member
  Future<void> deleteTeamMember(String id);

  // ========== Events ==========

  /// Get all events
  Future<List<Event>> getEvents();

  /// Watch all events in real-time
  Stream<List<Event>> watchEvents();

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

  /// Get events strictly older than [cursor], newest-first, capped to [limit].
  /// Used for paging back through history beyond the assignments time window.
  Future<List<Event>> getEventsBeforeDate(DateTime cursor, {required int limit});

  /// Watch events within a date range in real-time
  /// Optimized for pagination - only loads events within the specified window
  Stream<List<Event>> watchEventsByDateRange(DateTime start, DateTime end);

  /// Check if an event with the same name and start date already exists
  /// If excludeEventId is provided, that event is excluded from the check (for updates)
  Future<bool> isDuplicateEvent(String name, DateTime startDate,
      {String? excludeEventId});

  // ========== Assignments ==========

  /// Get all assignments
  Future<List<Assignment>> getAssignments();

  /// Watch all assignments in real-time
  Stream<List<Assignment>> watchAssignments();

  /// Watch assignments for a specific event in real-time
  Stream<List<Assignment>> watchAssignmentsByEvent(String eventId);

  /// Watch assignments for a specific team member in real-time
  Stream<List<Assignment>> watchAssignmentsByPerson(String teamMemberId);

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

  /// Get assignments for events within a time window (optimized for pagination)
  /// First fetches events in the window, then fetches matching assignments
  /// This is more efficient than fetching all assignments when you only need a subset
  Future<List<Assignment>> getAssignmentsInTimeWindow(
    DateTime windowStart,
    DateTime windowEnd,
  );

  /// Get all assignments for the given event ids (batched whereIn, ≤30/chunk).
  Future<List<Assignment>> getAssignmentsByEventIds(List<String> eventIds);

  /// Watch assignments within a time window in real-time (optimized for pagination)
  /// Returns a stream that emits updated assignment lists for events in the time window
  /// This is more efficient than watching all assignments when you only need a subset
  Stream<List<Assignment>> watchAssignmentsInTimeWindow(
    DateTime windowStart,
    DateTime windowEnd,
  );

  /// Insert a new assignment
  Future<void> insertAssignment(
    Assignment assignment, {
    bool bypassAvailability,
  });

  /// Update an existing assignment
  Future<void> updateAssignment(
    Assignment assignment, {
    bool bypassAvailability,
  });

  /// Update assignment metadata without re-validating assignment eligibility
  Future<void> updateAssignmentMetadata(
    String assignmentId, {
    required String notes,
    String? semanticLabelId,
    String? alternativePhoneNumber,
  });

  /// Delete an assignment
  Future<void> deleteAssignment(String id);

  /// Delete all assignments for an event
  Future<void> deleteAssignmentsByEvent(String eventId);

  /// Delete all assignments for a team member
  Future<void> deleteAssignmentsByPerson(String teamMemberId);

  /// Delete multiple assignments by their IDs in a single batch operation
  Future<void> deleteAssignmentsBatch(List<String> assignmentIds);

  // ========== Assignment Labels ==========

  /// Get all assignment semantic labels
  Future<List<AssignmentLabel>> getAssignmentLabels();

  /// Insert a new assignment semantic label
  Future<void> insertAssignmentLabel(AssignmentLabel label);

  /// Update an existing assignment semantic label
  Future<void> updateAssignmentLabel(AssignmentLabel label);

  /// Archive an assignment semantic label
  Future<void> archiveAssignmentLabel(String id);

  /// Restore an archived assignment semantic label
  Future<void> restoreAssignmentLabel(String id);

  /// Permanently delete an assignment semantic label
  Future<void> deleteAssignmentLabel(String id);

  /// Update assignment semantic label sort order
  Future<void> updateAssignmentLabelsSortOrder(
    Map<String, int> labelIdToSortOrder,
  );

  /// Watch assignment semantic labels in real-time
  Stream<List<AssignmentLabel>> watchAssignmentLabels();

  // ========== Batch Operations ==========

  /// Insert multiple team members at once (for data import)
  Future<void> insertTeamMembersBatch(List<TeamMember> members);

  /// Insert multiple events at once (for data import)
  Future<void> insertEventsBatch(List<Event> events);

  /// Insert multiple assignments at once (for data import)
  Future<void> insertAssignmentsBatch(List<Assignment> assignments);

  /// Atomically create + update + delete assignments in one server-side batch.
  /// [eventQuotaBumps] optionally raises event role quotas in the SAME batch
  /// (restore-to-quota; see [EventQuotaBump]). [eventQuotaSets] optionally
  /// sets/lowers event role quotas in the SAME batch (see [EventQuotaSet]).
  Future<void> saveAssignmentsBatch({
    required List<Assignment> creates,
    required List<Assignment> updates,
    required List<String> deletes,
    List<EventQuotaBump> eventQuotaBumps,
    List<EventQuotaSet> eventQuotaSets,
  });

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

  // ========== Event Calendar Sync State ==========

  /// Save event calendar sync state mapping event ID to calendar event IDs
  Future<void> saveEventCalendarSyncState({
    required String eventId,
    required String assemblyCalendarEventId,
    required String mainCalendarEventId,
    required CalendarSyncStatus status,
  });

  /// Get event calendar sync state
  Future<Map<String, dynamic>?> getEventCalendarSyncState(String eventId);

  /// Watch the calendar sync status of every event, keyed by event id.
  ///
  /// Live stream over the whole event-calendar-sync collection so the admin
  /// event list can flag events whose Google Calendar entry is missing or
  /// failed. Events absent from the map have no sync state at all.
  Stream<Map<String, CalendarSyncStatus>> watchEventCalendarSyncStates();

  /// Remove event calendar sync state
  Future<void> removeEventCalendarSyncState(String eventId);

  /// Update constraint status
  /// If constraintIndex is null, teamMemberIdOrConstraintId is treated as constraintId
  /// If constraintIndex is provided, teamMemberIdOrConstraintId is treated as teamMemberId
  Future<void> updateConstraintStatus(
    String teamMemberIdOrConstraintId,
    int? constraintIndex,
    ConstraintStatus newStatus, {
    String? note,
    bool? wasAutoRejectedFromCalendar,
  });

  /// Add a constraint to a team member (targeted update - only writes constraints field)
  Future<void> addConstraint(
    String teamMemberId,
    DateConstraint newConstraint,
  );

  /// Edit a constraint by ID (targeted update - only writes constraints field)
  /// Reads the latest member data, finds the constraint by ID, replaces it, and writes back.
  Future<void> editConstraintById(
    String teamMemberId,
    String constraintId,
    DateConstraint updatedConstraint,
  );

  /// Remove a constraint by ID (targeted update - only writes constraints field)
  /// Reads the latest member data, finds the constraint by ID, removes it, and writes back.
  Future<DateConstraint?> removeConstraintById(
    String teamMemberId,
    String constraintId,
  );

  /// Get all synced constraints for a team member
  Future<List<Map<String, dynamic>>> getSyncedConstraintsForMember(
      String teamMemberId);

  /// Legacy method retained for interface compatibility.
  /// Google Calendar config is now backend-only and should not be read by clients.
  Future<Map<String, String?>?> getGoogleCalendarConfig();

  /// Legacy method retained for interface compatibility.
  /// Google Drive config is now backend-only and should not be read by clients.
  Future<Map<String, String?>?> getDriveConfig();

  // ========== Checklist Items ==========

  /// Get all checklist items
  Future<List<ChecklistItem>> getChecklistItems();

  /// Get a checklist item by ID
  Future<ChecklistItem?> getChecklistItemById(String id);

  /// Get checklist items for a specific event
  Future<List<ChecklistItem>> getChecklistItemsByEvent(String eventId);

  /// Get checklist items for a specific team member (as responsible or CC'd)
  Future<List<ChecklistItem>> getChecklistItemsForTeamMember(
      String teamMemberId);

  /// Get checklist items where team member is responsible
  Future<List<ChecklistItem>> getChecklistItemsWhereResponsible(
      String teamMemberId);

  /// Get checklist items where team member is CC'd
  Future<List<ChecklistItem>> getChecklistItemsWhereCc(String teamMemberId);

  /// Insert a new checklist item
  Future<void> insertChecklistItem(ChecklistItem item);

  /// Update an existing checklist item
  Future<void> updateChecklistItem(ChecklistItem item);

  /// Delete a checklist item
  Future<void> deleteChecklistItem(String id);

  /// Delete all checklist items for an event
  Future<void> deleteChecklistItemsByEvent(String eventId);

  /// Add a note to a checklist item (atomic arrayUnion)
  Future<void> addNoteToChecklistItem(
      String checklistItemId, Map<String, dynamic> noteData);

  // ========== Checklist Presets ==========

  /// Get all presets
  Future<List<Preset>> getPresets();

  /// Get a preset by ID
  Future<Preset?> getPresetById(String id);

  /// Insert a new preset
  Future<void> insertPreset(Preset preset);

  /// Update an existing preset
  Future<void> updatePreset(Preset preset);

  /// Delete a preset
  Future<void> deletePreset(String id);

  /// Load a preset into an event (creates checklist items from template)
  Future<void> loadPresetIntoEvent(
      String presetId, String eventId, String creatorAdminId);

  // ========== Roles ==========

  /// Get all roles
  Future<List<Role>> getRoles();

  /// Get a role by ID (which is the same as key)
  Future<Role?> getRoleById(String id);

  /// Get a role by key
  Future<Role?> getRoleByKey(String key);

  /// Insert a new role
  Future<void> insertRole(Role role);

  /// Update an existing role
  Future<void> updateRole(Role role);

  /// Delete a role (soft delete - set isArchived to true)
  Future<void> archiveRole(String id);

  /// Restore an archived role
  Future<void> restoreRole(String id);

  /// Permanently delete a role
  Future<void> deleteRole(String id);

  /// Watch all roles in real-time
  Stream<List<Role>> watchRoles();

  /// Seed roles collection from RoleType enum (migration helper)
  Future<void> seedRolesFromEnum();

  /// Update sort order for multiple roles in batch
  Future<void> updateRolesSortOrder(Map<String, int> roleIdToSortOrder);

  // ========== Categories ==========

  /// Get all categories
  Future<List<Category>> getCategories();

  /// Get active categories (isArchived = false)
  Future<List<Category>> getActiveCategories();

  /// Get a category by ID
  Future<Category?> getCategoryById(String id);

  /// Insert a new category
  Future<void> insertCategory(Category category);

  /// Update an existing category
  Future<void> updateCategory(Category category);

  /// Delete a category (soft delete - set isArchived to true)
  Future<void> deleteCategory(String id);

  /// Permanently delete a category (actual deletion from database)
  Future<void> permanentlyDeleteCategory(String id);

  /// Restore an archived category
  Future<void> restoreCategory(String id);

  /// Watch all categories in real-time
  Stream<List<Category>> watchCategories();

  /// Watch active categories in real-time
  Stream<List<Category>> watchActiveCategories();
}
