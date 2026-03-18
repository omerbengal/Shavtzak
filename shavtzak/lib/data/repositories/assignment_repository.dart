import '../../domain/entities/assignment.dart';
import '../../core/constants/role_types.dart';
import '../data_sources/database_interface.dart';
import '../data_sources/firestore_database.dart';

/// Repository for assignment operations
/// This is the CRITICAL repository that fixes the V1 sync problem
/// by maintaining proper FK relationships between events and team members
class AssignmentRepository {
  final DatabaseInterface _database;

  // Cache for current assignments to support real-time updates
  List<Assignment> _cachedAssignments = [];

  AssignmentRepository(this._database);

  /// Watch all assignments in real-time
  Stream<List<Assignment>> watchAssignments() {
    // Cast to FirestoreDatabase to access stream methods
    if (_database is FirestoreDatabase) {
      return (_database as FirestoreDatabase).watchAssignments();
    }
    // Fallback: convert Future to Stream for non-Firestore databases
    return Stream.fromFuture(_database.getAssignments());
  }

  /// Watch assignments for a specific event in real-time
  Stream<List<Assignment>> watchAssignmentsByEvent(String eventId) {
    if (_database is FirestoreDatabase) {
      return (_database as FirestoreDatabase).watchAssignmentsByEvent(eventId);
    }
    return Stream.fromFuture(_database.getAssignmentsByEvent(eventId));
  }

  /// Watch assignments for a specific team member in real-time
  Stream<List<Assignment>> watchAssignmentsByPerson(String teamMemberId) {
    if (_database is FirestoreDatabase) {
      return (_database as FirestoreDatabase)
          .watchAssignmentsByPerson(teamMemberId);
    }
    return Stream.fromFuture(_database.getAssignmentsByPerson(teamMemberId));
  }

  /// Get all assignments
  Future<List<Assignment>> getAllAssignments() async {
    return await _database.getAssignments();
  }

  /// Get assignment by ID
  Future<Assignment?> getAssignmentById(String id) async {
    return await _database.getAssignmentById(id);
  }

  /// Get assignments for a specific event
  /// Returns assignments with populated team member data
  Future<List<Assignment>> getAssignmentsByEvent(String eventId) async {
    return await _database.getAssignmentsByEvent(eventId);
  }

  /// Get assignments for a specific team member
  /// Returns assignments with populated event data
  Future<List<Assignment>> getAssignmentsByPerson(String teamMemberId) async {
    return await _database.getAssignmentsByPerson(teamMemberId);
  }

  /// Get assignments by date range
  Future<List<Assignment>> getAssignmentsByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    return await _database.getAssignmentsByDateRange(start, end);
  }

  /// Get assignments within a time window (optimized for pagination)
  /// First fetches events in the window, then fetches matching assignments
  /// This is more efficient than fetching all assignments when you only need a subset
  Future<List<Assignment>> getAssignmentsInTimeWindow({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    return await _database.getAssignmentsInTimeWindow(windowStart, windowEnd);
  }

  /// Watch assignments within a time window in real-time (optimized for pagination)
  /// Returns a stream that emits updated assignment lists for events in the time window
  /// This is more efficient than watching all assignments when you only need a subset
  Stream<List<Assignment>> watchAssignmentsInTimeWindow({
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    if (_database is FirestoreDatabase) {
      return (_database as FirestoreDatabase).watchAssignmentsInTimeWindow(
        windowStart,
        windowEnd,
      );
    }
    // Fallback: convert Future to Stream for non-Firestore databases
    return Stream.fromFuture(
      _database.getAssignmentsInTimeWindow(windowStart, windowEnd),
    );
  }

  /// Create a new assignment
  /// Validates FK relationships and checks for conflicts
  Future<void> createAssignment(Assignment assignment) async {
    // Validate that event and team member exist (handled by FirestoreDatabase)
    // Check for conflicts before inserting
    final conflicts = await checkConflicts(assignment);

    if (conflicts.isNotEmpty) {
      throw AssignmentConflictException(
        'Assignment has conflicts',
        conflicts,
      );
    }

    await _database.insertAssignment(assignment);
  }

  /// Create assignment without conflict checking (for imports)
  Future<void> createAssignmentUnchecked(Assignment assignment) async {
    await _database.insertAssignment(assignment);
  }

  /// Create assignment bypassing availability checks (for forced assignments)
  Future<void> createAssignmentWithBypass(Assignment assignment) async {
    await _database.insertAssignment(
      assignment,
      bypassAvailability: true,
    );
  }

  /// Update an existing assignment
  Future<void> updateAssignment(Assignment assignment) async {
    final conflicts = await checkConflicts(assignment);

    if (conflicts.isNotEmpty) {
      throw AssignmentConflictException(
        'Assignment has conflicts',
        conflicts,
      );
    }

    await _database.updateAssignment(assignment);
  }

  /// Update assignment without conflict checking (for internal operations like slot reassignment)
  Future<void> updateAssignmentUnchecked(Assignment assignment) async {
    await _database.updateAssignment(assignment);
  }

  /// Update assignment bypassing availability checks (for forced reassignments)
  Future<void> updateAssignmentWithBypass(Assignment assignment) async {
    await _database.updateAssignment(
      assignment,
      bypassAvailability: true,
    );
  }

  /// Delete an assignment
  Future<void> deleteAssignment(String id) async {
    await _database.deleteAssignment(id);
  }

  /// Delete multiple assignments in a single batch operation
  Future<void> deleteAssignmentsBatch(List<String> assignmentIds) async {
    await _database.deleteAssignmentsBatch(assignmentIds);
  }

  /// Check for conflicts in an assignment
  /// Returns list of conflict messages
  Future<List<String>> checkConflicts(Assignment assignment) async {
    final conflicts = <String>[];

    // Get full assignment data with relations
    final event = await _database.getEventById(assignment.eventId);
    final member = await _database.getTeamMemberById(assignment.teamMemberId);

    if (event == null) {
      conflicts.add('אירוע לא נמצא');
      return conflicts;
    }

    if (member == null) {
      conflicts.add('חבר צוות לא נמצא');
      return conflicts;
    }

    // Check availability conflict for entire event duration (with time-based detection)
    // Skip for members with allowMultipleAssignments
    if (!member.allowMultipleAssignments &&
        !member.isAvailableForEventWithTime(event)) {
      final dateRange = _isSameDay(event.startDate, event.endDate)
          ? _formatDate(event.startDate)
          : '${_formatDate(event.startDate)} - ${_formatDate(event.endDate)}';

      if (member.isPermanent) {
        conflicts.add(
            '${member.name} לא זמין/ה בתאריכים $dateRange (יש הגבלה מאושרת)');
      } else {
        conflicts.add(
            '${member.name} לא ציין/ה זמינות בתאריכים $dateRange (יש להוסיף זמינות)');
      }
    }

    // Check qualification conflict
    if (!member.canPerformRole(assignment.roleType)) {
      conflicts.add(
        '${member.name} לא מוסמך/ת לתפקיד ${assignment.roleType}', // Use role key instead of Hebrew name
      );
    }

    // Check if member is active
    if (!member.isActive) {
      conflicts.add('${member.name} אינו/ה פעיל/ה');
    }

    // Check for duplicate assignments (same person, same event, same role)
    // Skip for members with allowMultipleAssignments
    if (!member.allowMultipleAssignments) {
      final existingAssignments =
          await getAssignmentsByEvent(assignment.eventId);
      final duplicate = existingAssignments.any(
        (a) =>
            a.id != assignment.id && // Don't check against itself
            a.teamMemberId == assignment.teamMemberId &&
            a.roleType == assignment.roleType,
      );

      if (duplicate) {
        conflicts.add(
          '${member.name} כבר משובץ/ת לתפקיד ${assignment.roleType} באירוע זה', // Use role key instead of Hebrew name
        );
      }
    }

    return conflicts;
  }

  /// Get assignment statistics for an event
  Future<Map<String, AssignmentStats>> getEventAssignmentStats(
    String eventId,
  ) async {
    final event = await _database.getEventById(eventId);
    if (event == null) {
      return {};
    }

    final assignments = await getAssignmentsByEvent(eventId);
    final stats = <String, AssignmentStats>{};

    for (final roleKey in event.requiredRoleKeys) {
      final required = event.roleRequirements[roleKey] ?? 0;
      final assigned = assignments
          .where((a) =>
              a.roleType == roleKey && a.status != AssignmentStatus.declined)
          .length;

      stats[roleKey] = AssignmentStats(
        required: required,
        assigned: assigned,
        remaining: required - assigned,
      );
    }

    return stats;
  }

  /// Get assignments with conflicts
  Future<List<Assignment>> getAssignmentsWithConflicts() async {
    final all = await getAllAssignments();
    final withConflicts = <Assignment>[];

    for (final assignment in all) {
      if (assignment.hasAvailabilityConflict() ||
          assignment.hasQualificationConflict()) {
        withConflicts.add(assignment);
      }
    }

    return withConflicts;
  }

  /// Import assignments in batch (for V1 data import)
  Future<void> importAssignments(List<Assignment> assignments) async {
    await _database.insertAssignmentsBatch(assignments);
  }

  /// Get statistics
  Future<Map<String, int>> getStatistics() async {
    final all = await getAllAssignments();

    return {
      'total': all.length,
      'pending': all.where((a) => a.status == AssignmentStatus.pending).length,
      'confirmed':
          all.where((a) => a.status == AssignmentStatus.confirmed).length,
      'declined':
          all.where((a) => a.status == AssignmentStatus.declined).length,
      'with_conflicts': all
          .where(
            (a) => a.hasAvailabilityConflict() || a.hasQualificationConflict(),
          )
          .length,
    };
  }

  /// Update assignment status
  Future<void> updateAssignmentStatus(
    String id,
    AssignmentStatus status,
  ) async {
    final assignment = await getAssignmentById(id);
    if (assignment == null) {
      throw Exception('Assignment not found: $id');
    }

    final updated = Assignment(
      id: assignment.id,
      eventId: assignment.eventId,
      teamMemberId: assignment.teamMemberId,
      roleType: assignment.roleType,
      slotIndex: assignment.slotIndex,
      status: status,
      notes: assignment.notes,
      alternativePhoneNumber: assignment.alternativePhoneNumber,
      createdAt: assignment.createdAt,
      updatedAt: DateTime.now(),
      event: assignment.event,
      teamMember: assignment.teamMember,
    );

    await _database.updateAssignment(updated);
  }

  /// Confirm assignment
  Future<void> confirmAssignment(String id) async {
    await updateAssignmentStatus(id, AssignmentStatus.confirmed);
  }

  /// Decline assignment
  Future<void> declineAssignment(String id) async {
    await updateAssignmentStatus(id, AssignmentStatus.declined);
  }

  /// Update assignment notes and/or alternative phone number
  Future<void> updateAssignmentNotes(String id, String notes,
      {String? alternativePhoneNumber}) async {
    final assignment = await getAssignmentById(id);
    if (assignment == null) {
      throw Exception('Assignment not found: $id');
    }

    final updated = assignment.copyWith(
      notes: notes,
      alternativePhoneNumber: () => alternativePhoneNumber,
      updatedAt: DateTime.now(),
    );

    await _database.updateAssignment(updated);
  }

  /// Cache current assignments for real-time updates
  void cacheCurrentAssignments(List<Assignment> assignments) {
    _cachedAssignments = assignments;
  }

  /// Clear cached assignments
  void clearCache() {
    _cachedAssignments = [];
  }

  /// Get currently cached assignments
  List<Assignment> getCurrentAssignments() {
    return _cachedAssignments;
  }
}

/// Statistics for a specific role in an event
class AssignmentStats {
  final int required;
  final int assigned;
  final int remaining;

  AssignmentStats({
    required this.required,
    required this.assigned,
    required this.remaining,
  });

  bool get isFilled => remaining == 0;
  bool get isOverfilled => remaining < 0;
  bool get needsMore => remaining > 0;
}

/// Helper method to format date for display
String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

/// Helper method to check if two dates are the same day
bool _isSameDay(DateTime date1, DateTime date2) {
  return date1.year == date2.year &&
      date1.month == date2.month &&
      date1.day == date2.day;
}

/// Exception thrown when assignment has conflicts
class AssignmentConflictException implements Exception {
  final String message;
  final List<String> conflicts;

  AssignmentConflictException(this.message, this.conflicts);

  @override
  String toString() {
    return '$message: ${conflicts.join(', ')}';
  }
}
