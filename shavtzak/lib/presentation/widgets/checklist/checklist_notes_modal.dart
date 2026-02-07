import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/team_member.dart';
import 'chat_bubble.dart';
import '../../../core/utils/rtl_text_field_utils.dart';

/// Modal dialog showing the full notes conversation for a checklist item
class ChecklistNotesModal extends StatefulWidget {
  final ChecklistItem item;
  final String? currentUserId;
  final List<TeamMember> allTeamMembers;
  final void Function(String content)? onAddNote;

  const ChecklistNotesModal({
    super.key,
    required this.item,
    this.currentUserId,
    required this.allTeamMembers,
    this.onAddNote,
  });

  @override
  State<ChecklistNotesModal> createState() => _ChecklistNotesModalState();
}

class _ChecklistNotesModalState extends State<ChecklistNotesModal> {
  final _noteController = TextEditingController();
  final _scrollController = ScrollController();
  late final FocusNode _noteFocusNode;

  @override
  void initState() {
    super.initState();
    _noteFocusNode = createRtlCursorFixedFocusNode(_noteController);
    // Auto-scroll to bottom after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
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

    // Scroll to bottom after adding note
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  String _getMemberName(String memberId) {
    final member = widget.allTeamMembers.where((m) => m.id == memberId).firstOrNull;
    return member?.name ?? 'לא ידוע';
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.item.notes;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, sheetScrollController) => Material(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
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
                              'הערות - ${widget.item.name}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.item.event != null)
                              Text(
                                widget.item.event!.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
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
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount: notes.length,
                          itemBuilder: (context, index) {
                            final note = notes[index];
                            final isOwn = note.createdByTeamMemberId == widget.currentUserId;
                            final authorName = note.createdByTeamMemberName ??
                                _getMemberName(note.createdByTeamMemberId);

                            final displayName = isOwn ? 'אני' : authorName;

                            final timestamp = DateFormat('HH:mm, dd/MM').format(note.createdAt);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: ChatBubble(
                                authorName: displayName,
                                message: note.content,
                                bubbleColor: isOwn
                                    ? Colors.blue.withValues(alpha: 0.15)
                                    : Colors.grey.withValues(alpha: 0.2),
                                isOwnMessage: isOwn,
                                alignRight: isOwn,
                                timestamp: timestamp,
                                showAuthorLabel: true,
                              ),
                            );
                          },
                        ),
                ),

                // Input field at bottom
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
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
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
                            icon: const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 20,
                            ),
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
        ),
      ),
    );
  }
}
