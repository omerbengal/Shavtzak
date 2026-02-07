import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/team_member.dart';
import '../map_location_picker.dart';
import '../../bloc/checklist/checklist_bloc.dart';
import 'chat_bubble.dart';
import '../../../core/utils/rtl_text_field_utils.dart';

/// Card widget for displaying a checklist item (admin view)
class ChecklistItemCard extends StatelessWidget {
  final ChecklistItem item;
  final bool isAdmin;
  final String? currentUserId;
  final List<TeamMember> allTeamMembers;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onStatusChanged;
  final void Function(String content)? onAddNote;

  const ChecklistItemCard({
    super.key,
    required this.item,
    required this.allTeamMembers,
    this.isAdmin = false,
    this.currentUserId,
    this.onTap,
    this.onStatusChanged,
    this.onAddNote,
  });

  Color _getBackgroundColor() {
    return item.status
        ? Colors.lightGreen.withValues(alpha: 0.3)
        : Colors.red.withValues(alpha: 0.3);
  }

  String _getLatestNoteSnippet() {
    final content = item.latestNoteContent;
    if (content == null) return '';
    if (content.length <= 50) return content;
    return '${content.substring(0, 50)}...';
  }

  String _getMemberName(String memberId) {
    final member = allTeamMembers.where((m) => m.id == memberId).firstOrNull;
    return member?.name ?? 'לא ידוע';
  }

  @override
  Widget build(BuildContext context) {
    final canUpdateStatus = isAdmin;
    final latestNote = item.notes.isNotEmpty ? item.notes.last : null;
    final noteSnippet = _getLatestNoteSnippet();

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
            // Event info
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
            // Notes section - always show button to access conversation
            const SizedBox(height: 6),
            InkWell(
                onTap: () => _showNotesModal(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (latestNote != null) ...[
                              () {
                                final snippetAuthor = latestNote.createdByTeamMemberName ?? _getMemberName(latestNote.createdByTeamMemberId);
                                final snippetName = latestNote.createdByTeamMemberId == currentUserId ? 'אני' : snippetAuthor;
                                final snippetDisplay = latestNote.authorRole != null
                                    ? '$snippetName (${latestNote.authorRole})'
                                    : snippetName;
                                return Text(
                                  snippetDisplay,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                );
                              }(),
                            ],
                            Text(
                              noteSnippet.isNotEmpty ? noteSnippet : 'הערות (${item.notes.length})',
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${item.notes.length}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                      Icon(Icons.chevron_left, size: 16, color: Colors.grey[400]),
                    ],
                  ),
                ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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

  void _showNotesModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalContext) {
        return _NotesModalWrapper(
          item: item,
          currentUserId: currentUserId,
          allTeamMembers: allTeamMembers,
          onAddNote: onAddNote,
          parentContext: context,
        );
      },
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

/// Wrapper for the notes modal
class _NotesModalWrapper extends StatefulWidget {
  final ChecklistItem item;
  final String? currentUserId;
  final List<TeamMember> allTeamMembers;
  final void Function(String content)? onAddNote;
  final BuildContext parentContext;

  const _NotesModalWrapper({
    required this.item,
    this.currentUserId,
    required this.allTeamMembers,
    this.onAddNote,
    required this.parentContext,
  });

  @override
  State<_NotesModalWrapper> createState() => _NotesModalWrapperState();
}

class _NotesModalWrapperState extends State<_NotesModalWrapper> {
  final _noteController = TextEditingController();
  final _scrollController = ScrollController();
  late final FocusNode _noteFocusNode;
  late ChecklistItem _item;
  StreamSubscription<ChecklistItem>? _subscription;

  @override
  void initState() {
    super.initState();
    _noteFocusNode = createRtlCursorFixedFocusNode(_noteController);
    _item = widget.item;
    // Subscribe to live updates
    final checklistRepository = widget.parentContext.read<ChecklistBloc>().repository;
    _subscription = checklistRepository.watchChecklistItem(widget.item.id).listen(
      (updatedItem) {
        if (mounted) {
          final hadNewNotes = updatedItem.notes.length > _item.notes.length;
          setState(() { _item = updatedItem; });
          if (hadNewNotes) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
          }
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _noteFocusNode.dispose();
    _noteController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _submitNote() {
    final content = _noteController.text.trim();
    if (content.isEmpty) return;
    widget.onAddNote?.call(content);
    _noteController.clear();
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  String _getMemberName(String memberId) {
    final member = widget.allTeamMembers.where((m) => m.id == memberId).firstOrNull;
    return member?.name ?? 'לא ידוע';
  }

  @override
  Widget build(BuildContext context) {
    final notes = _item.notes;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'הערות - ${_item.name} (${notes.length})',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_item.event != null)
                          Text(
                            _item.event!.name,
                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Notes list
            Expanded(
              child: notes.isEmpty
                  ? const Center(
                      child: Text(
                        'אין הערות עדיין',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      itemCount: notes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        final isOwn = note.createdByTeamMemberId == widget.currentUserId;
                        final authorName =
                            note.createdByTeamMemberName ??
                            _getMemberName(note.createdByTeamMemberId);
                        final baseName = isOwn ? 'אני' : authorName;
                        final displayName = note.authorRole != null
                            ? '$baseName (${note.authorRole})'
                            : baseName;
                        final timestamp = DateFormat('HH:mm, dd/MM').format(note.createdAt);

                        return ChatBubble(
                          authorName: displayName,
                          message: note.content,
                          bubbleColor: isOwn
                              ? Colors.blue.withValues(alpha: 0.15)
                              : Colors.grey.withValues(alpha: 0.2),
                          isOwnMessage: isOwn,
                          alignRight: isOwn,
                          timestamp: timestamp,
                          showAuthorLabel: true,
                        );
                      },
                    ),
            ),

            // Input field
            if (widget.onAddNote != null) ...[
              const Divider(height: 1),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _noteController,
                        focusNode: _noteFocusNode,
                        textAlign: TextAlign.right,
                        decoration: InputDecoration(
                          hintText: 'כתוב הערה...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          isDense: true,
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submitNote(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: _submitNote,
                        icon: const Icon(Icons.send, color: Colors.white, size: 20),
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
