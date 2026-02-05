import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/team_member.dart';
import '../map_location_picker.dart';
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

/// Get all notes sorted chronologically by timestamp
/// Notes with timestamps are sorted ascending, notes without timestamp come last
List<_NoteData> _getAllNotesSorted(ChecklistItem item, String? currentUserId, List<TeamMember> allTeamMembers) {
  final notes = <_NoteData>[];

  // Add admin notes (purple color, "(מנהל)" label) - one per admin
  for (final entry in item.adminNotes.entries) {
    if (entry.value.note.isNotEmpty) {
      final adminId = entry.key;
      final admin = allTeamMembers.firstWhere(
        (m) => m.id == adminId,
        orElse: () {
          final now = DateTime.now();
          return TeamMember(
            id: adminId,
            name: 'מנהל לא ידוע',
            isActive: true,
            isPermanent: false,
            constraints: [],
            roleCapabilities: {},
            createdAt: now,
            updatedAt: now,
            uniqueKey: '',
            isAdmin: true,
          );
        },
      );
      notes.add(_NoteData(
        type: 'admin',
        note: entry.value.note,
        timestamp: entry.value.updatedAt,
        member: admin,
        isOwn: currentUserId != null && adminId == currentUserId,
      ));
    }
  }

  // Add responsible note
  if (item.responsibleNote.note.isNotEmpty) {
    notes.add(_NoteData(
      type: 'responsible',
      note: item.responsibleNote.note,
      timestamp: item.responsibleNote.updatedAt,
      member: item.responsible,
      isOwn: currentUserId != null && item.responsibleId == currentUserId,
    ));
  }

  // Add CC notes
  for (final entry in item.ccNotes.entries) {
    if (entry.value.note.isNotEmpty) {
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
      notes.add(_NoteData(
        type: 'cc',
        ccMemberId: entry.key,
        note: entry.value.note,
        timestamp: entry.value.updatedAt,
        member: ccMember,
        isOwn: currentUserId != null && entry.key == currentUserId,
      ));
    }
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

/// Card widget for displaying a checklist item
class ChecklistItemCard extends StatelessWidget {
  final ChecklistItem item;
  final bool isAdmin;
  final String? currentUserId; // Current admin's ID for personal note display
  final List<TeamMember> allTeamMembers; // All team members for admin name lookup
  final VoidCallback? onTap;
  final ValueChanged<bool>? onStatusChanged;

  const ChecklistItemCard({
    super.key,
    required this.item,
    required this.allTeamMembers,
    this.isAdmin = false,
    this.currentUserId,
    this.onTap,
    this.onStatusChanged,
  });

  /// Get the admin member who created this item
  TeamMember? _getAdminMember() {
    if (item.createdByAdminId == null) return null;
    return allTeamMembers.firstWhere(
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

  @override
  Widget build(BuildContext context) {
    // For now, we don't pass the user, so we use isAdmin to determine permissions
    final canUpdateStatus = isAdmin;

    // Get all notes sorted chronologically
    final sortedNotes = _getAllNotesSorted(item, currentUserId, allTeamMembers);

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
              if (item.event!.location.isNotEmpty)
                Text(
                  'מיקום: ${MapLocationResult.stripCoordinates(item.event!.location)}',
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
            // Notes displayed as chat bubbles in chronological order
            ...sortedNotes.map((noteData) {
              // Determine color and author label based on note type
              final bubbleColor = switch (noteData.type) {
                'admin' => Colors.purple.withValues(alpha: 0.3),
                'responsible' => Colors.amber.withValues(alpha: 0.3),
                'cc' => Colors.grey.withValues(alpha: 0.3),
                _ => Colors.grey.withValues(alpha: 0.3),
              };

              final authorName = switch (noteData.type) {
                'admin' => noteData.isOwn
                    ? 'אני (מנהל)'
                    : '${noteData.member?.name ?? "מנהל"} (מנהל)',
                'responsible' => noteData.isOwn
                    ? 'אני (אחראי)'
                    : '${noteData.member?.name ?? "לא ידוע"} (אחראי)',
                'cc' => noteData.isOwn
                    ? 'אני'
                    : '${noteData.member?.name ?? "לא ידוע"} (מיודע)',
                _ => 'הערה',
              };

              // Format timestamp as HH:mm, DD/MM (removed seconds)
              final timestamp = noteData.timestamp != null
                  ? DateFormat('HH:mm, dd/MM').format(noteData.timestamp!)
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
    final months = [
      'ינואר', 'פברואר', 'מרץ', 'אפריל', 'מאי', 'יוני',
      'יולי', 'אוגוסט', 'ספטמבר', 'אוקטובר', 'נובמבר', 'דצמבר'
    ];
    return '${date.day} ב${months[date.month - 1]}';
  }
}
