import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/team_member.dart';
import 'chat_bubble.dart';

/// Helper function to get CC notes sorted by timestamp (for admin view)
/// Notes with timestamps are sorted ascending, notes without timestamp come last
List<MapEntry<String, CcNoteEntry>> _getSortedCcNotesForAdmin(ChecklistItem item) {
  final entries = item.ccNotes.entries
      .where((entry) => entry.value.note.isNotEmpty)
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

/// Card widget for displaying a checklist item
class ChecklistItemCard extends StatelessWidget {
  final ChecklistItem item;
  final bool isAdmin;
  final String? currentUserId; // Current admin's ID for personal note display
  final VoidCallback? onTap;
  final ValueChanged<bool>? onStatusChanged;

  const ChecklistItemCard({
    super.key,
    required this.item,
    this.isAdmin = false,
    this.currentUserId,
    this.onTap,
    this.onStatusChanged,
  });

  Color _getBackgroundColor() {
    // Use same colors as EventListScreen
    return item.status
        ? Colors.lightGreen.withValues(alpha: 0.3)
        : Colors.red.withValues(alpha: 0.3);
  }

  @override
  Widget build(BuildContext context) {
    // For now, we don't pass the user, so we use isAdmin to determine permissions
    final canUpdateStatus = isAdmin;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListTile(
        title: Text(
          item.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Text(
              'אחראי: ${item.responsible?.name ?? "לא ידוע"}',
              style: const TextStyle(fontSize: 12),
            ),
            if (item.ccMembers.isNotEmpty)
              Text(
                'מיודעים: ${item.ccMembers.map((m) => m.name).join(", ")}',
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 8),
            // Notes displayed as chat bubbles
            // 1. Admin note (purple bubble)
            if (item.adminNote.isNotEmpty) ...[
              ChatBubble(
                authorName: (currentUserId != null && item.createdByAdminId == currentUserId)
                    ? 'הערה אישית שלך (מנהל)'
                    : 'הערת מנהל',
                message: item.adminNote,
                bubbleColor: Colors.purple.withValues(alpha: 0.3),
                isOwnMessage: currentUserId != null && item.createdByAdminId == currentUserId,
                alignRight: currentUserId != null && item.createdByAdminId == currentUserId,
                showAuthorLabel: true,
              ),
              const SizedBox(height: 2),
            ],
            // 2. Responsible note (yellow bubble)
            if (item.responsibleNote.isNotEmpty) ...[
              ChatBubble(
                authorName: (currentUserId != null && item.responsibleId == currentUserId)
                    ? 'הערה אישית שלך (אחראי)'
                    : 'אחראי: ${item.responsible?.name ?? "לא ידוע"}',
                message: item.responsibleNote,
                bubbleColor: Colors.amber.withValues(alpha: 0.3),
                isOwnMessage: currentUserId != null && item.responsibleId == currentUserId,
                alignRight: currentUserId != null && item.responsibleId == currentUserId,
                showAuthorLabel: true,
              ),
              const SizedBox(height: 2),
            ],
            // 3. CC notes (gray bubbles, sorted by timestamp)
            ..._getSortedCcNotesForAdmin(item).map((entry) {
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
              final isOwn = currentUserId != null && entry.key == currentUserId;
              final timestamp = entry.value.updatedAt != null
                  ? DateFormat('HH:mm').format(entry.value.updatedAt!)
                  : null;

              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: ChatBubble(
                authorName: isOwn
                    ? 'הערה אישית שלך (מיודע)'
                    : 'מיודע: ${ccMember.name}',
                message: entry.value.note,
                bubbleColor: Colors.grey.withValues(alpha: 0.3),
                isOwnMessage: isOwn,
                alignRight: isOwn,
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
            // Status toggle button
            if (onStatusChanged != null && canUpdateStatus)
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
            else
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
        onTap: onTap,
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}