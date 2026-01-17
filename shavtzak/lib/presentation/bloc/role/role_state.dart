import 'package:equatable/equatable.dart';
import '../../../domain/entities/role.dart';

/// Base state class for RoleBloc
abstract class RoleState extends Equatable {
  const RoleState();

  @override
  List<Object?> get props => [];
}

/// Initial state
class RoleInitial extends RoleState {
  const RoleInitial();
}

/// Loading state
class RoleLoading extends RoleState {
  const RoleLoading();
}

/// Roles loaded successfully
class RolesLoaded extends RoleState {
  final List<Role> roles;

  const RolesLoaded(this.roles);

  /// Get active (non-archived) roles for main list
  List<Role> get activeRoles => roles
      .where((role) => !role.isArchived)
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// Get archived roles for history view
  List<Role> get archivedRoles => roles
      .where((role) => role.isArchived)
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// Get roles where isActiveForQuotas is true (for EventFormModal)
  List<Role> get visibleRoles => roles
      .where((role) => role.isActiveForQuotas)
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// Get all non-archived roles (for team capability checkboxes)
  List<Role> get allNonArchivedRoles => activeRoles;

  /// Lookup role by key (searches all roles including archived)
  Role? getRoleByKey(String key) {
    try {
      return roles.firstWhere((role) => role.key == key);
    } catch (e) {
      return null;
    }
  }

  /// Get role Hebrew name by key (fallback to key if not found)
  String getRoleHebrewName(String key) {
    final role = getRoleByKey(key);
    return role?.hebrewName ?? key;
  }

  @override
  List<Object?> get props => [roles];
}

/// Role operation in progress (create/update/archive/restore)
class RoleOperating extends RoleState {
  final String operation; // 'creating', 'updating', 'archiving', 'restoring', 'reordering'

  const RoleOperating(this.operation);

  @override
  List<Object?> get props => [operation];
}

/// Role operation succeeded
class RoleOperationSuccess extends RoleState {
  final String message;

  const RoleOperationSuccess(this.message);

  @override
  List<Object?> get props => [message];
}

/// Error state
class RoleError extends RoleState {
  final String message;

  const RoleError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Roles empty (unlikely, but possible if all roles are deleted)
class RolesEmpty extends RoleState {
  final String message;

  const RolesEmpty(this.message);

  @override
  List<Object?> get props => [message];
}
