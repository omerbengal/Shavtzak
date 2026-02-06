import 'package:equatable/equatable.dart';

/// A single note in a checklist item's conversation thread
class ChecklistNote extends Equatable {
  final String id;
  final String content;
  final DateTime createdAt;
  final String createdByTeamMemberId;
  final String? createdByTeamMemberName; // Denormalized for display
  final String? authorRole; // Role context: מנהל, אחראי, מיודע

  const ChecklistNote({
    required this.id,
    required this.content,
    required this.createdAt,
    required this.createdByTeamMemberId,
    this.createdByTeamMemberName,
    this.authorRole,
  });

  ChecklistNote copyWith({
    String? id,
    String? content,
    DateTime? createdAt,
    String? createdByTeamMemberId,
    String? createdByTeamMemberName,
    String? authorRole,
  }) {
    return ChecklistNote(
      id: id ?? this.id,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      createdByTeamMemberId: createdByTeamMemberId ?? this.createdByTeamMemberId,
      createdByTeamMemberName: createdByTeamMemberName ?? this.createdByTeamMemberName,
      authorRole: authorRole ?? this.authorRole,
    );
  }

  @override
  List<Object?> get props => [id, content, createdAt, createdByTeamMemberId, createdByTeamMemberName, authorRole];
}
