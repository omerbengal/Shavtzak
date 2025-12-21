import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/checklist_item.dart';
import '../../domain/entities/event.dart';
import '../../domain/entities/team_member.dart';

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

    // Handle ccNotes field - supports both old (Map<String, String>) and new (Map<String, {note, updatedAt}>) formats
    Map<String, CcNoteEntry> ccNotes = {};
    if (data['ccNotes'] != null) {
      final notesMap = data['ccNotes'] as Map;
      ccNotes = notesMap.map((key, value) {
        // Handle new format: {note: String, updatedAt: Timestamp}
        if (value is Map && value.containsKey('note')) {
          final noteText = value['note']?.toString() ?? '';
          final updatedAt = value['updatedAt'] is Timestamp
              ? (value['updatedAt'] as Timestamp).toDate()
              : null;
          return MapEntry(key.toString(), CcNoteEntry(note: noteText, updatedAt: updatedAt));
        }
        // Handle old format: just a string
        return MapEntry(key.toString(), CcNoteEntry(note: value.toString(), updatedAt: null));
      });
    }

    return ChecklistItem(
      id: doc.id,
      eventId: data['eventId'] as String,
      name: data['name'] as String,
      responsibleId: data['responsibleId'] as String,
      responsibleNote: data['responsibleNote'] as String? ?? '',
      adminNote: data['adminNote'] as String? ?? '',
      ccIds: ccIds,
      ccNotes: ccNotes,
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
    // Convert ccNotes to Firestore format with timestamps
    final ccNotesFirestore = item.ccNotes.map((key, entry) => MapEntry(key, {
      'note': entry.note,
      'updatedAt': entry.updatedAt != null ? Timestamp.fromDate(entry.updatedAt!) : null,
    }));

    return {
      'eventId': item.eventId,
      'name': item.name,
      'responsibleId': item.responsibleId,
      'responsibleNote': item.responsibleNote,
      'adminNote': item.adminNote,
      'ccIds': item.ccIds,
      'ccNotes': ccNotesFirestore,
      'status': item.status,
      'createdAt': Timestamp.fromDate(item.createdAt),
      'updatedAt': Timestamp.fromDate(item.updatedAt),
      'statusLastUpdatedAt': Timestamp.fromDate(item.statusLastUpdatedAt),
      'createdByAdminId': item.createdByAdminId,
    };
  }

  /// Creates a ChecklistItem from an entity (for creating new documents)
  static ChecklistItem fromEntity(ChecklistItem item) {
    return item;
  }

  /// Creates a ChecklistItem entity from a model
  static ChecklistItem toEntity(ChecklistItemModel model) {
    // This method is not typically needed since we work directly with entities
    // but kept for consistency with other model patterns
    throw UnimplementedError('Use fromFirestore instead');
  }
}