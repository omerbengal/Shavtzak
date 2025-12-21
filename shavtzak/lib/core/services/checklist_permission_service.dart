import '../../domain/entities/checklist_item.dart';
import '../../domain/entities/team_member.dart';

/// Service for managing checklist item permissions
class ChecklistPermissionService {
  /// Check if a user can view a checklist item
  static bool canViewItem(ChecklistItem item, TeamMember user) {
    if (user.isAdmin) return true;
    return item.responsibleId == user.id || item.ccIds.contains(user.id);
  }

  /// Check if a user can edit a checklist item (all fields except CC notes)
  static bool canEditItem(ChecklistItem item, TeamMember user) {
    if (user.isAdmin) return true;
    return item.responsibleId == user.id;
  }

  /// Check if a user can edit a specific CC note
  static bool canEditCcNote(ChecklistItem item, TeamMember user, String ccId) {
    if (user.isAdmin) return true;
    return ccId == user.id;
  }

  /// Check if a user can update the status
  static bool canUpdateStatus(ChecklistItem item, TeamMember user) {
    if (user.isAdmin) return true;
    return item.responsibleId == user.id;
  }

  /// Check if a user can add CC members
  static bool canAddCcMembers(ChecklistItem item, TeamMember user) {
    if (user.isAdmin) return true;
    return item.responsibleId == user.id;
  }

  /// Check if a user can remove CC members
  static bool canRemoveCcMembers(ChecklistItem item, TeamMember user) {
    if (user.isAdmin) return true;
    return item.responsibleId == user.id;
  }

  /// Check if a user can delete the checklist item
  static bool canDeleteItem(ChecklistItem item, TeamMember user) {
    return user.isAdmin;
  }

  /// Get the user's role for a checklist item
  static ChecklistUserRole getUserRole(ChecklistItem item, TeamMember user) {
    if (user.isAdmin) return ChecklistUserRole.admin;
    if (item.responsibleId == user.id) return ChecklistUserRole.responsible;
    if (item.ccIds.contains(user.id)) return ChecklistUserRole.cc;
    return ChecklistUserRole.none;
  }
}

/// Enum representing a user's role in relation to a checklist item
enum ChecklistUserRole {
  /// Admin can do everything
  admin,
  /// Responsible person can edit the item, add/remove CC, update status
  responsible,
  /// CC'd person can only edit their own note
  cc,
  /// No access
  none,
}