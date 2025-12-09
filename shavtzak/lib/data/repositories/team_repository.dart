import '../../domain/entities/team_member.dart';
import '../../core/constants/role_types.dart';
import '../data_sources/database_interface.dart';
import '../data_sources/firestore_database.dart';

/// Repository for team member operations
/// Provides high-level business logic on top of database operations
class TeamRepository {
  final DatabaseInterface _database;

  TeamRepository(this._database);

  /// Get the database interface for direct access (needed for constraint status updates)
  DatabaseInterface get database => _database;

  /// Watch all team members in real-time
  Stream<List<TeamMember>> watchTeamMembers() {
    // Cast to FirestoreDatabase to access stream methods
    if (_database is FirestoreDatabase) {
      return (_database as FirestoreDatabase).watchTeamMembers();
    }
    // Fallback: convert Future to Stream for non-Firestore databases
    return Stream.fromFuture(_database.getTeamMembers());
  }

  /// Get all team members
  Future<List<TeamMember>> getAllTeamMembers() async {
    return await _database.getTeamMembers();
  }

  /// Get active team members only
  Future<List<TeamMember>> getActiveTeamMembers() async {
    final all = await _database.getTeamMembers();
    return all.where((member) => member.isActive).toList();
  }

  /// Get team member by ID
  Future<TeamMember?> getTeamMemberById(String id) async {
    return await _database.getTeamMemberById(id);
  }

  /// Create a new team member
  Future<void> createTeamMember(TeamMember member) async {
    await _database.insertTeamMember(member);
  }

  /// Update an existing team member
  Future<void> updateTeamMember(TeamMember member) async {
    await _database.updateTeamMember(member);
  }

  /// Delete a team member
  /// Also deletes all assignments for this member
  Future<void> deleteTeamMember(String id) async {
    // Delete all assignments first
    await _database.deleteAssignmentsByPerson(id);

    // Then delete the team member
    await _database.deleteTeamMember(id);
  }

  /// Deactivate a team member (soft delete)
  /// Preserves historical assignment data
  Future<void> deactivateTeamMember(String id) async {
    final member = await _database.getTeamMemberById(id);
    if (member == null) {
      throw Exception('Team member not found: $id');
    }

    final updated = member.copyWith(
      isActive: false,
      updatedAt: DateTime.now(),
    );

    await _database.updateTeamMember(updated);
  }

  /// Reactivate a team member
  Future<void> reactivateTeamMember(String id) async {
    final member = await _database.getTeamMemberById(id);
    if (member == null) {
      throw Exception('Team member not found: $id');
    }

    final updated = member.copyWith(
      isActive: true,
      updatedAt: DateTime.now(),
    );

    await _database.updateTeamMember(updated);
  }

  /// Get team members who can perform a specific role
  Future<List<TeamMember>> getTeamMembersByRole(RoleType role) async {
    final all = await getActiveTeamMembers();
    return all.where((member) => member.canPerformRole(role)).toList();
  }

  /// Get team members available on a specific date
  Future<List<TeamMember>> getAvailableTeamMembers(DateTime date) async {
    final all = await getActiveTeamMembers();
    return all.where((member) => member.isAvailableOn(date)).toList();
  }

  /// Get team members qualified and available for a role on a date
  Future<List<TeamMember>> getQualifiedAvailableMembers(
    RoleType role,
    DateTime date,
  ) async {
    final all = await getActiveTeamMembers();
    return all
        .where((member) => member.isQualifiedAndAvailableFor(role, date))
        .toList();
  }

  /// Search team members by name
  Future<List<TeamMember>> searchTeamMembers(String query) async {
    if (query.trim().isEmpty) {
      return await getAllTeamMembers();
    }

    final all = await getAllTeamMembers();
    final lowerQuery = query.trim().toLowerCase();

    return all
        .where(
          (member) => member.name.toLowerCase().contains(lowerQuery),
        )
        .toList();
  }

  /// Import team members in batch (for V1 data import)
  Future<void> importTeamMembers(List<TeamMember> members) async {
    await _database.insertTeamMembersBatch(members);
  }

  /// Get statistics
  Future<Map<String, int>> getStatistics() async {
    final all = await getAllTeamMembers();
    final active = all.where((m) => m.isActive).length;

    return {
      'total': all.length,
      'active': active,
      'inactive': all.length - active,
    };
  }
}
