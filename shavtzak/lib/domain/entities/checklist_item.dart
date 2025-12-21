import 'package:equatable/equatable.dart';
import 'event.dart';
import 'team_member.dart';

/// Entry for a CC note with timestamp for ordering
class CcNoteEntry extends Equatable {
  final String note;
  final DateTime? updatedAt; // null for legacy entries (before timestamp support)

  const CcNoteEntry({
    required this.note,
    this.updatedAt,
  });

  CcNoteEntry copyWith({
    String? note,
    DateTime? updatedAt,
  }) {
    return CcNoteEntry(
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [note, updatedAt];
}

/// Entity representing a checklist item for an event
class ChecklistItem extends Equatable {
  final String id;
  final String eventId; // Foreign key to Event
  final String name; // Title of the checklist item
  final String responsibleId; // Foreign key to TeamMember (אחראי)
  final String responsibleNote; // פירוט אחראי
  final String adminNote; // הערת מנהל
  final List<String> ccIds; // List of team member IDs (מיודעים)
  final Map<String, CcNoteEntry> ccNotes; // Map of teamMemberId → CcNoteEntry (פירוט מיודעים)
  final bool status; // true = כן, false = לא
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime statusLastUpdatedAt; // Hidden timestamp for status changes
  final String? createdByAdminId; // The admin who created this item (for personal note display)

  // Computed fields (populated by repository)
  final Event? event;
  final TeamMember? responsible;
  final List<TeamMember> ccMembers;

  const ChecklistItem({
    required this.id,
    required this.eventId,
    required this.name,
    required this.responsibleId,
    this.responsibleNote = '',
    this.adminNote = '',
    this.ccIds = const [],
    this.ccNotes = const {},
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.statusLastUpdatedAt,
    this.createdByAdminId,
    this.event,
    this.responsible,
    this.ccMembers = const [],
  });

  /// Creates a copy with updated values
  ChecklistItem copyWith({
    String? id,
    String? eventId,
    String? name,
    String? responsibleId,
    String? responsibleNote,
    String? adminNote,
    List<String>? ccIds,
    Map<String, CcNoteEntry>? ccNotes,
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
      responsibleNote: responsibleNote ?? this.responsibleNote,
      adminNote: adminNote ?? this.adminNote,
      ccIds: ccIds ?? this.ccIds,
      ccNotes: ccNotes ?? this.ccNotes,
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

  /// Check if a user can edit a specific CC note
  bool userCanEditCcNote(String teamMemberId, String ccId, bool isAdmin) {
    if (isAdmin) return true;
    return ccId == teamMemberId;
  }

  /// Get the note for a specific CC'd team member
  String? getCcNote(String teamMemberId) {
    return ccNotes[teamMemberId]?.note;
  }

  /// Get the full CcNoteEntry for a specific CC'd team member
  CcNoteEntry? getCcNoteEntry(String teamMemberId) {
    return ccNotes[teamMemberId];
  }

  /// Update the note for a specific CC'd team member
  ChecklistItem withUpdatedCcNote(String teamMemberId, String note) {
    final updatedNotes = Map<String, CcNoteEntry>.from(ccNotes);
    if (note.isNotEmpty) {
      updatedNotes[teamMemberId] = CcNoteEntry(
        note: note,
        updatedAt: DateTime.now(),
      );
    } else {
      updatedNotes.remove(teamMemberId);
    }
    return copyWith(ccNotes: updatedNotes, updatedAt: DateTime.now());
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
    final updatedNotes = Map<String, CcNoteEntry>.from(ccNotes);
    updatedNotes.remove(teamMemberId);
    return copyWith(
      ccIds: ccIds.where((id) => id != teamMemberId).toList(),
      ccNotes: updatedNotes,
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
        responsibleNote,
        adminNote,
        ccIds,
        ccNotes,
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