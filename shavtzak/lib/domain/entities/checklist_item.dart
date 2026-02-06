import 'package:equatable/equatable.dart';
import 'checklist_note.dart';
import 'event.dart';
import 'team_member.dart';

/// Entity representing a checklist item for an event
class ChecklistItem extends Equatable {
  final String id;
  final String eventId; // Foreign key to Event
  final String name; // Title of the checklist item
  final String responsibleId; // Foreign key to TeamMember (אחראי)
  final List<ChecklistNote> notes; // Conversation-like notes thread
  final List<String> ccIds; // List of team member IDs (מיודעים)
  final bool status; // true = כן, false = לא
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime statusLastUpdatedAt; // Hidden timestamp for status changes
  final String? createdByAdminId; // The admin who created this item

  // Computed fields (populated by repository)
  final Event? event;
  final TeamMember? responsible;
  final List<TeamMember> ccMembers;

  const ChecklistItem({
    required this.id,
    required this.eventId,
    required this.name,
    required this.responsibleId,
    this.notes = const [],
    this.ccIds = const [],
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.statusLastUpdatedAt,
    this.createdByAdminId,
    this.event,
    this.responsible,
    this.ccMembers = const [],
  });

  /// Get the content of the latest note, or null if no notes
  String? get latestNoteContent {
    return notes.isEmpty ? null : notes.last.content;
  }

  /// Creates a copy with updated values
  ChecklistItem copyWith({
    String? id,
    String? eventId,
    String? name,
    String? responsibleId,
    List<ChecklistNote>? notes,
    List<String>? ccIds,
    bool? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? statusLastUpdatedAt,
    String? createdByAdminId,
    Event? event,
    TeamMember? responsible,
    List<TeamMember>? ccMembers,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      eventId: eventId ?? this.eventId,
      name: name ?? this.name,
      responsibleId: responsibleId ?? this.responsibleId,
      notes: notes ?? this.notes,
      ccIds: ccIds ?? this.ccIds,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      statusLastUpdatedAt: statusLastUpdatedAt ?? this.statusLastUpdatedAt,
      createdByAdminId: createdByAdminId ?? this.createdByAdminId,
      event: event ?? this.event,
      responsible: responsible ?? this.responsible,
      ccMembers: ccMembers ?? this.ccMembers,
    );
  }

  /// Check if a user can view this checklist item
  bool userCanView(String teamMemberId, bool isAdmin) {
    if (isAdmin) return true;
    return responsibleId == teamMemberId || ccIds.contains(teamMemberId);
  }

  /// Check if a user can edit this checklist item
  bool userCanEdit(String teamMemberId, bool isAdmin) {
    if (isAdmin) return true;
    return responsibleId == teamMemberId;
  }

  /// Add a CC'd team member
  ChecklistItem withAddedCc(String teamMemberId) {
    if (ccIds.contains(teamMemberId)) return this;
    return copyWith(
      ccIds: [...ccIds, teamMemberId],
      updatedAt: DateTime.now(),
    );
  }

  /// Remove a CC'd team member
  ChecklistItem withRemovedCc(String teamMemberId) {
    if (!ccIds.contains(teamMemberId)) return this;
    return copyWith(
      ccIds: ccIds.where((id) => id != teamMemberId).toList(),
      updatedAt: DateTime.now(),
    );
  }

  /// Update the status with timestamp
  ChecklistItem withUpdatedStatus(bool newStatus) {
    return copyWith(
      status: newStatus,
      statusLastUpdatedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        eventId,
        name,
        responsibleId,
        notes,
        ccIds,
        status,
        createdAt,
        updatedAt,
        statusLastUpdatedAt,
        createdByAdminId,
        event,
        responsible,
        ccMembers,
      ];

  @override
  String toString() {
    return 'ChecklistItem{id: $id, name: $name, eventId: $eventId, responsibleId: $responsibleId, status: $status}';
  }
}
