part of 'checklist_bloc.dart';

abstract class ChecklistEvent extends Equatable {
  const ChecklistEvent();

  @override
  List<Object?> get props => [];
}

/// Load all checklist items (admin only)
class LoadChecklistItems extends ChecklistEvent {}

/// Load checklist items for a specific event
class LoadChecklistItemsByEvent extends ChecklistEvent {
  final String eventId;

  const LoadChecklistItemsByEvent(this.eventId);

  @override
  List<Object?> get props => [eventId];
}

/// Load checklist items for a specific user (both responsible and CC'd)
class LoadUserChecklistItems extends ChecklistEvent {
  final String teamMemberId;

  const LoadUserChecklistItems(this.teamMemberId);

  @override
  List<Object?> get props => [teamMemberId];
}

/// Add a new checklist item
class AddChecklistItem extends ChecklistEvent {
  final ChecklistItem item;

  const AddChecklistItem(this.item);

  @override
  List<Object?> get props => [item];
}

/// Update an existing checklist item
class UpdateChecklistItem extends ChecklistEvent {
  final ChecklistItem item;

  const UpdateChecklistItem(this.item);

  @override
  List<Object?> get props => [item];
}

/// Update only the status of a checklist item
class UpdateChecklistItemStatus extends ChecklistEvent {
  final String itemId;
  final bool newStatus;

  const UpdateChecklistItemStatus({
    required this.itemId,
    required this.newStatus,
  });

  @override
  List<Object?> get props => [itemId, newStatus];
}

/// Add a note to a checklist item (conversation-style)
class AddChecklistNote extends ChecklistEvent {
  final String itemId;
  final String content;
  final String authorRole;

  const AddChecklistNote({
    required this.itemId,
    required this.content,
    required this.authorRole,
  });

  @override
  List<Object?> get props => [itemId, content, authorRole];
}

/// Add a CC member to a checklist item
class AddCcMember extends ChecklistEvent {
  final String itemId;
  final String ccMemberId;

  const AddCcMember({
    required this.itemId,
    required this.ccMemberId,
  });

  @override
  List<Object?> get props => [itemId, ccMemberId];
}

/// Remove a CC member from a checklist item
class RemoveCcMember extends ChecklistEvent {
  final String itemId;
  final String ccMemberId;

  const RemoveCcMember({
    required this.itemId,
    required this.ccMemberId,
  });

  @override
  List<Object?> get props => [itemId, ccMemberId];
}

/// Delete a checklist item
class DeleteChecklistItem extends ChecklistEvent {
  final String itemId;

  const DeleteChecklistItem(this.itemId);

  @override
  List<Object?> get props => [itemId];
}

/// Refresh checklist items (reload from database)
class RefreshChecklistItems extends ChecklistEvent {}
