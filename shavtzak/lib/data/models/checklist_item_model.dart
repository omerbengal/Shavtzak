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

    // Handle adminNote field
    AdminNoteEntry adminNote;
    if (data['adminNote'] != null && data['adminNote'] is Map) {
      final adminNoteData = data['adminNote'] as Map;
      adminNote = AdminNoteEntry(
        note: adminNoteData['note']?.toString() ?? '',
        updatedAt: adminNoteData['updatedAt'] is Timestamp
            ? (adminNoteData['updatedAt'] as Timestamp).toDate()
            : null,
      );
    } else {
      // Fallback for missing or old format
      adminNote = AdminNoteEntry(note: data['adminNote']?.toString() ?? '', updatedAt: null);
    }

    // Handle responsibleNote field
    ResponsibleNoteEntry responsibleNote;
    if (data['responsibleNote'] != null && data['responsibleNote'] is Map) {
      final responsibleNoteData = data['responsibleNote'] as Map;
      responsibleNote = ResponsibleNoteEntry(
        note: responsibleNoteData['note']?.toString() ?? '',
        updatedAt: responsibleNoteData['updatedAt'] is Timestamp
            ? (responsibleNoteData['updatedAt'] as Timestamp).toDate()
            : null,
      );
    } else {
      // Fallback for missing or old format
      responsibleNote = ResponsibleNoteEntry(note: data['responsibleNote']?.toString() ?? '', updatedAt: null);
    }

    return ChecklistItem(
      id: doc.id,
      eventId: data['eventId'] as String,
      name: data['name'] as String,
      responsibleId: data['responsibleId'] as String,
      responsibleNote: responsibleNote,
      adminNote: adminNote,
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
    // Find CC IDs that have notes but are NOT in ccIds (orphaned notes)
    final orphanedNoteKeys = item.ccNotes.keys.where((noteKey) =>
      !item.ccIds.contains(noteKey)
    ).toList();

    // Build update data with standard fields
    final updateData = <String, dynamic>{
      'eventId': item.eventId,
      'name': item.name,
      'responsibleId': item.responsibleId,
      'responsibleNote': {
        'note': item.responsibleNote.note,
        'updatedAt': item.responsibleNote.updatedAt != null
            ? Timestamp.fromDate(item.responsibleNote.updatedAt!)
            : null,
      },
      'adminNote': {
        'note': item.adminNote.note,
        'updatedAt': item.adminNote.updatedAt != null
            ? Timestamp.fromDate(item.adminNote.updatedAt!)
            : null,
      },
      'ccIds': item.ccIds,
      'status': item.status,
      'createdAt': Timestamp.fromDate(item.createdAt),
      'updatedAt': Timestamp.fromDate(item.updatedAt),
      'statusLastUpdatedAt': Timestamp.fromDate(item.statusLastUpdatedAt),
      // Only include createdByAdminId if it's not null (preserves existing values)
      if (item.createdByAdminId != null) 'createdByAdminId': item.createdByAdminId,
    };

    // Handle ccNotes based on whether there are orphaned notes
    if (orphanedNoteKeys.isEmpty) {
      // No orphaned notes - send the full ccNotes map (standard update)
      final ccNotesFirestore = item.ccNotes.map((key, entry) => MapEntry(key, {
        'note': entry.note,
        'updatedAt': entry.updatedAt != null ? Timestamp.fromDate(entry.updatedAt!) : null,
      }));
      updateData['ccNotes'] = ccNotesFirestore;
    } else {
      // There are orphaned notes - use individual field updates/deletions
      // This ensures Firestore properly deletes the orphaned nested fields
      for (final entry in item.ccNotes.entries) {
        final ccId = entry.key;
        final noteEntry = entry.value;

        if (orphanedNoteKeys.contains(ccId)) {
          // This note is orphaned - delete it from Firestore
          updateData["ccNotes.$ccId"] = FieldValue.delete();
        } else {
          // This note should remain - update it individually
          updateData["ccNotes.$ccId"] = {
            'note': noteEntry.note,
            'updatedAt': noteEntry.updatedAt != null ? Timestamp.fromDate(noteEntry.updatedAt!) : null,
          };
        }
      }
    }

    return updateData;
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