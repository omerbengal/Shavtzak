import 'package:equatable/equatable.dart';
import '../../../domain/entities/role.dart';
import '../../../core/utils/crud_action_result.dart';

/// Base event class for RoleBloc
abstract class RoleEvent extends Equatable {
  const RoleEvent();

  @override
  List<Object?> get props => [];
}

/// Load all roles with real-time updates
class LoadRoles extends RoleEvent {
  const LoadRoles();
}

/// Create new role
class CreateRole extends RoleEvent {
  final String hebrewName;
  final bool isVisible;
  final CrudActionCompleter? completion;

  const CreateRole({
    required this.hebrewName,
    this.isVisible = true,
    this.completion,
  });

  @override
  List<Object?> get props => [hebrewName, isVisible];
}

/// Update role
class UpdateRole extends RoleEvent {
  final Role role;
  final CrudActionCompleter? completion;

  const UpdateRole(this.role, {this.completion});

  @override
  List<Object?> get props => [role];
}

/// Rename role
class RenameRole extends RoleEvent {
  final String roleId;
  final String newHebrewName;
  final CrudActionCompleter? completion;

  const RenameRole({
    required this.roleId,
    required this.newHebrewName,
    this.completion,
  });

  @override
  List<Object?> get props => [roleId, newHebrewName];
}

/// Toggle role visibility (active/inactive for event quota configuration)
class ToggleRoleVisibility extends RoleEvent {
  final String roleId;
  final CrudActionCompleter? completion;

  const ToggleRoleVisibility(this.roleId, {this.completion});

  @override
  List<Object?> get props => [roleId];
}

/// Archive role
class ArchiveRole extends RoleEvent {
  final String roleId;
  final CrudActionCompleter? completion;

  const ArchiveRole(this.roleId, {this.completion});

  @override
  List<Object?> get props => [roleId];
}

/// Restore archived role
class RestoreRole extends RoleEvent {
  final String roleId;
  final CrudActionCompleter? completion;

  const RestoreRole(this.roleId, {this.completion});

  @override
  List<Object?> get props => [roleId];
}

/// Permanently delete a role
class DeleteRole extends RoleEvent {
  final String roleId;
  final CrudActionCompleter? completion;

  const DeleteRole(this.roleId, {this.completion});

  @override
  List<Object?> get props => [roleId];
}

/// Reorder roles
class ReorderRoles extends RoleEvent {
  final List<Role> reorderedRoles;

  const ReorderRoles(this.reorderedRoles);

  @override
  List<Object?> get props => [reorderedRoles];
}

/// Seed roles from RoleType enum (migration helper)
class SeedRolesFromEnum extends RoleEvent {
  const SeedRolesFromEnum();
}
