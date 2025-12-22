import 'package:flutter/material.dart';
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/team_member.dart';

/// Dialog for responsible users to manage CC members and their notes
class ResponsibleCcManagementDialog extends StatefulWidget {
  final ChecklistItem item;
  final TeamMember currentUser;
  final List<TeamMember> allTeamMembers;
  final Function(List<String>) onCcMembersChanged;
  final Function(String, String) onCcNoteUpdated;

  const ResponsibleCcManagementDialog({
    super.key,
    required this.item,
    required this.currentUser,
    required this.allTeamMembers,
    required this.onCcMembersChanged,
    required this.onCcNoteUpdated,
  });

  @override
  State<ResponsibleCcManagementDialog> createState() => _ResponsibleCcManagementDialogState();
}

class _ResponsibleCcManagementDialogState extends State<ResponsibleCcManagementDialog> {
  late List<TeamMember> _selectedCcMembers;
  late List<TeamMember> _availableMembers;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedCcMembers = widget.item.ccMembers.toList();
    _updateAvailableMembers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateAvailableMembers() {
    final searchTerm = _searchController.text.toLowerCase();
    _availableMembers = widget.allTeamMembers
        .where((member) =>
            member.id != widget.item.responsibleId &&
            !_selectedCcMembers.any((cc) => cc.id == member.id) &&
            member.name.toLowerCase().contains(searchTerm))
        .toList();
    setState(() {});
  }

  void _addCcMember(TeamMember member) {
    setState(() {
      _selectedCcMembers.add(member);
      _updateAvailableMembers();
    });
    widget.onCcMembersChanged(_selectedCcMembers.map((m) => m.id).toList());
  }

  void _removeCcMember(TeamMember member) {
    setState(() {
      _selectedCcMembers.removeWhere((m) => m.id == member.id);
      _updateAvailableMembers();
    });
    widget.onCcMembersChanged(_selectedCcMembers.map((m) => m.id).toList());
  }

  void _editCcNote(TeamMember member) {
    final currentNote = widget.item.getCcNote(member.id) ?? '';
    showDialog(
      context: context,
      builder: (context) => _CcNoteDialog(
        memberName: member.name,
        initialNote: currentNote,
        onSave: (note) {
          widget.onCcNoteUpdated(member.id, note);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ניהול מיודעים עבור "${widget.item.name}"',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Current CC members
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'מיודעים נוכחיים',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    if (_selectedCcMembers.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text(
                            'אין מיודעים כרגע',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: _selectedCcMembers.length,
                          itemBuilder: (context, index) {
                            final member = _selectedCcMembers[index];
                            final note = widget.item.getCcNote(member.id);
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                title: Text(member.name),
                                subtitle: note != null && note.isNotEmpty
                                    ? Text('הערה: $note', style: const TextStyle(fontSize: 12))
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_note, size: 20),
                                      onPressed: () => _editCcNote(member),
                                      tooltip: 'ערוך הערה',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle, size: 20),
                                      onPressed: () => _removeCcMember(member),
                                      tooltip: 'הסר מהרשימה',
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Add CC members section
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'הוסף מיודעים',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchController,
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                      decoration: const InputDecoration(
                        labelText: 'חיפוש חבר צוות...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _updateAvailableMembers(),
                    ),
                    const SizedBox(height: 12),
                    if (_availableMembers.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text(
                            'כל החברים כבר מיודעים או לא נמצאו תוצאות',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          itemCount: _availableMembers.length,
                          itemBuilder: (context, index) {
                            final member = _availableMembers[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                title: Text(member.name),
                                trailing: IconButton(
                                  icon: const Icon(Icons.add_circle, size: 20),
                                  onPressed: () => _addCcMember(member),
                                  tooltip: 'הוסף לרשימת המיודעים',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),

              // Close button
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('סגור'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simple dialog for editing CC notes
class _CcNoteDialog extends StatefulWidget {
  final String memberName;
  final String initialNote;
  final Function(String) onSave;

  const _CcNoteDialog({
    required this.memberName,
    required this.initialNote,
    required this.onSave,
  });

  @override
  State<_CcNoteDialog> createState() => _CcNoteDialogState();
}

class _CcNoteDialogState extends State<_CcNoteDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialNote;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('הערה עבור ${widget.memberName}'),
        content: TextField(
          controller: _controller,
          decoration: const InputDecoration(
            labelText: 'הערה',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () {
              widget.onSave(_controller.text.trim());
              Navigator.pop(context);
            },
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }
}