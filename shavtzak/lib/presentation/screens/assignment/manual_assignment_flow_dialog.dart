import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/entities/event.dart';
import '../../../domain/entities/team_member.dart';
import '../../../core/constants/role_types.dart';
import '../../bloc/event/event_bloc.dart';
import '../../bloc/event/event_event.dart';
import '../../bloc/event/event_state.dart';
import '../../bloc/team/team_bloc.dart';
import '../../bloc/team/team_event.dart';
import '../../bloc/team/team_state.dart';

class ManualAssignmentFlowDialog extends StatefulWidget {
  const ManualAssignmentFlowDialog({super.key});

  @override
  State<ManualAssignmentFlowDialog> createState() => _ManualAssignmentFlowDialogState();
}

class _ManualAssignmentFlowDialogState extends State<ManualAssignmentFlowDialog> {
  int _currentStep = 0;
  Event? _selectedEvent;
  TeamMember? _selectedTeamMember;
  RoleType? _selectedRole;
  List<Event> _futureEvents = [];
  List<TeamMember> _teamMembers = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    // Load events and team members
    context.read<EventBloc>().add(const LoadEvents());
    context.read<TeamBloc>().add(const LoadActiveTeamMembers());
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<EventBloc, EventState>(
          listener: (context, state) {
            if (state is EventsLoaded) {
              setState(() {
                _futureEvents = state.events
                    .where((event) => !event.isPast)
                    .toList()
                  ..sort((a, b) => a.startDate.compareTo(b.startDate));
              });
            }
          },
        ),
        BlocListener<TeamBloc, TeamState>(
          listener: (context, state) {
            if (state is TeamLoaded) {
              setState(() {
                _teamMembers = state.members
                    .where((member) => member.isActive)
                    .toList()
                  ..sort((a, b) => a.name.compareTo(b.name));
              });
            }
          },
        ),
      ],
      child: AlertDialog(
        title: Text(
          'שיבוץ ידני חדש',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade700,
          ),
        ),
        content: SizedBox(
          width: 400,
          height: 500,
          child: Column(
            children: [
              // Progress indicator
              _buildProgressIndicator(),

              const SizedBox(height: 24),

              // Step content
              Expanded(
                child: _buildStepContent(),
              ),
            ],
          ),
        ),
        actions: [
          // Cancel button only - role selection auto-completes the assignment
          Semantics(
            identifier: 'manual-assignment-dialog-cancel-button',
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ביטול', style: TextStyle(color: Colors.red)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return Container(
          width: 60,
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: index <= _currentStep ? Colors.blue : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildEventSelectionStep();
      case 1:
        return _buildTeamMemberSelectionStep();
      case 2:
        return _buildRoleSelectionStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildEventSelectionStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'שלב 1 מתוך 3: בחירת אירוע',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'בחר אירוע עתידי שברצונך לשבץ לו איש צוות:',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _futureEvents.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_busy, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'לא נמצאו אירועים עתידיים',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _futureEvents.length,
                  itemBuilder: (context, index) {
                    final event = _futureEvents[index];
                    final isSelected = _selectedEvent?.id == event.id;

                    return Semantics(
                      identifier: 'event-selection-${event.id}',
                      child: Card(
                        elevation: isSelected ? 4 : 1,
                        color: isSelected ? Colors.blue.shade50 : Colors.white,
                        child: ListTile(
                          title: Text(
                            event.name,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Colors.blue.shade700 : Colors.black,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(event.dateRangeString),
                              if (event.location.isNotEmpty) Text('מיקום: ${event.location}'),
                              Text('${event.startTime} - ${event.endTime}'),
                            ],
                          ),
                          onTap: () {
                            setState(() {
                              _selectedEvent = isSelected ? null : event;
                            });
                            // Auto-advance to next step if event was selected
                            if (_selectedEvent != null) {
                              Future.delayed(const Duration(milliseconds: 300), () {
                                if (mounted) {
                                  setState(() {
                                    _currentStep = 1;
                                  });
                                }
                              });
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTeamMemberSelectionStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'שלב 2 מתוך 3: בחירת איש צוות',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'בחר איש צוות לשיבוץ באירוע "${_selectedEvent?.name}":',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _teamMembers.isEmpty
              ? const Center(
                  child: Text('לא נמצאו אנשי צוות פעילים'),
                )
              : ListView.builder(
                  itemCount: _teamMembers.length,
                  itemBuilder: (context, index) {
                    final teamMember = _teamMembers[index];
                    final isSelected = _selectedTeamMember?.id == teamMember.id;
                    final hasConflict = _hasDateConstraintConflict(teamMember);

                    return Semantics(
                      identifier: 'team-member-selection-${teamMember.id}',
                      child: Card(
                        elevation: isSelected ? 4 : 1,
                        color: isSelected ? Colors.blue.shade50 : Colors.white,
                        child: ListTile(
                          title: Text(
                            teamMember.name,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Colors.blue.shade700 : Colors.black,
                            ),
                          ),
                          subtitle: null, // uniqueKey not implemented yet
                          trailing: hasConflict
                              ? Icon(Icons.warning, color: Colors.orange.shade700)
                              : null,
                          onTap: () {
                            if (hasConflict) {
                              _showConstraintWarning(teamMember);
                            } else {
                              setState(() {
                                _selectedTeamMember = isSelected ? null : teamMember;
                              });
                              // Auto-advance to next step if team member was selected
                              if (_selectedTeamMember != null) {
                                Future.delayed(const Duration(milliseconds: 300), () {
                                  if (mounted) {
                                    setState(() {
                                      _currentStep = 2;
                                    });
                                  }
                                });
                              }
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRoleSelectionStep() {
    if (_selectedTeamMember == null) return const SizedBox.shrink();

    final availableRoles = _selectedTeamMember!.roleCapabilities.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList()
      ..sort((a, b) => a.hebrewName.compareTo(b.hebrewName));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'שלב 3 מתוך 3: בחירת תפקיד',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'בחר תפקיד עבור ${_selectedTeamMember!.name} באירוע "${_selectedEvent?.name}":',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: availableRoles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.work_off, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'לאיש צוות זה אין תפקידים זמינים',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: availableRoles.length,
                  itemBuilder: (context, index) {
                    final role = availableRoles[index];
                    final isSelected = _selectedRole == role;

                    return Semantics(
                      identifier: 'role-selection-${role.name}',
                      child: Card(
                        elevation: isSelected ? 4 : 1,
                        color: isSelected ? Colors.blue.shade50 : Colors.white,
                        child: InkWell(
                          onTap: () {
                            // Auto-complete assignment when role is selected
                            if (!isSelected) {
                              setState(() {
                                _selectedRole = role;
                              });
                              _finish();
                            }
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Text(
                              role.hebrewName,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? Colors.blue.shade700 : Colors.black,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  bool _hasDateConstraintConflict(TeamMember teamMember) {
    if (_selectedEvent == null) return false;

    return teamMember.constraints.any((constraint) {
      // Check if constraint overlaps with event dates
      final constraintStart = constraint.startDate;
      final constraintEnd = constraint.endDate ?? constraint.startDate;
      return !(constraintEnd.isBefore(_selectedEvent!.startDate) ||
               constraintStart.isAfter(_selectedEvent!.endDate));
    });
  }

  void _showConstraintWarning(TeamMember teamMember) {
    final conflictingConstraints = teamMember.constraints.where((constraint) {
      final constraintStart = constraint.startDate;
      final constraintEnd = constraint.endDate ?? constraint.startDate;
      return !(constraintEnd.isBefore(_selectedEvent!.startDate) ||
               constraintStart.isAfter(_selectedEvent!.endDate));
    }).toList();

    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              const Text('אזהרת סתירה'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ל${teamMember.name} יש מגבלות תאריך החופפות לאירוע "${_selectedEvent!.name}":'),
              const SizedBox(height: 12),
              ...conflictingConstraints.map((constraint) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.block, size: 16, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        constraint.endDate != null && !_isSameDay(constraint.startDate, constraint.endDate!)
                            ? '${_formatDate(constraint.startDate)} - ${_formatDate(constraint.endDate!)}'
                            : _formatDate(constraint.startDate),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ),
          actions: [
            Semantics(
              identifier: 'constraint-warning-dialog-cancel-button',
              child: TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('ביטול'),
              ),
            ),
            Semantics(
              identifier: 'constraint-warning-dialog-assign-anyway-button',
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  setState(() {
                    _selectedTeamMember = teamMember;
                  });
                  // Auto-advance to next step
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted) {
                      setState(() {
                        _currentStep = 2;
                      });
                    }
                  });
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('שבץ בכל זאת'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 0:
        return _selectedEvent != null;
      case 1:
        return _selectedTeamMember != null;
      case 2:
        return _selectedRole != null;
      default:
        return false;
    }
  }

  void _nextStep() {
    setState(() {
      _currentStep++;
    });
  }

  void _previousStep() {
    setState(() {
      _currentStep--;
    });
  }

  void _finish() {
    if (_selectedEvent != null && _selectedTeamMember != null && _selectedRole != null) {
      Navigator.of(context).pop({
        'event': _selectedEvent!,
        'teamMember': _selectedTeamMember!,
        'roleType': _selectedRole!,
      });
    }
  }
}