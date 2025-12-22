import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/team/team_state.dart';

/// Modal form for creating or editing a checklist item
class ChecklistFormModal extends StatefulWidget {
  final ChecklistItem? item;
  final Function(ChecklistItem) onSave;
  final String? currentUserId; // The current admin's ID (for tracking creator)
  final bool isResponsibleUser; // If true, limit editing to responsible user capabilities
  final VoidCallback? onDelete; // Callback for deleting the item

  const ChecklistFormModal({
    super.key,
    this.item,
    required this.onSave,
    this.currentUserId,
    this.isResponsibleUser = false,
    this.onDelete,
  });

  @override
  State<ChecklistFormModal> createState() => _ChecklistFormModalState();
}

class _ChecklistFormModalState extends State<ChecklistFormModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _adminNoteController = TextEditingController();
  final _responsibleNoteController = TextEditingController();
  final _ccSearchController = TextEditingController();

  Event? _selectedEvent;
  TeamMember? _selectedResponsible;
  bool _status = false;
  List<TeamMember> _selectedCcMembers = [];

  @override
  void initState() {
    super.initState();
    // Data loading is handled by parent screens
  }

  void _initializeFromItem(ChecklistItem item, List<Event> events, List<TeamMember> teamMembers) {
    _nameController.text = item.name;
    _adminNoteController.text = item.adminNote;
    _responsibleNoteController.text = item.responsibleNote;

    // Safely find the event using try-catch
    try {
      _selectedEvent = events.firstWhere((e) => e.id == item.eventId);
    } catch (e) {
      _selectedEvent = null;
    }

    // Safely find the responsible person using try-catch
    try {
      _selectedResponsible = teamMembers.firstWhere((m) => m.id == item.responsibleId);
    } catch (e) {
      _selectedResponsible = null;
    }

    _status = item.status;

    // ccMembers is already a list of TeamMember objects, no need to map from IDs
    _selectedCcMembers = item.ccMembers.where((member) =>
        teamMembers.any((m) => m.id == member.id)
    ).toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _adminNoteController.dispose();
    _responsibleNoteController.dispose();
    _ccSearchController.dispose();
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

  void _delete() {
    if (widget.onDelete != null) {
      widget.onDelete!();
    }
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
        builder: (context, scrollController) => Material(
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.isResponsibleUser
                          ? 'צפייה וניהול פריט'
                          : (widget.item == null ? 'הוסף פריט לצ\'קליסט' : 'ערוך פריט בצ\'קליסט'),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Content with loading state
                Expanded(
                  child: BlocBuilder<EventBloc, EventState>(
                    builder: (context, eventState) {
                      return BlocBuilder<TeamBloc, TeamState>(
                        builder: (context, teamState) {
                          // Show loading if either is loading or not loaded
                          final eventsLoading = eventState is EventLoading || eventState is EventInitial;
                          final teamLoading = teamState is TeamLoading || teamState is TeamInitial;

                          if (eventsLoading || teamLoading) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          // Get the data
                          final events = eventState is EventsLoaded ? eventState.events : <Event>[];
                          final teamMembers = teamState is TeamLoaded ? teamState.members : <TeamMember>[];

                          // Initialize from item if not already done
                          if (widget.item != null && _nameController.text.isEmpty) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _initializeFromItem(widget.item!, events, teamMembers);
                              setState(() {});
                            });
                          }

                          return _buildForm(scrollController, events, teamMembers);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(ScrollController scrollController, List<Event> events, List<TeamMember> teamMembers) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              children: [
                      // Name field
                      TextFormField(
                        controller: _nameController,
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                        decoration: InputDecoration(
                          labelText: 'שם הפריט *',
                          border: const OutlineInputBorder(),
                          filled: widget.isResponsibleUser,
                          fillColor: widget.isResponsibleUser ? Colors.grey[200] : null,
                        ),
                        enabled: !widget.isResponsibleUser,
                        validator: widget.isResponsibleUser ? null : (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'אנא הזן שם לפריט';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Event dropdown
                      widget.isResponsibleUser
                          ? InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'אירוע *',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Color.fromARGB(255, 240, 240, 240),
                              ),
                              child: Text(
                                _selectedEvent?.name ?? 'אירוע לא ידוע',
                                style: const TextStyle(fontSize: 14),
                              ),
                            )
                          : DropdownButtonFormField<Event>(
                              value: _selectedEvent,
                              decoration: const InputDecoration(
                                labelText: 'אירוע *',
                                border: OutlineInputBorder(),
                              ),
                              items: events.map((event) {
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
                      widget.isResponsibleUser
                          ? InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'אחראי *',
                                border: OutlineInputBorder(),
                                filled: true,
                                fillColor: Color.fromARGB(255, 240, 240, 240),
                              ),
                              child: Text(
                                _selectedResponsible?.name ?? 'לא ידוע',
                                style: const TextStyle(fontSize: 14),
                              ),
                            )
                          : DropdownButtonFormField<TeamMember>(
                              value: _selectedResponsible,
                              decoration: const InputDecoration(
                                labelText: 'אחראי *',
                                border: OutlineInputBorder(),
                              ),
                              items: teamMembers.map((member) => DropdownMenuItem(
                                value: member,
                                child: Text(member.name),
                              )).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedResponsible = value;
                                });
                              },
                            ),
                      const SizedBox(height: 16),

                      // Show responsible note for responsible users, admin note for admins
                      if (widget.isResponsibleUser)
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
                        )
                      else
                        TextFormField(
                          controller: _adminNoteController,
                          textAlign: TextAlign.right,
                          textDirection: TextDirection.rtl,
                          decoration: const InputDecoration(
                            labelText: 'הערות מנהל',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          maxLines: 3,
                        ),
                      const SizedBox(height: 16),

                      // CC members with search
                      const Text(
                        'מיודעים',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),

                      // Search bar for CCs
                      TextField(
                        controller: _ccSearchController,
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                        decoration: const InputDecoration(
                          labelText: 'חיפוש חבר צוות...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),

                      // CC member chips
                      // Show all available team members, but filter based on search if there's text
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: teamMembers.where((member) {
                          // Don't show the responsible person in CC list
                          if (member.id == _selectedResponsible?.id) return false;

                          // If there's search text, filter by it
                          if (_ccSearchController.text.isNotEmpty) {
                            return member.name.toLowerCase().contains(_ccSearchController.text.toLowerCase());
                          }

                          // Otherwise, show all
                          return true;
                        }).map((member) {
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

          // Action buttons
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Save button
              ElevatedButton(
                onPressed: _save,
                child: Text(widget.item == null ? 'צור פריט' : 'שמור שינויים'),
              ),
              // Delete button (only when editing an existing item and delete callback is provided)
              if (widget.item != null && widget.onDelete != null) ...[
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _delete,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('מחק פריט'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}