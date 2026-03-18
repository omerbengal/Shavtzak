import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/utils/crud_action_result.dart';
import '../../../domain/entities/checklist_item.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_state.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_state.dart';
import '../../../core/utils/rtl_text_field_utils.dart';
import '../loading_overlay.dart';

/// Modal form for creating or editing a checklist item
class ChecklistFormModal extends StatefulWidget {
  final ChecklistItem? item;
  final Future<CrudActionResult> Function(ChecklistItem) onSave;
  final String? currentUserId; // The current admin's ID (for tracking creator)
  final bool
      isResponsibleUser; // If true, limit editing to responsible user capabilities
  final Future<CrudActionResult> Function()?
      onDelete; // Callback for deleting the item

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
  final _ccSearchController = TextEditingController();

  late final FocusNode _nameFocusNode;
  late final FocusNode _ccSearchFocusNode;

  Event? _selectedEvent;
  TeamMember? _selectedResponsible;
  bool _status = false;
  List<TeamMember> _selectedCcMembers = [];
  bool _isSaving = false;
  String _savingMessage = '';

  @override
  void initState() {
    super.initState();
    _nameFocusNode = createRtlCursorFixedFocusNode(_nameController);
    _ccSearchFocusNode = createRtlCursorFixedFocusNode(_ccSearchController);
  }

  void _initializeFromItem(
      ChecklistItem item, List<Event> events, List<TeamMember> teamMembers) {
    _nameController.text = item.name;

    // Safely find the event using try-catch
    try {
      _selectedEvent = events.firstWhere((e) => e.id == item.eventId);
    } catch (e) {
      _selectedEvent = null;
    }

    // Safely find the responsible person using try-catch
    try {
      _selectedResponsible =
          teamMembers.firstWhere((m) => m.id == item.responsibleId);
    } catch (e) {
      _selectedResponsible = null;
    }

    _status = item.status;

    // ccMembers is already a list of TeamMember objects, no need to map from IDs
    _selectedCcMembers = item.ccMembers
        .where((member) => teamMembers.any((m) => m.id == member.id))
        .toList();
  }

  @override
  void dispose() {
    _nameFocusNode.dispose();
    _ccSearchFocusNode.dispose();
    _nameController.dispose();
    _ccSearchController.dispose();
    super.dispose();
  }

  void _showMutationError(String fallbackMessage) {
    final message =
        fallbackMessage.trim().isEmpty ? 'הפעולה נכשלה' : fallbackMessage;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: Text(message),
          ),
          backgroundColor: Colors.red,
        ),
      );
  }

  Widget _buildCenteredDropdownText(String text) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SizedBox(
        width: double.infinity,
        child: Text(
          text,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ),
    );
  }

  Widget _buildCenteredMemberDropdownLabel(TeamMember member) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SizedBox(
        width: double.infinity,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  member.name,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return; // Prevent double-submit

    if (!_formKey.currentState!.validate()) return;
    if (_selectedEvent == null || _selectedResponsible == null) {
      return;
    }

    setState(() {
      _isSaving = true;
      _savingMessage = widget.item == null ? 'יוצר פריט...' : 'שומר פריט...';
    });

    final isNewItem = (widget.item?.id ?? '').isEmpty;

    // Only update createdByAdminId for new items
    final createdByAdminId =
        isNewItem ? widget.currentUserId : widget.item?.createdByAdminId;

    final checklistItem = ChecklistItem(
      id: isNewItem ? '' : widget.item!.id,
      eventId: _selectedEvent!.id,
      name: _nameController.text.trim(),
      responsibleId: _selectedResponsible!.id,
      notes: isNewItem ? const [] : widget.item!.notes,
      ccIds: _selectedCcMembers.map((m) => m.id).toList(),
      status: _status,
      createdAt: isNewItem ? DateTime.now() : widget.item!.createdAt,
      updatedAt: DateTime.now(),
      statusLastUpdatedAt:
          isNewItem ? DateTime.now() : widget.item!.statusLastUpdatedAt,
      createdByAdminId: createdByAdminId,
    );

    final result = await widget.onSave(checklistItem);
    if (!mounted) {
      return;
    }

    if (result.isFailure) {
      setState(() {
        _isSaving = false;
        _savingMessage = '';
      });
      _showMutationError(result.message ?? 'שגיאה בשמירת פריט הצ\'קליסט');
      return;
    }

    Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (widget.onDelete == null || _isSaving) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת פריט מהצ\'קליסט'),
          content: Text(
            'האם אתה בטוח שברצונך למחוק את "${widget.item?.name ?? ''}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ביטול'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isSaving = true;
      _savingMessage = 'מוחק פריט...';
    });

    final result = await widget.onDelete!();
    if (!mounted) {
      return;
    }

    if (result.isFailure) {
      setState(() {
        _isSaving = false;
        _savingMessage = '';
      });
      _showMutationError(result.message ?? 'שגיאה במחיקת פריט הצ\'קליסט');
      return;
    }

    Navigator.pop(context);
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
                              : (widget.item == null
                                  ? 'הוסף פריט לצ\'קליסט'
                                  : 'ערוך פריט בצ\'קליסט'),
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Delete button (only when editing an existing item)
                            if (widget.item != null && widget.onDelete != null)
                              IconButton(
                                onPressed: _delete,
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
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
                              final eventsLoading =
                                  eventState is EventLoading ||
                                      eventState is EventInitial;
                              final teamLoading = teamState is TeamLoading ||
                                  teamState is TeamInitial;

                              if (eventsLoading || teamLoading) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              // Get the data
                              final events = eventState is EventsLoaded
                                  ? eventState.events
                                  : <Event>[];
                              final teamMembers = teamState is TeamLoaded
                                  ? teamState.members
                                  : <TeamMember>[];

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
                              if (widget.item != null &&
                                  _nameController.text.isEmpty) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  _initializeFromItem(widget.item!,
                                      deduplicatedEvents, teamMembers);
                                  setState(() {});
                                });
                              }

                              return _buildForm(scrollController,
                                  deduplicatedEvents, teamMembers);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            LoadingOverlay(
              isLoading: _isSaving,
              message: _savingMessage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(ScrollController scrollController, List<Event> events,
      List<TeamMember> teamMembers) {
    final selectableEvents = events.where((event) {
      // Show event if it's in the future OR if it's the currently selected event
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final eventEndDate =
          DateTime(event.endDate.year, event.endDate.month, event.endDate.day);
      return eventEndDate.isAtSameMomentAs(today) ||
          eventEndDate.isAfter(today) ||
          (_selectedEvent != null && event.id == _selectedEvent!.id);
    }).toList();

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
                  focusNode: _nameFocusNode,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    labelText: 'שם הפריט *',
                    border: const OutlineInputBorder(),
                    filled: widget.isResponsibleUser,
                    fillColor:
                        widget.isResponsibleUser ? Colors.grey[200] : null,
                  ),
                  enabled: !widget.isResponsibleUser,
                  validator: widget.isResponsibleUser
                      ? null
                      : (value) {
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
                        alignment: AlignmentDirectional.center,
                        decoration: const InputDecoration(
                          labelText: 'אירוע *',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                        selectedItemBuilder: (context) {
                          return selectableEvents
                              .map(
                                (event) => _buildCenteredDropdownText(
                                  '${event.name} (${event.startDate.day}/${event.startDate.month})',
                                ),
                              )
                              .toList();
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'אנא בחר אירוע';
                          }
                          return null;
                        },
                        items: selectableEvents
                            .map((event) => DropdownMenuItem<Event>(
                                  value: event,
                                  child: _buildCenteredDropdownText(
                                    '${event.name} (${event.startDate.day}/${event.startDate.month})',
                                  ),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedEvent = value),
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
                        alignment: AlignmentDirectional.center,
                        decoration: const InputDecoration(
                          labelText: 'אחראי *',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                        selectedItemBuilder: (context) {
                          return teamMembers
                              .map(_buildCenteredMemberDropdownLabel)
                              .toList();
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'אנא בחר אחראי';
                          }
                          return null;
                        },
                        items: teamMembers
                            .map((member) => DropdownMenuItem<TeamMember>(
                                  value: member,
                                  child:
                                      _buildCenteredMemberDropdownLabel(member),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedResponsible = value;
                          });
                        },
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
                  focusNode: _ccSearchFocusNode,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    labelText: 'חיפוש חבר צוות...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),

                // CC member chips
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: teamMembers.where((member) {
                    // Don't show the responsible person in CC list
                    if (member.id == _selectedResponsible?.id) return false;

                    // If there's search text, filter by it
                    if (_ccSearchController.text.isNotEmpty) {
                      return member.name
                          .toLowerCase()
                          .contains(_ccSearchController.text.toLowerCase());
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
