import 'package:flutter/material.dart';
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/services/checklist_permission_service.dart';

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
  final VoidCallback? onDelete;

  const ChecklistItemCard({
    super.key,
    required this.item,
    this.isAdmin = false,
    this.currentUserId,
    this.onTap,
    this.onStatusChanged,
    this.onDelete,
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
    final canEdit = isAdmin;
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
            // Admin notes (highest priority, shown first)
            if (item.adminNote.isNotEmpty) ...[
              const SizedBox(height: 4),
              // Check if current user is the creator
              if (currentUserId != null && item.createdByAdminId == currentUserId)
                // Personal note display for the creator
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'הערה אישית שלך (כאדמין שיצר את פריט הרשימה):',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.blue,
                        ),
                      ),
                      Text(
                        item.adminNote,
                        style: const TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ],
                  ),
                )
              else
                // For other admins - show as "הערה אישית של האדמין שיצר את פריט הרשימה"
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'הערה אישית של האדמין שיצר את פריט הרשימה:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.purple,
                        ),
                      ),
                      Text(
                        item.adminNote,
                        style: const TextStyle(fontSize: 12, color: Colors.purple),
                      ),
                    ],
                  ),
                ),
            ],
            if (item.responsibleNote.isNotEmpty)
              Text(
                'הערת אחראי (${item.responsible?.name ?? "לא ידוע"}): ${item.responsibleNote}',
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            // Show all CC notes (visible to admin), sorted by timestamp
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
              return Text(
                'הערת ${ccMember.name}: ${entry.value.note}',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey[700]),
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
            if (isAdmin || canEdit) ...[
              const SizedBox(width: 8),
              // Edit button
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: onTap,
                tooltip: 'ערוך',
              ),
              // Delete button (admin only)
              if (isAdmin && onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete, size: 20),
                  onPressed: onDelete,
                  tooltip: 'מחק',
                ),
            ],
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