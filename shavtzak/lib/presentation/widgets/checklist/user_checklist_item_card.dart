import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/services/checklist_permission_service.dart';
import 'chat_bubble.dart';

/// Class to hold unified note data for sorting
class _NoteData {
  final String type; // 'admin', 'responsible', 'cc'
  final String? ccMemberId; // Only for CC notes
  final String note;
  final DateTime? timestamp;
  final TeamMember? member; // For responsible and CC notes
  final bool isOwn;

  _NoteData({
    required this.type,
    this.ccMemberId,
    required this.note,
    this.timestamp,
    this.member,
    required this.isOwn,
  });
}

/// Get all notes sorted chronologically by timestamp (for user view)
/// Notes with timestamps are sorted ascending, notes without timestamp come last
List<_NoteData> _getAllNotesSortedForUser(ChecklistItem item, TeamMember user, ChecklistUserRole userRole) {
  final notes = <_NoteData>[];

  // Add admin note (always shown, never own in user view)
  if (item.adminNote.note.isNotEmpty) {
    notes.add(_NoteData(
      type: 'admin',
      note: item.adminNote.note,
      timestamp: item.adminNote.updatedAt,
      isOwn: false,
    ));
  }

  // Add responsible note
  if (item.responsibleNote.note.isNotEmpty) {
    if (userRole == ChecklistUserRole.responsible) {
      // User IS the responsible - show as own note
      notes.add(_NoteData(
        type: 'responsible',
        note: item.responsibleNote.note,
        timestamp: item.responsibleNote.updatedAt,
        member: item.responsible,
        isOwn: true,
      ));
    } else if (userRole == ChecklistUserRole.cc) {
      // User is CC - show responsible's note as other's message
      notes.add(_NoteData(
        type: 'responsible',
        note: item.responsibleNote.note,
        timestamp: item.responsibleNote.updatedAt,
        member: item.responsible,
        isOwn: false,
      ));
    }
  }

  // Add all CC notes (including user's own - sorted chronologically)
  for (final entry in item.ccNotes.entries) {
    if (entry.value.note.isEmpty) continue;

    final ccMember = item.ccMembers.firstWhere(
      (m) => m.id == entry.key,
      orElse: () {
        final now = DateTime.now();
        return TeamMember(
          id: entry.key,
          name: 'משתמש לא ידוע',
          isActive: true,
          isPermanent: false,
          constraints: [],
          roleCapabilities: {},
          createdAt: now,
          updatedAt: now,
          uniqueKey: '',
          isAdmin: false,
        );
      },
    );

    final isOwn = entry.key == user.id;
    notes.add(_NoteData(
      type: 'cc',
      ccMemberId: entry.key,
      note: entry.value.note,
      timestamp: entry.value.updatedAt,
      member: ccMember,
      isOwn: isOwn,
    ));
  }

  // Sort by timestamp (notes with timestamps first, then legacy notes)
  notes.sort((a, b) {
    final aTime = a.timestamp;
    final bTime = b.timestamp;
    if (aTime != null && bTime != null) return aTime.compareTo(bTime);
    if (aTime != null && bTime == null) return -1;
    if (aTime == null && bTime != null) return 1;
    return 0;
  });

  return notes;
}

/// Card widget for displaying a checklist item in the user view
class UserChecklistItemCard extends StatelessWidget {
  final ChecklistItem item;
  final TeamMember user;
  final ValueChanged<bool>? onStatusChanged;
  final VoidCallback? onEditItem;
  final List<TeamMember>? allTeamMembers;

  const UserChecklistItemCard({
    super.key,
    required this.item,
    required this.user,
    this.onStatusChanged,
    this.onEditItem,
    this.allTeamMembers,
  });

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  /// Get the admin member who created this item
  TeamMember? _getAdminMember() {
    if (item.createdByAdminId == null) return null;
    return allTeamMembers?.firstWhere(
      (m) => m.id == item.createdByAdminId,
      orElse: () => item.responsible!,
    );
  }

  Color _getBackgroundColor() {
    // Use same colors as EventListScreen
    return item.status
        ? Colors.lightGreen.withValues(alpha: 0.3)
        : Colors.red.withValues(alpha: 0.3);
  }

  ChecklistUserRole _getUserRole() {
    return ChecklistPermissionService.getUserRole(item, user);
  }

  @override
  Widget build(BuildContext context) {
    final userRole = _getUserRole();
    final canUpdateStatus = ChecklistPermissionService.canUpdateStatus(item, user);

    // Get all notes sorted chronologically (including user's own CC note)
    final sortedNotes = _getAllNotesSortedForUser(item, user, userRole);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListTile(
        onTap: onEditItem,
        title: Text(
          item.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event info (ALWAYS shown)
            if (item.event != null) ...[
              Text(
                'אירוע: ${item.event!.name}',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                'תאריך: ${_formatDate(item.event!.startDate)}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            // Responsible (shown appropriately)
            if (userRole == ChecklistUserRole.responsible)
              Text(
                'אחראי: את/ה',
                style: const TextStyle(fontSize: 12),
              )
            else if (item.responsible != null)
              Text(
                'אחראי: ${item.responsible!.name}',
                style: const TextStyle(fontSize: 12),
              ),
            // Show location if available
            if (item.event?.location.isNotEmpty == true)
              Text(
                'מיקום: ${item.event!.location}',
                style: const TextStyle(fontSize: 12),
              ),
            // CC names (if any)
            if (item.ccMembers.isNotEmpty)
              Text(
                'מיודעים: ${item.ccMembers.map((m) => m.name).join(", ")}',
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 8),
            // Notes displayed as chat bubbles in chronological order
            ...sortedNotes.map((noteData) {
              // Determine color and author label based on note type
              final bubbleColor = switch (noteData.type) {
                'admin' => Colors.purple.withValues(alpha: 0.3),
                'responsible' => Colors.amber.withValues(alpha: 0.3),
                'cc' => Colors.grey.withValues(alpha: 0.3),
                _ => Colors.grey.withValues(alpha: 0.3),
              };

              // Get admin member for admin notes
              final adminMember = _getAdminMember();

              final authorName = switch (noteData.type) {
                'admin' => noteData.isOwn
                    ? 'אני'
                    : '${adminMember?.name ?? 'מנהל'} (מנהל)',
                'responsible' => noteData.isOwn
                    ? 'אני'
                    : '${noteData.member?.name ?? "לא ידוע"} (אחראי)',
                'cc' => noteData.isOwn
                    ? 'אני'
                    : '${noteData.member?.name ?? "לא ידוע"} (מיודע)',
                _ => 'הערה',
              };

              // Format timestamp as HH:mm, DD/MM (removed seconds)
              final timestamp = noteData.timestamp != null
                  ? DateFormat('HH:mm, dd/M').format(noteData.timestamp!)
                  : null;

              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: ChatBubble(
                  authorName: authorName,
                  message: noteData.note,
                  bubbleColor: bubbleColor,
                  isOwnMessage: noteData.isOwn,
                  alignRight: noteData.isOwn,
                  timestamp: timestamp,
                  showAuthorLabel: true,
                ),
              );
            }),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status toggle (only if responsible)
            if (canUpdateStatus && onStatusChanged != null)
              Container(
                decoration: BoxDecoration(
                  color: item.status ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: InkWell(
                  onTap: () => onStatusChanged?.call(!item.status),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      item.status ? 'כן' : 'לא',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              )
            else if (!canUpdateStatus)
              // Just display status (non-editable)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: item.status ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  item.status ? 'כן' : 'לא',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
