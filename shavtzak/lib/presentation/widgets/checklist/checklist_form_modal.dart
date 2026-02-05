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
import '../loading_overlay.dart';

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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Data loading is handled by parent screens
  }

  void _initializeFromItem(ChecklistItem item, List<Event> events, List<TeamMember> teamMembers) {
    _nameController.text = item.name;

    // Load the current admin's note from the adminNotes map
    final currentAdminNote = widget.currentUserId != null
        ? item.adminNotes[widget.currentUserId]
        : null;
    _adminNoteController.text = currentAdminNote?.note ?? '';

    _responsibleNoteController.text = item.responsibleNote.note;

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
    if (_isSaving) return; // Prevent double-submit

    if (!_formKey.currentState!.validate()) return;
    if (_selectedEvent == null || _selectedResponsible == null) {
      // Validation will be handled by the dropdown validators
      return;
    }

    setState(() => _isSaving = true);

    // For new items, createdByAdminId should be the current admin
    // For existing items, preserve the original creator
    final isNewItem = (widget.item?.id ?? '').isEmpty;
    final createdByAdminId = isNewItem
        ? widget.currentUserId
        : widget.item?.createdByAdminId;

    // Start with base item (new or existing)
    final baseItem = isNewItem
        ? ChecklistItem(
            id: '',
            eventId: _selectedEvent!.id,
            name: _nameController.text.trim(),
            responsibleId: _selectedResponsible!.id,
            responsibleNote: const ResponsibleNoteEntry(note: ''),
            adminNotes: {},
            ccIds: _selectedCcMembers.map((m) => m.id).toList(),
            ccNotes: {},
            status: _status,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            statusLastUpdatedAt: DateTime.now(),
            createdByAdminId: widget.currentUserId,
          )
        : widget.item!;

    // Update admin note (for current admin)
    final adminNoteText = _adminNoteController.text.trim();
    final itemWithAdminNote = widget.currentUserId != null
        ? baseItem.withUpdatedAdminNote(widget.currentUserId!, adminNoteText)
        : baseItem;

    // Update responsible note (only for responsible users)
    final responsibleNoteText = _responsibleNoteController.text.trim();
    final itemWithResponsibleNote = itemWithAdminNote.copyWith(
      responsibleNote: ResponsibleNoteEntry(
        note: responsibleNoteText,
        updatedAt: (baseItem.responsibleNote.note == responsibleNoteText)
            ? baseItem.responsibleNote.updatedAt
            : DateTime.now(),
      ),
    );

    // Update other fields
    var checklistItem = itemWithResponsibleNote.copyWith(
      eventId: _selectedEvent!.id,
      name: _nameController.text.trim(),
      responsibleId: _selectedResponsible!.id,
      ccIds: _selectedCcMembers.map((m) => m.id).toList(),
      status: _status,
      updatedAt: DateTime.now(),
    );

    // Only update createdByAdminId for new items
    if (isNewItem && widget.currentUserId != null) {
      checklistItem = checklistItem.copyWith(createdByAdminId: widget.currentUserId);
    }

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
        builder: (context, scrollController) => Stack(
          children: [
            Material(
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Delete button (only when editing an existing item)
                        if (widget.item != null && widget.onDelete != null)
                          IconButton(
                            onPressed: _delete,
                            icon: const Icon(Icons.delete, color: Colors.red),
                            tooltip: 'מחק פריט',
                          ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
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

                          // Deduplicate events by ID to prevent DropdownButton errors
                          final seenEventIds = <String>{};
                          final deduplicatedEvents = events.where((event) {
                            if (seenEventIds.contains(event.id)) {
                              return false; // Skip duplicate
                            }
                            seenEventIds.add(event.id);
                            return true;
                          }).toList();

                          // Initialize from item if not already done
                          if (widget.item != null && _nameController.text.isEmpty) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _initializeFromItem(widget.item!, deduplicatedEvents, teamMembers);
                              setState(() {});
                            });
                          }

                          return _buildForm(scrollController, deduplicatedEvents, teamMembers);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
            ),
            LoadingOverlay(isLoading: _isSaving, message: widget.item == null ? 'יוצר פריט...' : 'שומר פריט...'),
          ],
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
                              validator: (value) {
                                if (value == null) {
                                  return 'אנא בחר אירוע';
                                }
                                return null;
                              },
                              items: events.where((event) {
                                // Show event if it's in the future OR if it's the currently selected event
                                final now = DateTime.now();
                                final today = DateTime(now.year, now.month, now.day);
                                final eventEndDate = DateTime(event.endDate.year, event.endDate.month, event.endDate.day);
                                return eventEndDate.isAtSameMomentAs(today) || eventEndDate.isAfter(today) || (_selectedEvent != null && event.id == _selectedEvent!.id);
                              }).map((event) {
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
                              selectedItemBuilder: (context) {
                                return teamMembers.map((member) => DropdownMenuItem<TeamMember>(
                                  value: member,
                                  child: Text(member.name),
                                )).toList();
                              },
                              validator: (value) {
                                if (value == null) {
                                  return 'אנא בחר אחראי';
                                }
                                return null;
                              },
                              items: teamMembers.map((member) => DropdownMenuItem(
                                value: member,
                                child: Row(
                                  children: [
                                    Text(member.name),
                                    if (member.isPermanent) ...[
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.verified_user,
                                        size: 14,
                                        color: Colors.blue.shade700,
                                      ),
                                    ],
                                  ],
                                ),
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
                            labelText: 'הערה',
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
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(member.name),
                                if (member.isPermanent) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.verified_user,
                                    size: 12,
                                    color: Colors.blue.shade700,
                                  ),
                                ],
                              ],
                            ),
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
            onPressed: _isSaving ? null : _save,
            child: Text(widget.item == null ? 'צור פריט' : 'שמור שינויים'),
          ),
        ],
      ),
    );
  }
}