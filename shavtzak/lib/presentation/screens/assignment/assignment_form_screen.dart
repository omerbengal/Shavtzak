import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/role_types.dart';
import '../../../domain/entities/assignment.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/team_member.dart';
import '../../bloc/assignment/assignment_bloc.dart';
import '../../bloc/assignment/assignment_event.dart';
import '../../bloc/assignment/assignment_state.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/team/team_state.dart';

class AssignmentFormScreen extends StatefulWidget {
  final Assignment? assignment;
  final Event? event; // Pre-selected event

  const AssignmentFormScreen({
    super.key,
    this.assignment,
    this.event,
  });

  @override
  State<AssignmentFormScreen> createState() => _AssignmentFormScreenState();
}

class _AssignmentFormScreenState extends State<AssignmentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();

  Event? _selectedEvent;
  TeamMember? _selectedTeamMember;
  RoleType? _selectedRole;
  AssignmentStatus _status = AssignmentStatus.pending;
  String? _eventError;
  String? _memberError;
  String? _roleError;

  bool get _isEditMode => widget.assignment != null;

  @override
  void initState() {
    super.initState();

    // Load data
    context.read<EventBloc>().add(const LoadEvents());
    context.read<TeamBloc>().add(const LoadTeamMembers());

    // Initialize form values
    if (_isEditMode) {
      final assignment = widget.assignment!;
      _selectedEvent = assignment.event;
      _selectedTeamMember = assignment.teamMember;
      _selectedRole = assignment.roleType;
      _status = assignment.status;
      _notesController.text = assignment.notes;
    } else if (widget.event != null) {
      _selectedEvent = widget.event;
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _saveAssignment() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _eventError = _selectedEvent == null ? 'יש לבחור אירוע' : null;
      _memberError = _selectedTeamMember == null ? 'יש לבחור חבר צוות' : null;
      _roleError = _selectedRole == null ? 'יש לבחור תפקיד' : null;
    });

    if (_selectedEvent == null || _selectedTeamMember == null || _selectedRole == null) {
      return;
    }

    final now = DateTime.now();

    // Determine slotIndex: preserve if editing, otherwise find next available slot
    final slotIndex = _isEditMode
        ? widget.assignment!.slotIndex
        : _getNextAvailableSlotIndex(_selectedEvent!.id, _selectedRole!);

    final assignment = Assignment(
      id: _isEditMode ? widget.assignment!.id : const Uuid().v4(),
      eventId: _selectedEvent!.id,
      teamMemberId: _selectedTeamMember!.id,
      roleType: _selectedRole!,
      slotIndex: slotIndex,
      status: _status,
      notes: _notesController.text.trim(),
      createdAt: _isEditMode ? widget.assignment!.createdAt : now,
      updatedAt: now,
      event: _selectedEvent,
      teamMember: _selectedTeamMember,
    );

    if (_isEditMode) {
      context.read<AssignmentBloc>().add(UpdateAssignment(assignment));
    } else {
      context.read<AssignmentBloc>().add(CreateAssignment(assignment));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AssignmentBloc, AssignmentState>(
      listener: (context, state) {
        if (state is AssignmentOperationSuccess) {
          Navigator.pop(context);
        }
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: Text(_isEditMode ? 'עריכת שיבוץ' : 'הוספת שיבוץ'),
            actions: [
              TextButton(
                onPressed: _saveAssignment,
                child: const Text(AppStrings.save, style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          body: BlocBuilder<AssignmentBloc, AssignmentState>(
            builder: (context, state) {
              if (state is AssignmentOperating) {
                return const Center(child: CircularProgressIndicator());
              }
              return Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Event selector
                    const Text(
                      'אירוע',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    BlocBuilder<EventBloc, EventState>(
                      builder: (context, eventState) {
                        if (eventState is EventsLoaded) {
                          return DropdownButtonFormField<Event>(
                            value: _selectedEvent,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'בחר אירוע',
                              prefixIcon: Icon(Icons.event),
                            ),
                            items: eventState.events
                                .where((e) => e.isActive)
                                .map((event) {
                              return DropdownMenuItem(
                                value: event,
                                child: Text(event.name),
                              );
                            }).toList(),
                            onChanged: (event) {
                              setState(() {
                                _selectedEvent = event;
                                _eventError = null;
                              });
                            },
                            validator: (v) => v == null ? 'יש לבחור אירוע' : null,
                          );
                        }
                        return const CircularProgressIndicator();
                      },
                    ),
                    const SizedBox(height: 16),

                    // Team member selector
                    const Text(
                      'חבר צוות',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    BlocBuilder<TeamBloc, TeamState>(
                      builder: (context, teamState) {
                        if (teamState is TeamLoaded) {
                          return DropdownButtonFormField<TeamMember>(
                            value: _selectedTeamMember,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'בחר חבר צוות',
                              prefixIcon: Icon(Icons.person),
                            ),
                            items: teamState.members
                                .where((m) => m.isActive)
                                .map((member) {
                              return DropdownMenuItem(
                                value: member,
                                child: Text(member.name),
                              );
                            }).toList(),
                            onChanged: (member) {
                              setState(() {
                                _selectedTeamMember = member;
                                _memberError = null;
                              });
                            },
                            validator: (v) => v == null ? 'יש לבחור חבר צוות' : null,
                          );
                        }
                        return const CircularProgressIndicator();
                      },
                    ),
                    const SizedBox(height: 16),

                    // Role selector
                    const Text(
                      'תפקיד',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<RoleType>(
                      value: _selectedRole,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'בחר תפקיד',
                        prefixIcon: Icon(Icons.work),
                      ),
                      items: RoleType.values.map((role) {
                        return DropdownMenuItem(
                          value: role,
                          child: Text(role.hebrewName),
                        );
                      }).toList(),
                      onChanged: (role) {
                        setState(() {
                          _selectedRole = role;
                          _roleError = null;
                        });
                      },
                      validator: (v) => v == null ? 'יש לבחור תפקיד' : null,
                    ),
                    const SizedBox(height: 16),

                    // Conflict warnings (if any)
                    if (_selectedEvent != null &&
                        _selectedTeamMember != null &&
                        _selectedRole != null)
                      FutureBuilder<List<String>>(
                        future: _checkConflicts(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                border: Border.all(color: Colors.red),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.warning, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text(
                                        'אזהרות קונפליקט:',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ...snapshot.data!.map(
                                    (warning) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '• $warning',
                                        style: const TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),

                    // Status selector
                    const Text(
                      'סטטוס',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<AssignmentStatus>(
                      value: _status,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: AssignmentStatus.values.map((status) {
                        return DropdownMenuItem(
                          value: status,
                          child: Text(status.hebrewName),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _status = v!),
                    ),
                    const SizedBox(height: 16),

                    // Notes
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'הערות',
                        hintText: 'הערות נוספות על השיבוץ',
                        prefixIcon: Icon(Icons.notes),
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<List<String>> _checkConflicts() async {
    if (_selectedEvent == null ||
        _selectedTeamMember == null ||
        _selectedRole == null) {
      return [];
    }

    // Temporary assignment for conflict checking - use slotIndex 0 as placeholder
    final assignment = Assignment(
      id: _isEditMode ? widget.assignment!.id : 'temp',
      eventId: _selectedEvent!.id,
      teamMemberId: _selectedTeamMember!.id,
      roleType: _selectedRole!,
      slotIndex: _isEditMode ? widget.assignment!.slotIndex : 0,
      status: _status,
      notes: _notesController.text.trim(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      event: _selectedEvent,
      teamMember: _selectedTeamMember,
    );

    return context.read<AssignmentBloc>().state is AssignmentsLoaded
        ? []
        : [];
  }

  /// Find the next available slot index for the given event and role
  int _getNextAvailableSlotIndex(String eventId, RoleType roleType) {
    final state = context.read<AssignmentBloc>().state;
    if (state is! AssignmentsLoaded) {
      return 0; // Default to first slot if assignments not loaded
    }

    // Get all assignments for this event+role combination
    final existingAssignments = state.assignments
        .where((a) => a.eventId == eventId && a.roleType == roleType)
        .toList();

    if (existingAssignments.isEmpty) {
      return 0; // First slot
    }

    // Find the highest slotIndex and return next one
    final maxIndex = existingAssignments
        .map((a) => a.slotIndex)
        .reduce((a, b) => a > b ? a : b);

    return maxIndex + 1;
  }
}
