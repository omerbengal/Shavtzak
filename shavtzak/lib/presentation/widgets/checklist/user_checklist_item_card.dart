import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/services/checklist_permission_service.dart';
import 'chat_bubble.dart';

/// Helper function to get CC notes sorted by timestamp
/// Notes with timestamps are sorted ascending, notes without timestamp come last
List<MapEntry<String, CcNoteEntry>> _getSortedCcNotes(ChecklistItem item, String excludeUserId) {
  final entries = item.ccNotes.entries
      .where((entry) => entry.value.note.isNotEmpty && entry.key != excludeUserId)
      .toList();

  entries.sort((a, b) {
    final aTime = a.value.updatedAt;
    final bTime = b.value.updatedAt;

    // Both have timestamps - sort ascending
    if (aTime != null && bTime != null) {
      return aTime.compareTo(bTime);
    }
    // a has timestamp, b doesn't - a comes first
    if (aTime != null && bTime == null) {
      return -1;
    }
    // a doesn't have timestamp, b does - b comes first
    if (aTime == null && bTime != null) {
      return 1;
    }
    // Neither has timestamp - maintain order
    return 0;
  });

  return entries;
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

  Color _getBackgroundColor() {
    // Use same colors as EventListScreen
    return item.status
        ? Colors.lightGreen.withValues(alpha: 0.3)
        : Colors.red.withValues(alpha: 0.3);
  }

  ChecklistUserRole _getUserRole() {
    return ChecklistPermissionService.getUserRole(item, user);
  }

  String _getUserNote() {
    if (user.id == item.responsibleId) {
      return item.responsibleNote;
    }
    return item.getCcNote(user.id) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final userRole = _getUserRole();
    final canUpdateStatus = ChecklistPermissionService.canUpdateStatus(item, user);
    final userNote = _getUserNote();

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
            // Show responsible person if user is CC'd
            if (userRole == ChecklistUserRole.cc && item.responsible != null)
              Text(
                'אחראי: ${item.responsible!.name}',
                style: const TextStyle(fontSize: 12),
              ),
            // Show location if available
            if (item.event?.location?.isNotEmpty == true)
              Text(
                'מיקום: ${item.event!.location}',
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 8),
            // Notes displayed as chat bubbles
            // 1. Admin note (purple bubble, never own in user view)
            if (item.adminNote.isNotEmpty) ...[
              ChatBubble(
                authorName: 'הערת מנהל',
                message: item.adminNote,
                bubbleColor: Colors.purple.withValues(alpha: 0.3),
                isOwnMessage: false,
                alignRight: false,
                showAuthorLabel: true,
              ),
              const SizedBox(height: 2),
            ],
            // 2. Responsible note (yellow bubble)
            if (item.responsibleNote.isNotEmpty) ...[
              if (userRole == ChecklistUserRole.responsible) ...[
                // User IS the responsible - show as own note
                ChatBubble(
                  authorName: 'הערה אישית שלך (אחראי)',
                  message: item.responsibleNote,
                  bubbleColor: Colors.amber.withValues(alpha: 0.3),
                  isOwnMessage: true,
                  alignRight: true,
                  showAuthorLabel: true,
                ),
                const SizedBox(height: 2),
              ] else if (userRole == ChecklistUserRole.cc) ...[
                // User is CC - show responsible's note as other's message
                ChatBubble(
                  authorName: 'אחראי: ${item.responsible?.name ?? "לא ידוע"}',
                  message: item.responsibleNote,
                  bubbleColor: Colors.amber.withValues(alpha: 0.3),
                  isOwnMessage: false,
                  alignRight: false,
                  showAuthorLabel: true,
                ),
                const SizedBox(height: 2),
              ],
            ],
            // 3. CC notes from others (gray bubbles, exclude own)
            ..._getSortedCcNotes(item, user.id).map((entry) {
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
              final timestamp = entry.value.updatedAt != null
                  ? DateFormat('HH:mm').format(entry.value.updatedAt!)
                  : null;

              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: ChatBubble(
                authorName: 'מיודע: ${ccMember.name}',
                message: entry.value.note,
                bubbleColor: Colors.grey.withValues(alpha: 0.3),
                isOwnMessage: false,
                alignRight: false,
                timestamp: timestamp,
                showAuthorLabel: true,
                ),
              );
            }),
            // 4. User's own CC note (if they are CC and have a note)
            if (userRole == ChecklistUserRole.cc && userNote.isNotEmpty) ...[
              ChatBubble(
                authorName: 'הערה אישית שלך (מיודע)',
                message: userNote,
                bubbleColor: Colors.grey.withValues(alpha: 0.3),
                isOwnMessage: true,
                alignRight: true,
                timestamp: item.getCcNoteEntry(user.id)?.updatedAt != null
                    ? DateFormat('HH:mm').format(item.getCcNoteEntry(user.id)!.updatedAt!)
                    : null,
                showAuthorLabel: true,
              ),
            ],
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