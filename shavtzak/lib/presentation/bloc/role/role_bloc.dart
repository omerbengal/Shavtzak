import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:developer' as developer;
import '../../../data/repositories/role_repository.dart';
import '../../../domain/entities/role.dart';
import 'role_event.dart';
import 'role_state.dart';

/// BLoC for managing roles
class RoleBloc extends Bloc<RoleEvent, RoleState> {
  final RoleRepository _repository;

  // Flag to track if we're currently subscribed to prevent multiple listeners
  bool _isSubscribed = false;

  RoleBloc(this._repository) : super(const RoleInitial()) {
    // Register event handlers
    on<LoadRoles>(_onLoadRoles);
    on<CreateRole>(_onCreateRole);
    on<UpdateRole>(_onUpdateRole);
    on<RenameRole>(_onRenameRole);
    on<ToggleRoleVisibility>(_onToggleVisibility);
    on<ArchiveRole>(_onArchiveRole);
    on<RestoreRole>(_onRestoreRole);
    on<DeleteRole>(_onDeleteRole);
    on<ReorderRoles>(_onReorderRoles);
    on<SeedRolesFromEnum>(_onSeedRolesFromEnum);
  }

  /// Load all roles with real-time updates
  Future<void> _onLoadRoles(
    LoadRoles event,
    Emitter<RoleState> emit,
  ) async {
    // If already subscribed, don't start another subscription
    if (_isSubscribed) {
      developer.log('RoleBloc._onLoadRoles: Already subscribed, skipping', name: 'RoleBloc');
      return;
    }

    emit(const RoleLoading());
    _isSubscribed = true;

    try {
      // First, check if we need to seed the database
      final existingRoles = await _repository.getAllRoles();
      if (existingRoles.isEmpty) {
        developer.log('RoleBloc._onLoadRoles: No roles found, seeding from enum', name: 'RoleBloc');
        await _repository.seedRolesFromEnum();
      }

      // Subscribe to real-time updates using emit.forEach
      await emit.forEach<List<Role>>(
        _repository.watchRoles(),
        onData: (roles) {
          if (roles.isEmpty) {
            return const RolesEmpty('אין תפקידים זמינים');
          }
          developer.log('RoleBloc._onLoadRoles: Loaded ${roles.length} roles', name: 'RoleBloc');
          return RolesLoaded(roles);
        },
        onError: (error, stackTrace) {
          developer.log('RoleBloc._onLoadRoles: Error loading roles: $error', name: 'RoleBloc');
          return RoleError('שגיאה בטעינת תפקידים: $error');
        },
      ).then((_) {
        // Subscription ended (shouldn't happen with Firestore)
        _isSubscribed = false;
      });
    } catch (e) {
      _isSubscribed = false;
      developer.log('RoleBloc._onLoadRoles: Error: $e', name: 'RoleBloc');
      emit(RoleError('שגיאה בטעינת תפקידים: $e'));
    }
  }

  /// Create new role
  Future<void> _onCreateRole(
    CreateRole event,
    Emitter<RoleState> emit,
  ) async {
    try {
      await _repository.createRole(
        hebrewName: event.hebrewName,
        isVisible: event.isVisible,
      );
      developer.log('RoleBloc._onCreateRole: Created role "${event.hebrewName}"', name: 'RoleBloc');
      // Real-time stream will trigger UI update
    } catch (e) {
      developer.log('RoleBloc._onCreateRole: Error creating role: $e', name: 'RoleBloc');
      emit(RoleError('שגיאה ביצירת תפקיד: $e'));
    }
  }

  /// Update role
  Future<void> _onUpdateRole(
    UpdateRole event,
    Emitter<RoleState> emit,
  ) async {
    try {
      await _repository.updateRole(event.role);
      developer.log('RoleBloc._onUpdateRole: Updated role "${event.role.hebrewName}"', name: 'RoleBloc');
      // Real-time stream will trigger UI update
    } catch (e) {
      developer.log('RoleBloc._onUpdateRole: Error updating role: $e', name: 'RoleBloc');
      emit(RoleError('שגיאה בעדכון תפקיד: $e'));
    }
  }

  /// Rename role
  Future<void> _onRenameRole(
    RenameRole event,
    Emitter<RoleState> emit,
  ) async {
    try {
      await _repository.renameRole(event.roleId, event.newHebrewName);
      developer.log('RoleBloc._onRenameRole: Renamed role to "${event.newHebrewName}"', name: 'RoleBloc');
      // Real-time stream will trigger UI update
    } catch (e) {
      developer.log('RoleBloc._onRenameRole: Error renaming role: $e', name: 'RoleBloc');
      emit(RoleError('שגיאה בשינוי שם תפקיד: $e'));
    }
  }

  /// Toggle role visibility
  Future<void> _onToggleVisibility(
    ToggleRoleVisibility event,
    Emitter<RoleState> emit,
  ) async {
    try {
      await _repository.toggleVisibility(event.roleId);
      developer.log('RoleBloc._onToggleVisibility: Toggled visibility for role ${event.roleId}', name: 'RoleBloc');
      // Real-time stream will trigger UI update
    } catch (e) {
      developer.log('RoleBloc._onToggleVisibility: Error toggling visibility: $e', name: 'RoleBloc');
      emit(RoleError('שגיאה בשינוי נראות תפקיד: $e'));
    }
  }

  /// Archive role
  Future<void> _onArchiveRole(
    ArchiveRole event,
    Emitter<RoleState> emit,
  ) async {
    try {
      await _repository.archiveRole(event.roleId);
      developer.log('RoleBloc._onArchiveRole: Archived role ${event.roleId}', name: 'RoleBloc');
      // Real-time stream will trigger UI update
    } catch (e) {
      developer.log('RoleBloc._onArchiveRole: Error archiving role: $e', name: 'RoleBloc');
      emit(RoleError('שגיאה בהעברת תפקיד לארכיון: $e'));
    }
  }

  /// Restore archived role
  Future<void> _onRestoreRole(
    RestoreRole event,
    Emitter<RoleState> emit,
  ) async {
    try {
      await _repository.restoreRole(event.roleId);
      developer.log('RoleBloc._onRestoreRole: Restored role ${event.roleId}', name: 'RoleBloc');
      // Real-time stream will trigger UI update
    } catch (e) {
      developer.log('RoleBloc._onRestoreRole: Error restoring role: $e', name: 'RoleBloc');
      emit(RoleError('שגיאה בשחזור תפקיד מהארכיון: $e'));
    }
  }

  /// Permanently delete a role
  Future<void> _onDeleteRole(
    DeleteRole event,
    Emitter<RoleState> emit,
  ) async {
    try {
      await _repository.deleteRole(event.roleId);
      developer.log('RoleBloc._onDeleteRole: Permanently deleted role ${event.roleId}', name: 'RoleBloc');
      // Real-time stream will trigger UI update
    } catch (e) {
      developer.log('RoleBloc._onDeleteRole: Error deleting role: $e', name: 'RoleBloc');
      emit(RoleError('שגיאה במחיקת תפקיד: $e'));
    }
  }

  /// Reorder roles
  Future<void> _onReorderRoles(
    ReorderRoles event,
    Emitter<RoleState> emit,
  ) async {
    try {
      // Optimistic update: update sortOrder field for each role to match new positions
      final currentState = state;
      if (currentState is RolesLoaded) {
        // Update sortOrder for reordered roles to match their new index
        final updatedRoles = event.reorderedRoles
            .asMap()
            .entries
            .map((entry) => entry.value.copyWith(sortOrder: entry.key))
            .toList();

        // Replace reordered roles in the full roles list (preserving archived roles)
        final allRoles = currentState.roles.map((role) {
          if (role.isArchived) return role; // Keep archived roles unchanged

          // Find the role in updatedRoles by id
          final updatedRole = updatedRoles.firstWhere(
            (r) => r.id == role.id,
            orElse: () => role,
          );
          return updatedRole;
        }).toList();

        emit(RolesLoaded(allRoles));
        developer.log('RoleBloc._onReorderRoles: Optimistically updated UI with new sortOrder', name: 'RoleBloc');
      }

      // Then update Firestore (stream will eventually emit the same order)
      await _repository.reorderRoles(event.reorderedRoles);
      developer.log('RoleBloc._onReorderRoles: Reordered ${event.reorderedRoles.length} roles in Firestore', name: 'RoleBloc');
    } catch (e) {
      developer.log('RoleBloc._onReorderRoles: Error reordering roles: $e', name: 'RoleBloc');
      emit(RoleError('שגיאה בעדכון סדר תפקידים: $e'));
      // Note: On error, the real-time stream will revert to the correct order from Firestore
    }
  }

  /// Seed roles from RoleType enum
  Future<void> _onSeedRolesFromEnum(
    SeedRolesFromEnum event,
    Emitter<RoleState> emit,
  ) async {
    try {
      await _repository.seedRolesFromEnum();
      developer.log('RoleBloc._onSeedRolesFromEnum: Seeded roles from enum', name: 'RoleBloc');
      // Real-time stream will trigger UI update
    } catch (e) {
      developer.log('RoleBloc._onSeedRolesFromEnum: Error seeding roles: $e', name: 'RoleBloc');
      emit(RoleError('שגיאה ביצירת תפקידים מהמערכת: $e'));
    }
  }
}
