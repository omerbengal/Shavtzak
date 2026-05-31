import 'package:flutter/material.dart';
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/utils/rtl_text_field_utils.dart';
import '../../../core/debug/logger.dart';

/// Dialog for responsible users to manage CC members
class ResponsibleCcManagementDialog extends StatefulWidget {
  final ChecklistItem item;
  final TeamMember currentUser;
  final List<TeamMember> allTeamMembers;
  final Function(List<String>) onCcMembersChanged;

  const ResponsibleCcManagementDialog({
    super.key,
    required this.item,
    required this.currentUser,
    required this.allTeamMembers,
    required this.onCcMembersChanged,
  });

  @override
  State<ResponsibleCcManagementDialog> createState() => _ResponsibleCcManagementDialogState();
}

class _ResponsibleCcManagementDialogState extends State<ResponsibleCcManagementDialog> {
  late List<TeamMember> _selectedCcMembers;
  late List<TeamMember> _availableMembers;
  final _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = createRtlCursorFixedFocusNode(_searchController);
    _selectedCcMembers = widget.item.ccMembers.toList();
    _updateAvailableMembers();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
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
                    onPressed: () { Logger.action('tap:close:ccManagementDialog'); Navigator.pop(context); },
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
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                title: Text(member.name),
                                trailing: IconButton(
                                  icon: const Icon(Icons.remove_circle, size: 20),
                                  onPressed: () { Logger.action('tap:removeCcMember', {'memberId': member.id}); _removeCcMember(member); },
                                  tooltip: 'הסר מהרשימה',
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
                      focusNode: _searchFocusNode,
                      textAlign: TextAlign.right,
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
                                  onPressed: () { Logger.action('tap:addCcMember', {'memberId': member.id}); _addCcMember(member); },
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
                onPressed: () { Logger.action('tap:close:ccManagementDialog'); Navigator.pop(context); },
                child: const Text('סגור'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
