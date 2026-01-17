import 'dart:developer' as developer;
import '../../domain/entities/role.dart';
import '../data_sources/database_interface.dart';
import '../data_sources/firestore_database.dart';

/// Repository for role operations
/// Provides high-level business logic on top of database operations
class RoleRepository {
  final DatabaseInterface _database;

  RoleRepository(this._database);

  /// Watch all roles in real-time
  Stream<List<Role>> watchRoles() {
    // Cast to FirestoreDatabase to access stream methods
    if (_database is FirestoreDatabase) {
      return (_database as FirestoreDatabase).watchRoles();
    }
    // Fallback: convert Future to Stream for non-Firestore databases
    return Stream.fromFuture(_database.getRoles());
  }

  /// Get all roles
  Future<List<Role>> getAllRoles() async {
    return await _database.getRoles();
  }

  /// Get active (non-archived) roles
  Future<List<Role>> getActiveRoles() async {
    final allRoles = await getAllRoles();
    return allRoles.where((role) => !role.isArchived).toList();
  }

  /// Get archived roles
  Future<List<Role>> getArchivedRoles() async {
    final allRoles = await getAllRoles();
    return allRoles.where((role) => role.isArchived).toList();
  }

  /// Get visible roles (for EventFormModal quota configuration)
  Future<List<Role>> getVisibleRoles() async {
    final allRoles = await getAllRoles();
    return allRoles.where((role) => role.isActiveForQuotas).toList();
  }

  /// Get a role by ID
  Future<Role?> getRoleById(String id) async {
    return await _database.getRoleById(id);
  }

  /// Get a role by key
  Future<Role?> getRoleByKey(String key) async {
    return await _database.getRoleByKey(key);
  }

  /// Create a new role
  Future<void> createRole({
    required String hebrewName,
    bool isVisible = true,
  }) async {
    try {
      // Generate a key from Hebrew name (simplified - could be improved)
      // For now, use a timestamp-based key to ensure uniqueness
      final key = 'role_${DateTime.now().millisecondsSinceEpoch}';

      // Get current max sort order
      final allRoles = await getAllRoles();
      final maxSortOrder = allRoles.isEmpty
          ? 0
          : allRoles.map((r) => r.sortOrder).reduce((a, b) => a > b ? a : b);

      final now = DateTime.now();
      final role = Role(
        id: key,
        key: key,
        hebrewName: hebrewName,
        isVisible: isVisible,
        isArchived: false,
        sortOrder: maxSortOrder + 1,
        createdAt: now,
        updatedAt: now,
      );

      await _database.insertRole(role);
      developer.log('RoleRepository.createRole: Created role "$hebrewName"', name: 'RoleRepository');
    } catch (e) {
      developer.log('RoleRepository.createRole: Error creating role: $e', name: 'RoleRepository');
      rethrow;
    }
  }

  /// Update a role (rename or change visibility)
  Future<void> updateRole(Role role) async {
    try {
      final updatedRole = role.copyWith(updatedAt: DateTime.now());
      await _database.updateRole(updatedRole);
      developer.log('RoleRepository.updateRole: Updated role "${role.hebrewName}"', name: 'RoleRepository');
    } catch (e) {
      developer.log('RoleRepository.updateRole: Error updating role: $e', name: 'RoleRepository');
      rethrow;
    }
  }

  /// Rename a role
  Future<void> renameRole(String roleId, String newHebrewName) async {
    try {
      final role = await getRoleById(roleId);
      if (role == null) {
        throw Exception('Role not found: $roleId');
      }

      final updatedRole = role.copyWith(
        hebrewName: newHebrewName,
        updatedAt: DateTime.now(),
      );

      await _database.updateRole(updatedRole);
      developer.log('RoleRepository.renameRole: Renamed role to "$newHebrewName"', name: 'RoleRepository');
    } catch (e) {
      developer.log('RoleRepository.renameRole: Error renaming role: $e', name: 'RoleRepository');
      rethrow;
    }
  }

  /// Toggle role visibility (active/inactive for event quota configuration)
  Future<void> toggleVisibility(String roleId) async {
    try {
      final role = await getRoleById(roleId);
      if (role == null) {
        throw Exception('Role not found: $roleId');
      }

      final updatedRole = role.copyWith(
        isVisible: !role.isVisible,
        updatedAt: DateTime.now(),
      );

      await _database.updateRole(updatedRole);
      developer.log('RoleRepository.toggleVisibility: Toggled visibility for "${role.hebrewName}" to ${!role.isVisible}', name: 'RoleRepository');
    } catch (e) {
      developer.log('RoleRepository.toggleVisibility: Error toggling visibility: $e', name: 'RoleRepository');
      rethrow;
    }
  }

  /// Archive a role (soft delete)
  Future<void> archiveRole(String roleId) async {
    try {
      await _database.archiveRole(roleId);
      developer.log('RoleRepository.archiveRole: Archived role $roleId', name: 'RoleRepository');
    } catch (e) {
      developer.log('RoleRepository.archiveRole: Error archiving role: $e', name: 'RoleRepository');
      rethrow;
    }
  }

  /// Restore an archived role
  Future<void> restoreRole(String roleId) async {
    try {
      await _database.restoreRole(roleId);
      developer.log('RoleRepository.restoreRole: Restored role $roleId', name: 'RoleRepository');
    } catch (e) {
      developer.log('RoleRepository.restoreRole: Error restoring role: $e', name: 'RoleRepository');
      rethrow;
    }
  }

  /// Reorder roles (update sort order)
  Future<void> reorderRoles(List<Role> reorderedRoles) async {
    try {
      // Create a map of roleId -> new sortOrder
      final Map<String, int> roleIdToSortOrder = {};
      for (int i = 0; i < reorderedRoles.length; i++) {
        roleIdToSortOrder[reorderedRoles[i].id] = i;
      }

      await _database.updateRolesSortOrder(roleIdToSortOrder);
      developer.log('RoleRepository.reorderRoles: Updated sort order for ${roleIdToSortOrder.length} roles', name: 'RoleRepository');
    } catch (e) {
      developer.log('RoleRepository.reorderRoles: Error reordering roles: $e', name: 'RoleRepository');
      rethrow;
    }
  }

  /// Seed roles from RoleType enum (migration helper)
  Future<void> seedRolesFromEnum() async {
    try {
      await _database.seedRolesFromEnum();
      developer.log('RoleRepository.seedRolesFromEnum: Completed seed operation', name: 'RoleRepository');
    } catch (e) {
      developer.log('RoleRepository.seedRolesFromEnum: Error seeding roles: $e', name: 'RoleRepository');
      rethrow;
    }
  }
}
