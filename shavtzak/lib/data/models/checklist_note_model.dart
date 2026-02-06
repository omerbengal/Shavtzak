import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/checklist_note.dart';

/// Model for converting between ChecklistNote entities and Firestore data
class ChecklistNoteModel {
  /// Creates a ChecklistNote from a Firestore map
  static ChecklistNote fromMap(Map<String, dynamic> data) {
    return ChecklistNote(
      id: data['id'] as String,
      content: data['content'] as String,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.parse(data['createdAt'].toString()),
      createdByTeamMemberId: data['createdByTeamMemberId'] as String,
      createdByTeamMemberName: data['createdByTeamMemberName'] as String?,
      authorRole: data['authorRole'] as String?,
    );
  }

  /// Converts a ChecklistNote entity to a Firestore map
  static Map<String, dynamic> toMap(ChecklistNote note) {
    return {
      'id': note.id,
      'content': note.content,
      'createdAt': Timestamp.fromDate(note.createdAt),
      'createdByTeamMemberId': note.createdByTeamMemberId,
      'createdByTeamMemberName': note.createdByTeamMemberName,
      if (note.authorRole != null) 'authorRole': note.authorRole,
    };
  }

  /// Converts a list of Firestore maps to a list of ChecklistNote entities
  static List<ChecklistNote> fromMapList(List<dynamic>? data) {
    if (data == null) return [];
    return data
        .map((item) => fromMap(item as Map<String, dynamic>))
        .toList();
  }

  /// Converts a list of ChecklistNote entities to a list of Firestore maps
  static List<Map<String, dynamic>> toMapList(List<ChecklistNote> notes) {
    return notes.map((note) => toMap(note)).toList();
  }
}
