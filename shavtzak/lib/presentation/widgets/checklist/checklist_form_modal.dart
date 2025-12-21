import 'package:flutter/material.dart';
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/team_member.dart';

/// Modal form for creating or editing a checklist item
class ChecklistFormModal extends StatefulWidget {
  final ChecklistItem? item;
  final List<Event> events;
  final List<TeamMember> teamMembers;
  final Function(ChecklistItem) onSave;
  final String? currentUserId; // The current admin's ID (for tracking creator)

  const ChecklistFormModal({
    super.key,
    this.item,
    required this.events,
    required this.teamMembers,
    required this.onSave,
    this.currentUserId,
  });

  @override
  State<ChecklistFormModal> createState() => _ChecklistFormModalState();
}

class _ChecklistFormModalState extends State<ChecklistFormModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _responsibleNoteController = TextEditingController();
  final _adminNoteController = TextEditingController();

  Event? _selectedEvent;
  TeamMember? _selectedResponsible;
  bool _status = false;
  List<TeamMember> _selectedCcMembers = [];

  @override
  void initState() {
    super.initState();
    if (widget.item != null) {
      _initializeFromItem(widget.item!);
    }
  }

  void _initializeFromItem(ChecklistItem item) {
    _nameController.text = item.name;
    _responsibleNoteController.text = item.responsibleNote;
    _adminNoteController.text = item.adminNote;

    // Safely find the event with fallback
    _selectedEvent = widget.events.cast<Event?>().firstWhere(
      (e) => e?.id == item.eventId,
      orElse: () => null,
    );

    // Safely find the responsible person with fallback
    _selectedResponsible = widget.teamMembers.cast<TeamMember?>().firstWhere(
      (m) => m?.id == item.responsibleId,
      orElse: () => null,
    );

    _status = item.status;

    // ccMembers is already a list of TeamMember objects, no need to map from IDs
    _selectedCcMembers = item.ccMembers.where((member) =>
        widget.teamMembers.any((m) => m.id == member.id)
    ).toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _responsibleNoteController.dispose();
    _adminNoteController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedEvent == null || _selectedResponsible == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('אנא בחר אירוע ואחראי')),
      );
      return;
    }

    final checklistItem = ChecklistItem(
      id: widget.item?.id ?? '',
      eventId: _selectedEvent!.id,
      name: _nameController.text.trim(),
      responsibleId: _selectedResponsible!.id,
      responsibleNote: _responsibleNoteController.text.trim(),
      adminNote: _adminNoteController.text.trim(),
      ccIds: _selectedCcMembers.map((m) => m.id).toList(),
      ccNotes: widget.item?.ccNotes ?? {},
      status: _status,
      createdAt: widget.item?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      statusLastUpdatedAt: widget.item?.statusLastUpdatedAt ?? DateTime.now(),
      // Set createdByAdminId only when creating a new item
      createdByAdminId: widget.item?.createdByAdminId ?? widget.currentUserId,
    );

    widget.onSave(checklistItem);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.item == null ? 'הוסף פריט לצ\'קליסט' : 'ערוך פריט בצ\'קליסט',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      // Name field
                      TextFormField(
                        controller: _nameController,
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                        decoration: const InputDecoration(
                          labelText: 'שם הפריט *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'אנא הזן שם לפריט';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Event dropdown
                      DropdownButtonFormField<Event>(
                        value: _selectedEvent,
                        decoration: const InputDecoration(
                          labelText: 'אירוע *',
                          border: OutlineInputBorder(),
                        ),
                        items: widget.events.map((event) {
                          return DropdownMenuItem(
                            value: event,
                            child: Text(
                              '${event.name} (${event.startDate.day}/${event.startDate.month})',
                              style: const TextStyle(fontSize: 14),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) => setState(() => _selectedEvent = value),
                      ),
                      const SizedBox(height: 16),

                      // Responsible dropdown
                      DropdownButtonFormField<TeamMember>(
                        value: _selectedResponsible,
                        decoration: const InputDecoration(
                          labelText: 'אחראי *',
                          border: OutlineInputBorder(),
                        ),
                        items: widget.teamMembers.map((member) => DropdownMenuItem(
                          value: member,
                          child: Text(member.name),
                        )).toList(),
                        onChanged: (value) => setState(() => _selectedResponsible = value),
                      ),
                      const SizedBox(height: 16),

                      // Responsible note
                      TextFormField(
                        controller: _responsibleNoteController,
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                        decoration: const InputDecoration(
                          labelText: 'פירוט אחראי',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),

                      // Admin note
                      TextFormField(
                        controller: _adminNoteController,
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                        decoration: const InputDecoration(
                          labelText: 'הערת מנהל',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),

                      // CC members
                      const Text(
                        'מיודעים',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: widget.teamMembers.where((member) => member.id != _selectedResponsible?.id).map((member) {
                          final isSelected = _selectedCcMembers.contains(member);
                          return FilterChip(
                            label: Text(member.name),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedCcMembers.add(member);
                                } else {
                                  _selectedCcMembers.remove(member);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Status toggle
                      SwitchListTile(
                        title: const Text('סטטוס'),
                        subtitle: Text(_status ? 'קיים' : 'לא קיים'),
                        value: _status,
                        onChanged: (value) => setState(() => _status = value),
                        activeColor: Colors.green,
                        inactiveThumbColor: Colors.red,
                        inactiveTrackColor: Colors.red.withOpacity(0.5),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),

                // Save button
                ElevatedButton(
                  onPressed: _save,
                  child: Text(widget.item == null ? 'צור פריט' : 'שמור שינויים'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}