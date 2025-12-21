import 'package:flutter/material.dart';
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/services/checklist_permission_service.dart';

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
  final VoidCallback? onEditNote;

  const UserChecklistItemCard({
    super.key,
    required this.item,
    required this.user,
    this.onStatusChanged,
    this.onEditNote,
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
    final canEditItem = ChecklistPermissionService.canEditItem(item, user);
    final canUpdateStatus = ChecklistPermissionService.canUpdateStatus(item, user);
    final canEditCcNote = ChecklistPermissionService.canEditCcNote(item, user, user.id);
    final userNote = _getUserNote();

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
            // Notes display in precedence order: Admin > Responsible > CCs
            // 1. Admin notes (visible to everyone)
            if (item.adminNote.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'הערת מנהל: ${item.adminNote}',
                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.purple, fontWeight: FontWeight.w500),
              ),
            ],
            // 2. Responsible note (don't show if user is the responsible)
            if (item.responsibleNote.isNotEmpty && userRole != ChecklistUserRole.responsible) ...[
              const SizedBox(height: 2),
              Text(
                'הערת אחראי (${item.responsible?.name ?? "לא ידוע"}): ${item.responsibleNote}',
                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
              ),
            ],
            // 3. CC notes (don't show user's own CC note if they are CC)
            // Sort by timestamp: notes with timestamp ascending, then notes without timestamp
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
              return Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'הערת ${ccMember.name}: ${entry.value.note}',
                  style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
                ),
              );
            }),
            // Show user's note if they have one
            if (userNote.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      userRole == ChecklistUserRole.responsible ? 'הערה אישית שלך (כאחראי):' : 'הערה אישית שלך (כמיודע):',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.blue,
                      ),
                    ),
                    Text(
                      userNote,
                      style: const TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ],
                ),
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
            // Edit note button
            if ((canEditItem || canEditCcNote) && onEditNote != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  userNote.isEmpty ? Icons.note_add : Icons.edit_note,
                  size: 20,
                ),
                onPressed: onEditNote,
                tooltip: userNote.isEmpty ? 'הוסף הערה' : 'ערוך הערה',
              ),
            ],
          ],
        ),
      ),
    );
  }
}