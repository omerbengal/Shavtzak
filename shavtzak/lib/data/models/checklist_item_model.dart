import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/checklist_item.dart';
import '../../domain/entities/checklist_note.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';
import 'checklist_note_model.dart';

/// Model for converting between ChecklistItem entities and Firestore documents
class ChecklistItemModel {
  /// Creates a ChecklistItemModel from a Firestore document
  static ChecklistItem fromFirestore(
    DocumentSnapshot doc,
    Event? event,
    TeamMember? responsible,
    List<TeamMember> ccMembers,
  ) {
    final data = doc.data() as Map<String, dynamic>;

    // Handle ccIds field - could be List<dynamic> or List<String>
    List<String> ccIds = [];
    if (data['ccIds'] != null) {
      ccIds = (data['ccIds'] as List).map((e) => e.toString()).toList();
    }

    // Parse notes array
    List<ChecklistNote> notes = [];
    if (data['notes'] != null && data['notes'] is List) {
      notes = ChecklistNoteModel.fromMapList(data['notes'] as List);
    }

    // Sort notes chronologically (oldest first)
    notes.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return ChecklistItem(
      id: doc.id,
      eventId: data['eventId'] as String,
      name: data['name'] as String,
      responsibleId: data['responsibleId'] as String,
      notes: notes,
      ccIds: ccIds,
      status: data['status'] as bool,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      statusLastUpdatedAt: (data['statusLastUpdatedAt'] as Timestamp).toDate(),
      createdByAdminId: data['createdByAdminId'] as String?,
      event: event,
      responsible: responsible,
      ccMembers: ccMembers,
    );
  }

  /// Converts a ChecklistItem entity to a Firestore document
  static Map<String, dynamic> toFirestore(ChecklistItem item) {
    final updateData = <String, dynamic>{
      'eventId': item.eventId,
      'name': item.name,
      'responsibleId': item.responsibleId,
      'notes': ChecklistNoteModel.toMapList(item.notes),
      'ccIds': item.ccIds,
      'status': item.status,
      'createdAt': Timestamp.fromDate(item.createdAt),
      'updatedAt': Timestamp.fromDate(item.updatedAt),
      'statusLastUpdatedAt': Timestamp.fromDate(item.statusLastUpdatedAt),
      if (item.createdByAdminId != null) 'createdByAdminId': item.createdByAdminId,
    };

    return updateData;
  }

  /// Creates a ChecklistItem from an entity (for creating new documents)
  static ChecklistItem fromEntity(ChecklistItem item) {
    return item;
  }

  /// Creates a ChecklistItem entity from a model
  static ChecklistItem toEntity(ChecklistItemModel model) {
    throw UnimplementedError('Use fromFirestore instead');
  }
}
