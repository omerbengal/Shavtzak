import '../../../core/constants/role_types.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/event.dart';
import '../../../data/repositories/assignment_repository.dart';

/// Represents a conflict when reducing role quotas
/// Contains information about which assignments need to be removed
class RoleQuotaConflict {
  final RoleType roleType;
  final int oldQuota;
  final int newQuota;
  final List<Assignment> assignmentCandidates; // ALL assignments for this role
  final int countToRemove; // How many the user must select to delete

  const RoleQuotaConflict({
    required this.roleType,
    required this.oldQuota,
    required this.newQuota,
    required this.assignmentCandidates,
    required this.countToRemove,
  });

  /// Number of assignments that need to be removed
  int get removalCount => countToRemove;

  /// Whether this conflict requires user intervention
  bool get requiresUserAction => countToRemove > 0;
}

/// Analyzes quota reductions and identifies conflicts
class QuotaReductionAnalyzer {
  /// Analyzes quota reductions for an event
  /// Returns list of roles that have filled slots needing removal
  static Future<List<RoleQuotaConflict>> analyzeQuotaReductions({
    required Event originalEvent,
    required Map<RoleType, int> newRoleRequirements,
    required AssignmentRepository assignmentRepo,
  }) async {
    final conflicts = <RoleQuotaConflict>[];

    // Get all assignments for this event
    final allAssignments = await assignmentRepo.getAssignmentsByEvent(
      originalEvent.id,
    );

    // Check each role for quota reduction
    for (final roleType in RoleType.values) {
      final oldQuota = originalEvent.roleRequirements[roleType] ?? 0;
      final newQuota = newRoleRequirements[roleType] ?? 0;

      // Only process roles where quota was reduced
      if (newQuota >= oldQuota) continue;

      // Find all assignments for this role
      final roleAssignments = allAssignments
          .where((a) => a.roleType == roleType)
          .toList();

      // If there are more assignments than the new quota allows,
      // show ALL assignments and let the user choose which to keep
      if (roleAssignments.length > newQuota) {
        // Sort by slotIndex for predictable ordering
        roleAssignments.sort((a, b) => a.slotIndex.compareTo(b.slotIndex));

        conflicts.add(
          RoleQuotaConflict(
            roleType: roleType,
            oldQuota: oldQuota,
            newQuota: newQuota,
            assignmentCandidates: roleAssignments, // Show ALL assignments as candidates
            countToRemove: roleAssignments.length - newQuota, // How many to remove
          ),
        );
      }
    }

    return conflicts;
  }
}
